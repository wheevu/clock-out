/* combat.c -- combat state, entities, turn loop, piles.
 * Recreated after the bad rename destroyed the original implementation.
 * The matching header is combat.H (this file implements it). */
#include "combat.H"
#include "cards.H"

/* ---- physics (provided by physics module) ---- */
#ifndef PHYS_SHAPE_SPHERE
#define PHYS_SHAPE_SPHERE 0
#define PHYS_SHAPE_AABB   1
#define PHYS_SHAPE_PLANE  2
#endif
uint32_t phys_spawn(uint8_t shape, Vec3 pos, double mass, uint16_t owner);
void phys_burst(int steps);
void phys_init(void);

/* physics steps resolved at end of each player turn (deterministic).
 * The chair reliably reaches the enemy body by step ~12, so a modest
 * step count keeps event pressure low. */
#ifndef COMBAT_PHYS_STEPS
#define COMBAT_PHYS_STEPS 30
#endif

CombatState g_combat;

void shuffle_pile(uint32_t *arr, int n){
  if(!g_rng || n <= 1) return;
  for(int i = n - 1; i > 0; i--){
    int j = (int)(rng_u32(g_rng) % (uint32_t)(i + 1));
    uint32_t t = arr[i]; arr[i] = arr[j]; arr[j] = t;
  }
}

void draw_cards(int n){
  for(int k = 0; k < n; k++){
    if(g_combat.hand_n >= MAX_HAND) break;
    if(g_combat.draw_n == 0){
      if(g_combat.discard_n == 0) break;          /* nothing left to draw */
      g_combat.draw_n = g_combat.discard_n;
      for(int i = 0; i < g_combat.discard_n; i++) g_combat.draw_pile[i] = g_combat.discard[i];
      g_combat.discard_n = 0;
      shuffle_pile(g_combat.draw_pile, g_combat.draw_n);
    }
    g_combat.hand[g_combat.hand_n++] = g_combat.draw_pile[--g_combat.draw_n];
  }
}

/* ---- status ticking / start-of-turn damage ---- */

static void apply_hp_loss(Entity *e, int dmg){
  if(!e) return;
  if(dmg < 0) dmg = 0;
  e->hp -= dmg;
  if(e->hp < 0) e->hp = 0;
}

/* poison / leak / hazard deal deterministic start-of-turn damage, then decay.
 * Action statuses (weak/vuln/reveal) are NOT ticked here; they decrement in
 * status_end_of_action AFTER the owning entity's action, so a finite duration
 * of 2 affects exactly 2 relevant turns. */
static void status_start_of_turn(Entity *e){
  if(!e) return;
  int p = e->statuses[ST_POISON - 1];
  if(p > 0){ apply_hp_loss(e, p); e->statuses[ST_POISON - 1] = p - 1; }
  int l = e->statuses[ST_LEAK - 1];
  if(l > 0){ apply_hp_loss(e, l); e->statuses[ST_LEAK - 1] = l - 1; }
  int h = e->statuses[ST_HAZARD - 1];
  if(h > 0){ apply_hp_loss(e, h); e->statuses[ST_HAZARD - 1] = h - 1; }

  /* keep DOT duration bookkeeping in sync with the driving stacks */
  e->stturns[ST_POISON - 1] = e->statuses[ST_POISON - 1];
  e->stturns[ST_LEAK   - 1] = e->statuses[ST_LEAK   - 1];
  e->stturns[ST_HAZARD - 1] = e->statuses[ST_HAZARD - 1];
}

/* tick finite action-status durations once the entity's action/turn has
 * resolved; -1 stays permanent. */
static void status_end_of_action(Entity *e){
  if(!e) return;
  for(int i = 0; i < N_STATUS; i++){
    if(e->stturns[i] > 0){
      e->stturns[i]--;
      if(e->stturns[i] == 0) e->statuses[i] = 0;
    }
  }
}

/* ---- enemy intent (deterministic 4-step boss pattern) ---- */

static void combat_declare_intent(int turn){
  if(turn < 1) turn = 1;
  int step = (turn - 1) % 4;
  switch(step){
    case 0: g_combat.enemy_intent_type = COMBAT_INTENT_ATTACK;   g_combat.enemy_intent_value = 6; break;
    case 1: g_combat.enemy_intent_type = COMBAT_INTENT_BLOCK;    g_combat.enemy_intent_value = 8; break;
    case 2: g_combat.enemy_intent_type = COMBAT_INTENT_PRESSURE; g_combat.enemy_intent_value = 2; break;
    case 3: g_combat.enemy_intent_type = COMBAT_INTENT_GLITCH;   g_combat.enemy_intent_value = 3; break;
  }
}

static void execute_intent(void){
  Entity *en = &g_combat.enemy;
  Entity *pl = &g_combat.player;
  switch(g_combat.enemy_intent_type){
    case COMBAT_INTENT_ATTACK:
      deal_damage(en, pl, g_combat.enemy_intent_value);
      break;
    case COMBAT_INTENT_BLOCK:
      en->block += g_combat.enemy_intent_value;
      if(en->block < 0) en->block = 0;
      break;
    case COMBAT_INTENT_PRESSURE:
      apply_status(pl, ST_WEAK, g_combat.enemy_intent_value, 2);
      break;
    case COMBAT_INTENT_GLITCH:
      apply_status(pl, ST_HAZARD, g_combat.enemy_intent_value, 3);
      break;
  }
}

/* ---- turn lifecycle ---- */

static void start_player_turn(void){
  Entity *pl = &g_combat.player;
  status_start_of_turn(pl);          /* poison/leak/hazard + duration tick */
  pl->block = 0;                     /* block resets at start of player turn */
  int cap = pl->statuses[ST_ENERGYCAP - 1];
  int refill = pl->maxenergy - cap;  /* ST_ENERGYCAP lowers refill */
  if(refill < 0) refill = 0;
  pl->energy = refill;
  int need = 5 - g_combat.hand_n;    /* draw to fill hand to 5, not always 5 */
  if(need > 0) draw_cards(need);
}

static void end_turn_hand(void){
  int kept = 0;
  for(int i = 0; i < g_combat.hand_n; i++){
    uint32_t cid = g_combat.hand[i];
    CardDef *c = card_by_id(cid);
    if(c && c->retain){
      g_combat.hand[kept++] = cid;                 /* retained: stays in hand */
    } else if(c && c->exhaust){
      if(g_combat.exhaust_n < MAX_PILE) g_combat.exhaust[g_combat.exhaust_n++] = cid;
    } else {
      if(g_combat.discard_n < MAX_PILE) g_combat.discard[g_combat.discard_n++] = cid;
    }
  }
  g_combat.hand_n = kept;
}

void combat_start(uint32_t enemy_id){
  phys_init();                    /* fresh physics world per battle */
  g_combat.turn  = 1;
  g_combat.state = 0;

  /* full reset of both entities, including statuses/stturns */
  g_combat.player.id     = 1;
  g_combat.player.team   = 0;
  g_combat.player.maxhp  = 60; g_combat.player.hp = 60;
  g_combat.player.block  = 0;
  g_combat.player.energy = g_combat.player.maxenergy = 3;
  g_combat.player.pos    = (Vec3){0, 0, 0};
  g_combat.player.rank   = 1;
  g_combat.player.ai     = NULL;
  for(int i = 0; i < N_STATUS; i++){ g_combat.player.statuses[i] = 0; g_combat.player.stturns[i] = 0; }

  g_combat.enemy.id     = enemy_id;
  g_combat.enemy.team   = 1;
  g_combat.enemy.maxhp  = 40; g_combat.enemy.hp = 40;
  g_combat.enemy.block  = 0;
  g_combat.enemy.energy = g_combat.enemy.maxenergy = 3;
  g_combat.enemy.pos    = (Vec3){0, 0, 5};
  g_combat.enemy.rank   = 1;
  g_combat.enemy.ai     = NULL;
  for(int i = 0; i < N_STATUS; i++){ g_combat.enemy.statuses[i] = 0; g_combat.enemy.stturns[i] = 0; }

  g_combat.last_player_damage = 0;
  g_combat.last_enemy_damage  = 0;

  /* bodies: ground plane + the enemy's physics body */
  phys_spawn(PHYS_SHAPE_PLANE, (Vec3){0, 0, 0}, 0, 0);
  phys_spawn(PHYS_SHAPE_SPHERE, g_combat.enemy.pos, 1, (uint16_t)g_combat.enemy.id);

  /* draw pile seeded from the collection deck */
  g_combat.draw_n = g_deck_n;
  if(g_combat.draw_n > MAX_PILE) g_combat.draw_n = MAX_PILE;
  for(int i = 0; i < g_combat.draw_n; i++) g_combat.draw_pile[i] = g_deck[i];
  shuffle_pile(g_combat.draw_pile, g_combat.draw_n);
  g_combat.discard_n = 0;
  g_combat.exhaust_n = 0;
  g_combat.hand_n    = 0;
  draw_cards(5);

  /* deterministic first enemy intent (telegraphed before execution) */
  combat_declare_intent(1);
}

void combat_player_play(uint8_t hand_idx, uint32_t target_id){
  if(g_combat.state != 0) return;                       /* combat ended */
  if(hand_idx >= (uint8_t)g_combat.hand_n) return;      /* invalid hand */
  if(target_id != g_combat.player.id &&
     target_id != g_combat.enemy.id) return;            /* invalid target */
  uint32_t cid = g_combat.hand[hand_idx];
  CardDef *c = card_by_id(cid);
  if(!c) return;
  if(g_combat.player.energy < c->cost) return;          /* unaffordable */

  Entity *dst = (target_id == g_combat.enemy.id) ? &g_combat.enemy : &g_combat.player;
  run_effects(c, &g_combat.player, dst, 0);
  g_combat.player.energy -= c->cost;

  /* remove the played card from hand */
  for(int i = hand_idx; i < g_combat.hand_n - 1; i++) g_combat.hand[i] = g_combat.hand[i + 1];
  g_combat.hand_n--;
  /* exhausted cards leave the combat; everything else returns to the discard pile */
  if(c->exhaust){
    if(g_combat.exhaust_n < MAX_PILE) g_combat.exhaust[g_combat.exhaust_n++] = cid;
  } else {
    if(g_combat.discard_n < MAX_PILE) g_combat.discard[g_combat.discard_n++] = cid;
  }

  if(g_combat.enemy.hp  <= 0) g_combat.state = 1;
  if(g_combat.player.hp <= 0) g_combat.state = 2;
}

void combat_end_turn(void){
  if(g_combat.state != 0) return;

  /* 1) end-of-turn hand resolution: retain / exhaust / discard */
  end_turn_hand();

  /* 2) resolve physics weapons thrown this turn (chairs, desks, ...).
   *    Collisions emit EV_DEAL_DAMAGE routed to the correct entity; the
   *    existing event bridge applies the hp/block change. */
  phys_burst(COMBAT_PHYS_STEPS);
  ev_process_phase();
  if(g_combat.enemy.hp  <= 0){ g_combat.state = 1; return; }
  if(g_combat.player.hp <= 0){ g_combat.state = 2; return; }

  /* 3) the player's action window closed: tick their finite action statuses
   *    BEFORE any new statuses are applied this end-of-turn sequence. */
  status_end_of_action(&g_combat.player);

  /* 4) enemy acts on the CURRENT telegraphed intent. Its events are processed
   *    here, before start_player_turn resets player block, so block absorbs
   *    same-turn attacks and lethal outcomes stop the turn immediately. */
  Entity *en = &g_combat.enemy;
  en->block = 0;                  /* old block cleared at start of enemy turn */
  status_start_of_turn(en);       /* enemy poison/leak/hazard DOTs */
  if(en->hp <= 0){ g_combat.state = 1; return; }
  execute_intent();
  ev_process_phase();             /* apply emitted damage/heal NOW */
  if(en->hp <= 0){ g_combat.state = 1; return; }
  if(g_combat.player.hp <= 0){ g_combat.state = 2; return; }
  status_end_of_action(en);

  /* 5) declare the NEXT intent (telegraphed for the upcoming player turn) */
  if(g_combat.state == 0)
    combat_declare_intent(g_combat.turn + 1);

  /* 6) advance to the next player turn */
  g_combat.turn++;
  start_player_turn();

  if(g_combat.player.hp <= 0) g_combat.state = 2;
  if(g_combat.enemy.hp  <= 0) g_combat.state = 1;
}

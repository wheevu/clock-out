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

void combat_start(uint32_t enemy_id){
  g_combat.turn  = 1;
  g_combat.state = 0;

  g_combat.player.id     = 1;
  g_combat.player.team   = 0;
  g_combat.player.maxhp  = 60; g_combat.player.hp = 60;
  g_combat.player.block  = 0;
  g_combat.player.energy = g_combat.player.maxenergy = 3;
  g_combat.player.pos    = (Vec3){0, 0, 0};
  g_combat.player.rank   = 1;
  g_combat.player.ai     = NULL;

  g_combat.enemy.id     = enemy_id;
  g_combat.enemy.team   = 1;
  g_combat.enemy.maxhp  = 40; g_combat.enemy.hp = 40;
  g_combat.enemy.block  = 0;
  g_combat.enemy.energy = g_combat.enemy.maxenergy = 3;
  g_combat.enemy.pos    = (Vec3){0, 0, 5};
  g_combat.enemy.rank   = 1;
  g_combat.enemy.ai     = NULL;

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
}

void combat_player_play(uint8_t hand_idx, uint32_t target_id){
  if(hand_idx >= (uint8_t)g_combat.hand_n) return;
  uint32_t cid = g_combat.hand[hand_idx];
  CardDef *c = card_by_id(cid);
  if(!c) return;
  if(g_combat.player.energy < c->cost) return;   /* unaffordable */

  Entity *dst = (target_id == g_combat.enemy.id) ? &g_combat.enemy : &g_combat.player;
  run_effects(c, &g_combat.player, dst, 0);
  g_combat.player.energy -= c->cost;

  /* move the played card from hand to discard */
  for(int i = hand_idx; i < g_combat.hand_n - 1; i++) g_combat.hand[i] = g_combat.hand[i + 1];
  g_combat.hand_n--;
  if(g_combat.discard_n < MAX_PILE) g_combat.discard[g_combat.discard_n++] = cid;

  if(g_combat.enemy.hp  <= 0) g_combat.state = 1;
  if(g_combat.player.hp <= 0) g_combat.state = 2;
}

void combat_end_turn(void){
  /* discard whatever remains in hand */
  while(g_combat.hand_n > 0){
    uint32_t cid = g_combat.hand[0];
    for(int i = 0; i < g_combat.hand_n - 1; i++) g_combat.hand[i] = g_combat.hand[i + 1];
    g_combat.hand_n--;
    if(g_combat.discard_n < MAX_PILE) g_combat.discard[g_combat.discard_n++] = cid;
  }

  /* enemy acts, then physics resolves (chair collisions etc.) */
  Event ae = ai_choose(&g_combat.enemy);
  ev_emit(ae);
  phys_burst(30);

  /* run every queued event through the integration hook (ev_dispatch) */
  ev_process_phase();

  /* advance to the next player turn */
  g_combat.turn++;
  g_combat.player.energy = g_combat.player.maxenergy;
  if(g_combat.player.hp <= 0) g_combat.state = 2;
  if(g_combat.enemy.hp  <= 0) g_combat.state = 1;
  draw_cards(5);
}

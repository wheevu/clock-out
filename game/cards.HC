/* cards.c -- card registry, deck, effect interpreter, statuses.
 * Recreated after the bad rename destroyed the original implementation.
 * The matching header is cards.H (this file implements it). */
#include "cards.H"

/* ---- physics (provided by physics module; PHYS_POOL is canonical) ---- */
#include "../physics/phys.H"

/* ---- card registry (sparse, indexed by dense push) ---- */
#define MAX_CARD_REG 1024
static CardDef g_reg[MAX_CARD_REG];
static int     g_reg_n = 0;

/* the player's collection */
uint32_t g_deck[MAX_DECK];
int      g_deck_n = 0;

void card_register(CardDef d){
  if(d.id == 0 || d.id >= (uint32_t)MAX_CARD_REG) return;
  for(int i = 0; i < g_reg_n; i++){
    if(g_reg[i].id == d.id){ g_reg[i] = d; return; }   /* overwrite existing */
  }
  if(g_reg_n < MAX_CARD_REG) g_reg[g_reg_n++] = d;
}

CardDef *card_by_id(uint32_t id){
  for(int i = 0; i < g_reg_n; i++)
    if(g_reg[i].id == id) return &g_reg[i];
  return NULL;
}

void cards_init(void){
  /* deterministic 10-card starter so combat can always draw a full hand. */
  static const uint32_t starter[] = {1,2,3,1,2,3,1,2,3,1};
  g_deck_n = 0;
  for(int i = 0; i < 10 && i < MAX_DECK; i++) g_deck[g_deck_n++] = starter[i];
}

/* useful finite duration for card-applied statuses (permanent stays -1). */
static int default_status_turns(int st){
  switch(st){
    case ST_WEAK:      return 2;   /* card-applied weak: 2 turns */
    case ST_REVEAL:    return 2;   /* card-applied reveal: 2 turns */
    case ST_VULN:      return 2;
    case ST_POISON:    return 3;
    case ST_LEAK:      return 3;
    case ST_HAZARD:    return 3;
    case ST_ENERGYCAP: return -1;  /* persists until cleared */
    default:           return -1;
  }
}

void apply_status(Entity *e, int st, int mag, int turns){
  if(!e || st < 1 || st > N_STATUS) return;
  int idx = st - 1;
  e->statuses[idx] += mag;
  if(e->statuses[idx] < 0) e->statuses[idx] = 0;
  e->stturns[idx]  = turns;
}

void apply_heal(Entity *e, int amt){
  if(!e) return;
  if(amt < 0) amt = 0;
  e->hp += amt;
  if(e->hp > e->maxhp) e->hp = e->maxhp;
  if(e->hp < 0) e->hp = 0;
}

void apply_damage(uint32_t dst, int dmg){
  Entity *e = NULL;
  if(dst == g_combat.player.id) e = &g_combat.player;
  else if(dst == g_combat.enemy.id) e = &g_combat.enemy;
  if(!e) return;
  int d = dmg;
  if(d < 0) d = 0;
  if(e->block > 0){
    int ab = (d < e->block) ? d : e->block;
    e->block -= ab; d -= ab;
  }
  e->hp -= d;
  if(e->hp < 0) e->hp = 0;
}

/* weak reduces outgoing damage by 25% (floored, min 0);
 * vulnerable increases incoming damage by 50% (floored). */
void deal_damage(Entity *src, Entity *dst, int base){
  if(!src || !dst) return;
  int d = base;
  if(d < 0) d = 0;
  if(src->statuses[ST_WEAK - 1] > 0)    d = (d * 75) / 100;
  if(dst->statuses[ST_VULN - 1] > 0)    d = (d * 150) / 100;
  if(d < 0) d = 0;
  /* record post-modifier damage by source team */
  if(src->team == 1) g_combat.last_player_damage = d;  /* enemy -> player took it */
  else               g_combat.last_enemy_damage  = d;  /* player -> enemy took it */
  Event e;
  e.type = EV_DEAL_DAMAGE; e.src = src->id; e.dst = dst->id;
  e.a = d; e.b = 0; e.ref = 0; e.deferred = 0; e.seq = 0;
  ev_emit(e);
}

void run_effects(CardDef *c, Entity *src, Entity *dst, uint32_t target_body){
  if(!c) return;

  /* bodies spawned by THIS card, so OP_FORCE can hit every one of them.
   * Sized by the canonical physics pool; spawn attempts beyond free slots
   * are clamped, and every successful id is retained and forced. */
  uint32_t spawned[PHYS_POOL];
  int      nspawn = 0;

  for(int i = 0; i < c->nfx; i++){
    EffectOpT fx = c->fx[i];
    switch(fx.op){
      case OP_DAMAGE: {
        deal_damage(src, dst, fx.a);
        break;
      }
      case OP_BLOCK:
        if(src){ src->block += fx.a; if(src->block < 0) src->block = 0; }
        break;
      case OP_DRAW:
        draw_cards(fx.a);
        break;
      case OP_ENERGY:
        if(src){ src->energy += fx.a; if(src->energy < 0) src->energy = 0; }
        break;
      case OP_HEAL: {
        /* always heal the player/src, even when the card's target is the enemy. */
        Event e;
        e.type = EV_HEAL; e.src = src ? src->id : 0; e.dst = src ? src->id : 0;
        e.a = fx.a; e.b = 0; e.ref = 0; e.deferred = 0; e.seq = 0;
        ev_emit(e);
        break;
      }
      case OP_STATUS: {
        Entity *tgt = (fx.ref == 1 && dst) ? dst : src;
        if(tgt) apply_status(tgt, fx.a, fx.b, default_status_turns(fx.a));
        break;
      }
      case OP_FORCE: {
        Vec3 f = {0,0,0};
        double m = (double)fx.a;
        if(fx.b == 2){
          f = (Vec3){0, m, 0};
        } else if(fx.b == 1 && g_rng){
          f = (Vec3){ (rng_f64(g_rng)*2-1)*m, (rng_f64(g_rng)*2-1)*m, (rng_f64(g_rng)*2-1)*m };
        } else {
          Vec3 dir = {0,0,1};
          if(src && dst){ Vec3 d = vsub(dst->pos, src->pos); double L = vlen(d); if(L > 1e-9) dir = vscale(d, 1.0/L); }
          f = vscale(dir, m);
        }
        if(target_body != 0){
          phys_apply_force(target_body, f);              /* explicit target wins */
        } else if(nspawn > 0){
          for(int k = 0; k < nspawn; k++) phys_apply_force(spawned[k], f);
        } else if(dst){
          phys_apply_force(dst->id, f);
        }
        break;
      }
      case OP_GRAVITY:
        phys_set_gravity((fx.a == 1) ? (Vec3){0, 9.8, 0} : (Vec3){0, -9.8, 0});
        break;
      case OP_SPAWN: {
        int cnt = (fx.b > 0) ? fx.b : 1;
        uint8_t shape = (uint8_t)fx.a;
        int attempts = cnt;
        if(attempts > PHYS_POOL) attempts = PHYS_POOL;          /* clamp to pool */
        if(attempts > PHYS_POOL - nspawn) attempts = PHYS_POOL - nspawn;
        for(int k = 0; k < attempts; k++){
          uint32_t bid = phys_spawn(shape, src ? src->pos : (Vec3){0,0,0}, 1.0, 1);
          if(bid == 0) break;                                   /* pool full */
          spawned[nspawn++] = bid;                              /* retain all successes */
        }
        break;
      }
      case OP_STAT:
        if(src && fx.a == 1){
          src->hp += fx.b;                              /* STAT_HP */
          if(src->hp > src->maxhp) src->hp = src->maxhp;
          if(src->hp < 0) src->hp = 0;
        }
        break;
      case OP_END_CAMPAIGN: {
        Event e; e.type = EV_END_CAMPAIGN; e.src = src?src->id:0; e.dst = dst?dst->id:0;
        e.a = 0; e.b = 0; e.ref = 0; e.deferred = 0; e.seq = 0; ev_emit(e);
        break;
      }
      case OP_FLAG: {
        Event e; e.type = EV_SET_FLAG; e.src = src?src->id:0; e.dst = dst?dst->id:0;
        e.a = fx.a; e.b = fx.b; e.ref = fx.ref; e.deferred = 0; e.seq = 0; ev_emit(e);
        break;
      }
      case OP_REL: {
        Event e; e.type = EV_REL_CHANGE; e.src = src?src->id:0; e.dst = dst?dst->id:0;
        e.a = fx.a; e.b = fx.b; e.ref = fx.ref; e.deferred = 0; e.seq = 0; ev_emit(e);
        break;
      }
      case OP_ADD_CARD: {
        Event e; e.type = EV_ADD_CARD; e.src = src?src->id:0; e.dst = dst?dst->id:0;
        e.a = fx.a; e.b = fx.b; e.ref = fx.ref; e.deferred = 0; e.seq = 0; ev_emit(e);
        break;
      }
      default:
        break;
    }
  }
  ev_process_phase();
}

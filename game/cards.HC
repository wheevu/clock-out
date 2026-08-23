/* cards.c -- card registry, deck, effect interpreter, statuses.
 * Recreated after the bad rename destroyed the original implementation.
 * The matching header is cards.H (this file implements it). */
#include "cards.H"

/* ---- physics functions are defined by the physics module.
 *      Declared here so this TU compiles standalone; phys.H provides them
 *      at integration time. ---- */
#ifndef PHYS_SHAPE_SPHERE
#define PHYS_SHAPE_SPHERE 0
#define PHYS_SHAPE_AABB   1
#define PHYS_SHAPE_PLANE  2
#endif
uint32_t phys_spawn(uint8_t shape, Vec3 pos, double mass, uint16_t owner);
void phys_apply_force(uint32_t id, Vec3 f);
void phys_set_gravity(Vec3 g);

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

void apply_status(Entity *e, int st, int mag, int turns){
  if(!e || st < 1 || st > N_STATUS) return;
  int idx = st - 1;
  e->statuses[idx] += mag;
  e->stturns[idx]  = turns;
}

void apply_damage(uint32_t dst, int dmg){
  Entity *e = NULL;
  if(dst == g_combat.player.id) e = &g_combat.player;
  else if(dst == g_combat.enemy.id) e = &g_combat.enemy;
  if(!e) return;
  int d = dmg;
  if(e->block > 0){
    int ab = (d < e->block) ? d : e->block;
    e->block -= ab; d -= ab;
  }
  e->hp -= d;
  if(e->hp < 0) e->hp = 0;
}

void run_effects(CardDef *c, Entity *src, Entity *dst, uint32_t target_body){
  if(!c) return;
  uint32_t last_body = target_body;

  for(int i = 0; i < c->nfx; i++){
    EffectOpT fx = c->fx[i];
    switch(fx.op){
      case OP_DAMAGE: {
        Event e;
        e.type = EV_DEAL_DAMAGE; e.src = src ? src->id : 0; e.dst = dst ? dst->id : 0;
        e.a = fx.a; e.b = 0; e.ref = 0; e.deferred = 0; e.seq = 0;
        ev_emit(e);
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
        Event e;
        e.type = EV_HEAL; e.src = src ? src->id : 0; e.dst = dst ? dst->id : 0;
        e.a = fx.a; e.b = 0; e.ref = 0; e.deferred = 0; e.seq = 0;
        ev_emit(e);
        break;
      }
      case OP_STATUS: {
        Entity *tgt = (fx.ref == 1 && dst) ? dst : src;
        if(tgt) apply_status(tgt, fx.a, fx.b, -1);
        break;
      }
      case OP_FORCE: {
        uint32_t bid = (last_body != 0) ? last_body : (dst ? dst->id : 0);
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
        if(bid) phys_apply_force(bid, f);
        break;
      }
      case OP_GRAVITY:
        phys_set_gravity((fx.a == 1) ? (Vec3){0, 9.8, 0} : (Vec3){0, -9.8, 0});
        break;
      case OP_SPAWN: {
        int cnt = (fx.b > 0) ? fx.b : 1;
        uint8_t shape = (uint8_t)fx.a;
        for(int k = 0; k < cnt; k++){
          uint32_t bid = phys_spawn(shape, src ? src->pos : (Vec3){0,0,0}, 1.0, 1);
          if(k == 0) last_body = bid;
        }
        break;
      }
      case OP_STAT:
        if(src && fx.a == 1) src->hp += fx.b;   /* STAT_HP */
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

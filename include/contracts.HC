/* contracts.h -- shared types, structs, and API prototypes for 성광정보기술.
 * Portable C (compiles on macOS and 1:1 with HolyC). All modules include this.
 * HolyC port note: replace <stdint.h>/<stdio.h> with TempleOS equivalents; the
 * structs and function signatures are identical. */
#ifndef CONTRACTS_H
#define CONTRACTS_H
#include <stdint.h>
#include <stddef.h>
#include <math.h>

/* Game title: 퇴근 ("Clock Out"). Company within the game: 성광정보기술. */
#define GAME_TITLE "퇴근"
#define COMPANY_NAME "성광정보기술"

/* ===================== MATH ===================== */
typedef struct { double x, y, z; } Vec3;
static inline Vec3 vadd(Vec3 a, Vec3 b){ return (Vec3){a.x+b.x,a.y+b.y,a.z+b.z}; }
static inline Vec3 vsub(Vec3 a, Vec3 b){ return (Vec3){a.x-b.x,a.y-b.y,a.z-b.z}; }
static inline Vec3 vscale(Vec3 a, double s){ return (Vec3){a.x*s,a.y*s,a.z*s}; }
static inline double vdot(Vec3 a, Vec3 b){ return a.x*b.x+a.y*b.y+a.z*b.z; }
static inline double vlen2(Vec3 a){ return vdot(a,a); } /* squared length */
static inline double vlen(Vec3 a){ return sqrt(vlen2(a)); }
static inline Vec3 vnorm(Vec3 a){ double l=vlen(a); if(l<1e-12) return (Vec3){0,0,0}; l=1.0/l; return (Vec3){a.x*l,a.y*l,a.z*l}; }

typedef struct { double m[16]; } Mat4;
static inline Mat4 mat_ident(){ Mat4 r={{0}}; r.m[0]=r.m[5]=r.m[10]=r.m[15]=1.0; return r; }
static inline Mat4 mat_mul(Mat4 a, Mat4 b){
  Mat4 r={{0}};
  for(int i=0;i<4;i++) for(int j=0;j<4;j++){ double s=0; for(int k=0;k<4;k++) s+=a.m[i*4+k]*b.m[k*4+j]; r.m[i*4+j]=s; }
  return r;
}
Mat4 mat_perspective(double fovy, double asp, double n, double f);
Mat4 mat_lookat(Vec3 eye, Vec3 tgt, Vec3 up);
/* transform point (returns x,y,z,w); divide x,y,z by w for screen projection */
void mat_transform(Mat4 m, Vec3 p, double *x, double *y, double *z, double *w);

/* ===================== RNG (deterministic) ===================== */
typedef struct { uint64_t s; } RNG;
void rng_init(RNG *r, uint64_t seed);
uint64_t rng_u32(RNG *r);
int rng_range(RNG *r, int a, int b);   /* inclusive */
double rng_f64(RNG *r);                /* [0,1) */

/* ===================== EVENTS ===================== */
enum {
  EV_PLAY_CARD=1, EV_DRAW_CARD, EV_DISCARD_CARD, EV_APPLY_STATUS, EV_DEAL_DAMAGE,
  EV_HEAL, EV_SPAWN_BODY, EV_DESTROY_BODY, EV_APPLY_FORCE, EV_COLLISION,
  EV_DIALOGUE, EV_CHOICE, EV_STAT_CHANGE, EV_REL_CHANGE, EV_SET_FLAG,
  EV_START_BATTLE, EV_END_BATTLE, EV_LOAD_SCENE, EV_CAMERA_MOVE, EV_SCHEDULE,
  EV_MESSAGE, EV_TIME_ADVANCE, EV_SAVE, EV_SOUND, EV_CAMERA_SHAKE,
  EV_SET_GRAVITY, EV_END_CAMPAIGN, EV_REVEAL_INTENT, EV_UNLOCK_CHOICE, EV_ADD_CARD
};
typedef struct {
  uint16_t type;
  uint32_t src, dst;
  int32_t a, b;     /* generic params: damage, force, cost... */
  uint16_t ref;     /* string/def id */
  uint8_t deferred; /* 0 immediate, 1 next phase */
  uint32_t seq;     /* ordering key */
} Event;
void ev_init(void);
void ev_emit(Event e);
void ev_process_phase(void);          /* runs immediate + deferred, in order */
extern uint32_t g_ev_seq;
extern RNG *g_rng;                     /* single seeded stream */

/* ===================== CARDS ===================== */
enum CardType { C_ATTACK=1, C_DEFEND, C_TECH, C_SOCIAL, C_SYSTEM, C_CURSE, C_SPECIAL };
enum Archetype { A_PHYS=1, A_SOCIAL, A_SYSTEM, A_OVERWORK, A_DEFENSE };
enum EffectOp {
  OP_DAMAGE=1, OP_BLOCK, OP_DRAW, OP_ENERGY, OP_STATUS, OP_FORCE, OP_GRAVITY,
  OP_SPAWN, OP_HEAL, OP_STAT, OP_REL, OP_FLAG, OP_END_CAMPAIGN, OP_ADD_CARD
};
typedef struct { uint8_t op; int16_t a; int16_t b; uint16_t ref; } EffectOpT;
typedef struct {
  uint32_t id;
  uint8_t type, rarity, cost, archetype;
  uint16_t name_id, text_id, flavor_id;
  uint8_t upgrade_of;     /* 0 = base */
  uint8_t exhaust;        /* 소모 */
  uint8_t retain;         /* 보존 */
  uint8_t nfx;
  EffectOpT fx[4];
} CardDef;
CardDef *card_by_id(uint32_t id);
void card_register(CardDef d);

/* status ids */
enum Status {
  ST_BLOCK=1, ST_WEAK, ST_VULN, ST_POISON, ST_BLAME, ST_CREDIT, ST_LEAK,
  ST_REVEAL, ST_ENERGYCAP, ST_HAZARD, ST_SLEEP_BODY
};

/* ===================== TIME / SCHEDULER ===================== */
typedef struct { uint16_t year; uint8_t month, day, weekday; uint16_t minute; } GameTime;
GameTime time_add_min(GameTime t, int m);
int time_cmp(GameTime a, GameTime b);   /* -1,0,1 */

/* ===================== RELATIONSHIPS ===================== */
typedef struct {
  int8_t favor, trust, debt, suspicion, influence, respect, resentment, loyalty;
} RelState;

/* ===================== STRINGS (glyph tokens) ===================== */
/* A glyph string is an array of tokens.
 * token & 0x8000 => Korean syllable (jamo triple packed in low 15 bits: cho(5)|jung(5)|jong(5))
 * else: latin/digit/punct index into a small bitmap font (0..0x7FFF) */
typedef struct { uint16_t *tok; uint32_t len; } GStr;
GStr gstr_from_utf8(const char *s);     /* decompose Hangul -> jamo triples */
void gstr_free(GStr g);

/* global init for whole engine (calls sub-inits) */
void engine_init(uint64_t seed);

#endif

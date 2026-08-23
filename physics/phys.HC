/* phys.c -- minimal deterministic rigid-body physics engine.
 * Pool of 64 bodies, O(n^2) broad phase, sequential-impulse solver.
 * Only header needed is contracts.h (Vec3, Event, ev_emit). */
#include "phys.H"
#include "../include/contracts.HC"
#include <math.h>
#include <stdio.h>

static RigidBody g_pool[PHYS_POOL];
static uint32_t g_id_counter = 0;
static Vec3 g_gravity = {0, -9.8, 0};

typedef struct {
  int a, b;        /* indices into g_pool */
  Vec3 n;          /* contact normal, pointing from b to a */
  Vec3 point;
  double pen;      /* penetration depth */
  double jn;       /* accumulated normal impulse (>=0) */
} Contact;

static Contact g_contacts[PHYS_MAX_CONTACTS];
static int g_ncontacts;

/* ---- small helpers ---- */
static double s_abs(double x){ return x < 0 ? -x : x; }
static double s_min3(double x, double y, double z){ double m = x < y ? x : y; return m < z ? m : z; }
static Vec3 s_clamp(Vec3 v, Vec3 lo, Vec3 hi){
  return (Vec3){
    v.x < lo.x ? lo.x : (v.x > hi.x ? hi.x : v.x),
    v.y < lo.y ? lo.y : (v.y > hi.y ? hi.y : v.y),
    v.z < lo.z ? lo.z : (v.z > hi.z ? hi.z : v.z)
  };
}

/* ---- lifecycle ---- */
void phys_init(void){
  for(int i = 0; i < PHYS_POOL; i++){ g_pool[i].id = 0; g_pool[i].asleep = 0; g_pool[i].sleepTimer = 0; }
  g_id_counter = 0;
  g_gravity = (Vec3){0, -9.8, 0};
  g_ncontacts = 0;
}

uint32_t phys_spawn(uint8_t shape, Vec3 pos, double mass, uint16_t owner){
  int slot = -1;
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == 0){ slot = i; break; }
  }
  if(slot < 0) return 0; /* pool full */
  RigidBody *b = &g_pool[slot];
  b->id = ++g_id_counter;
  b->pos = pos;
  b->vel = (Vec3){0, 0, 0};
  b->angVel = (Vec3){0, 0, 0};
  b->mass = mass;
  b->invMass = mass > 0 ? 1.0 / mass : 0.0;
  b->shape = shape;
  b->owner = owner;
  b->asleep = 0;
  b->sleepTimer = 0;
  b->radius = 0.0;
  b->half = (Vec3){0, 0, 0};
  b->normal = (Vec3){0, 1, 0}; /* default plane normal (up) */
  if(shape == PHYS_SHAPE_SPHERE){ b->radius = 0.5; }
  else if(shape == PHYS_SHAPE_AABB){ b->half = (Vec3){0.5, 0.5, 0.5}; }
  /* plane: radius/half unused; normal stays up */
  return b->id;
}

void phys_apply_force(uint32_t id, Vec3 f){
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == id){
      RigidBody *b = &g_pool[i];
      b->vel = vadd(b->vel, vscale(f, b->invMass)); /* treat f as impulse */
      b->asleep = 0;
      b->sleepTimer = 0;
      return;
    }
  }
}

void phys_set_gravity(Vec3 g){ g_gravity = g; }

void phys_destroy(uint32_t id){
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == id){
      g_pool[i].id = 0;
      g_pool[i].asleep = 0;
      g_pool[i].sleepTimer = 0;
      Event e;
      e.type = EV_DESTROY_BODY;
      e.src = id; e.dst = 0; e.a = 0; e.b = 0; e.ref = g_pool[i].owner; e.deferred = 0; e.seq = 0;
      ev_emit(e);
      return;
    }
  }
}

/* ---- integration ---- */
static void integrate(double dt){
  for(int i = 0; i < PHYS_POOL; i++){
    RigidBody *b = &g_pool[i];
    if(b->id == 0) continue;
    if(b->shape == PHYS_SHAPE_PLANE) continue; /* static */
    if(b->asleep) continue;
    b->vel = vadd(b->vel, vscale(g_gravity, dt));
    b->pos = vadd(b->pos, vscale(b->vel, dt));
    b->vel = vscale(b->vel, PHYS_DAMP);
  }
}

/* sleep uses the RESOLVED velocity (after contacts cancel gravity), so a
 * resting body's speed is genuinely small, not the pre-collision fall speed. */
static void sleep_pass(double dt){
  for(int i = 0; i < PHYS_POOL; i++){
    RigidBody *b = &g_pool[i];
    if(b->id == 0 || b->shape == PHYS_SHAPE_PLANE || b->asleep) continue;
    if(vlen2(b->vel) < PHYS_SLEEP_SPEED * PHYS_SLEEP_SPEED){
      b->sleepTimer += dt;
      if(b->sleepTimer > PHYS_SLEEP_TIME){ b->asleep = 1; b->vel = (Vec3){0, 0, 0}; }
    } else {
      b->sleepTimer = 0;
    }
  }
}

/* ---- narrow phase: build contacts ---- */
static void add_contact(int a, int b, Vec3 n, Vec3 point, double pen){
  if(g_ncontacts >= PHYS_MAX_CONTACTS) return;
  Contact *c = &g_contacts[g_ncontacts++];
  c->a = a; c->b = b; c->n = n; c->point = point; c->pen = pen; c->jn = 0;
}

static void gen_contacts(void){
  g_ncontacts = 0;
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == 0) continue;
    for(int j = i + 1; j < PHYS_POOL; j++){
      if(g_pool[j].id == 0) continue;
      RigidBody *A = &g_pool[i];
      RigidBody *B = &g_pool[j];
      int sa = A->shape, sb = B->shape;

      /* sphere - sphere */
      if(sa == PHYS_SHAPE_SPHERE && sb == PHYS_SHAPE_SPHERE){
        Vec3 d = vsub(A->pos, B->pos);
        double dist2 = vlen(d);
        double rsum = A->radius + B->radius;
        if(dist2 < rsum * rsum){
          double dist = sqrt(dist2);
          Vec3 n = dist > 1e-9 ? vscale(d, 1.0 / dist) : (Vec3){0, 1, 0};
          double pen = rsum - dist;
          Vec3 point = vsub(A->pos, vscale(n, A->radius));
          add_contact(i, j, n, point, pen);
        }
        continue;
      }

      /* sphere - plane (either order) */
      if((sa == PHYS_SHAPE_SPHERE && sb == PHYS_SHAPE_PLANE) ||
         (sa == PHYS_SHAPE_PLANE && sb == PHYS_SHAPE_SPHERE)){
        int si = (sa == PHYS_SHAPE_SPHERE) ? i : j;
        int pi = (sa == PHYS_SHAPE_PLANE) ? i : j;
        RigidBody *S = &g_pool[si];
        RigidBody *P = &g_pool[pi];
        /* contact if sphere bottom below plane surface */
        double bottom = S->pos.y - S->radius;
        if(bottom < P->pos.y){
          double pen = P->pos.y - bottom; /* = P->pos.y - S->pos.y + S->radius */
          /* normal from plane to sphere = up */
          Vec3 n = (si == i) ? (Vec3){0, 1, 0} : (Vec3){0, -1, 0};
          Vec3 point = (Vec3){S->pos.x, P->pos.y, S->pos.z};
          add_contact(i, j, n, point, pen);
        }
        continue;
      }

      /* AABB - AABB */
      if(sa == PHYS_SHAPE_AABB && sb == PHYS_SHAPE_AABB){
        Vec3 d = vsub(A->pos, B->pos);
        double ox = (A->half.x + B->half.x) - s_abs(d.x);
        double oy = (A->half.y + B->half.y) - s_abs(d.y);
        double oz = (A->half.z + B->half.z) - s_abs(d.z);
        if(ox > 0 && oy > 0 && oz > 0){
          double pen = s_min3(ox, oy, oz);
          Vec3 n;
          if(ox <= oy && ox <= oz) n = (Vec3){ d.x >= 0 ? 1 : -1, 0, 0 };
          else if(oy <= oz)        n = (Vec3){ 0, d.y >= 0 ? 1 : -1, 0 };
          else                     n = (Vec3){ 0, 0, d.z >= 0 ? 1 : -1 };
          Vec3 point = vscale(vadd(A->pos, B->pos), 0.5);
          add_contact(i, j, n, point, pen);
        }
        continue;
      }

      /* sphere - AABB (either order) */
      if((sa == PHYS_SHAPE_SPHERE && sb == PHYS_SHAPE_AABB) ||
         (sa == PHYS_SHAPE_AABB && sb == PHYS_SHAPE_SPHERE)){
        int si = (sa == PHYS_SHAPE_SPHERE) ? i : j;
        int bi = (sa == PHYS_SHAPE_AABB) ? i : j;
        RigidBody *S = &g_pool[si];
        RigidBody *Bx = &g_pool[bi];
        Vec3 lo = vsub(Bx->pos, Bx->half);
        Vec3 hi = vadd(Bx->pos, Bx->half);
        Vec3 closest = s_clamp(S->pos, lo, hi);
        Vec3 d = vsub(S->pos, closest);
        double dist2 = vlen(d);
        if(dist2 < S->radius * S->radius){
          double dist = sqrt(dist2);
          Vec3 fromBox; /* points from box to sphere */
          if(dist > 1e-9){
            fromBox = vscale(d, 1.0 / dist);
          } else {
            /* center inside box: pick least-penetration axis */
            double px = Bx->half.x - s_abs(S->pos.x - Bx->pos.x);
            double py = Bx->half.y - s_abs(S->pos.y - Bx->pos.y);
            double pz = Bx->half.z - s_abs(S->pos.z - Bx->pos.z);
            if(px <= py && px <= pz) fromBox = (Vec3){ S->pos.x >= Bx->pos.x ? 1 : -1, 0, 0 };
            else if(py <= pz)        fromBox = (Vec3){ 0, S->pos.y >= Bx->pos.y ? 1 : -1, 0 };
            else                     fromBox = (Vec3){ 0, 0, S->pos.z >= Bx->pos.z ? 1 : -1 };
          }
          double pen = S->radius - dist;
          /* normal must point from b to a */
          Vec3 n = (si == i) ? fromBox : vscale(fromBox, -1.0);
          add_contact(i, j, n, closest, pen);
        }
        continue;
      }
      /* other combos (plane-plane, AABB-plane) produce no contact */
    }
  }
}

/* ---- solver ---- */
static void solve(double dt){
  (void)dt;
  const int ITER = 4;
  for(int it = 0; it < ITER; it++){
    for(int k = 0; k < g_ncontacts; k++){
      Contact *c = &g_contacts[k];
      RigidBody *A = &g_pool[c->a];
      RigidBody *B = &g_pool[c->b];
      /* effective inverse mass: static or asleep bodies are immovable */
      double ia = (A->asleep || A->shape == PHYS_SHAPE_PLANE) ? 0.0 : A->invMass;
      double ib = (B->asleep || B->shape == PHYS_SHAPE_PLANE) ? 0.0 : B->invMass;
      double sumInv = ia + ib;
      if(sumInv <= 0) continue;

      /* normal impulse */
      Vec3 vrel = vsub(A->vel, B->vel);
      double vn = vdot(vrel, c->n);
      double jn = -(1.0 + PHYS_RESTITUTION) * vn / sumInv;
      if(jn < 0) continue; /* separating */
      A->vel = vadd(A->vel, vscale(c->n, jn * ia));
      B->vel = vsub(B->vel, vscale(c->n, jn * ib));
      c->jn += jn;

      /* friction (tangent impulse, clamped to mu*jn) */
      vrel = vsub(A->vel, B->vel);
      double vn2 = vdot(vrel, c->n);
      Vec3 vt = vsub(vrel, vscale(c->n, vn2));
      double vtl2 = vlen(vt);
      if(vtl2 > 1e-9){
        Vec3 t = vscale(vt, 1.0 / sqrt(vtl2));
        double jt = -vdot(vrel, t) / sumInv;
        double maxf = PHYS_MU * jn;
        if(jt > maxf) jt = maxf;
        if(jt < -maxf) jt = -maxf;
        A->vel = vadd(A->vel, vscale(t, jt * ia));
        B->vel = vsub(B->vel, vscale(t, jt * ib));
      }
    }
  }
  /* positional correction (split by inverse mass) */
  for(int k = 0; k < g_ncontacts; k++){
    Contact *c = &g_contacts[k];
    RigidBody *A = &g_pool[c->a];
    RigidBody *B = &g_pool[c->b];
    double ia = (A->asleep || A->shape == PHYS_SHAPE_PLANE) ? 0.0 : A->invMass;
    double ib = (B->asleep || B->shape == PHYS_SHAPE_PLANE) ? 0.0 : B->invMass;
    double sumInv = ia + ib;
    if(sumInv <= 0) continue;
    double corr = c->pen * 0.5;
    A->pos = vadd(A->pos, vscale(c->n, corr * (ia / sumInv)));
    B->pos = vsub(B->pos, vscale(c->n, corr * (ib / sumInv)));
  }
}

void phys_step(double dt){
  integrate(dt);
  gen_contacts();
  solve(dt);
  sleep_pass(dt);
}

/* ---- burst + event emission ---- */
void phys_burst(int steps){
  for(int s = 0; s < steps; s++){
    phys_step(1.0 / 60.0);
    for(int k = 0; k < g_ncontacts; k++){
      Contact *c = &g_contacts[k];
      RigidBody *A = &g_pool[c->a];
      RigidBody *B = &g_pool[c->b];
      /* EV_COLLISION for every contact (logging) */
      Event ec;
      ec.type = EV_COLLISION;
      ec.src = A->id; ec.dst = B->id; ec.a = 0; ec.b = 0;
      ec.ref = A->owner; ec.deferred = 0; ec.seq = 0;
      ev_emit(ec);

      /* EV_DEAL_DAMAGE only between two dynamic bodies, strong impulse.
       * Route damage to the non-player owner: a player-thrown chair (owner 1)
       * hitting an enemy body deals damage to the enemy entity. */
      if(c->jn > PHYS_DMG_THRESHOLD && A->invMass > 0 && B->invMass > 0){
        int dmg = (int)(c->jn * 2.0);
        if(dmg < 0) dmg = 0;
        if(dmg > 9999) dmg = 9999;
        uint16_t oa = A->owner, ob = B->owner;
        uint32_t dmgdst = (oa == 1) ? (uint32_t)ob
                        : (ob == 1) ? (uint32_t)oa
                        : (uint32_t)ob;
        Event ed;
        ed.type = EV_DEAL_DAMAGE;
        ed.src = (uint32_t)oa; ed.dst = dmgdst; ed.a = dmg; ed.b = 0;
        ed.ref = oa; ed.deferred = 0; ed.seq = 0;
        ev_emit(ed);
      }
    }
  }
}

/* ---- queries ---- */
Vec3 phys_pos(uint32_t id){
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == id) return g_pool[i].pos;
  }
  return (Vec3){0, 0, 0};
}

uint8_t phys_asleep(uint32_t id){
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == id) return g_pool[i].asleep;
  }
  return 0;
}

double phys_ke(uint32_t id){
  for(int i = 0; i < PHYS_POOL; i++){
    if(g_pool[i].id == id){
      RigidBody *b = &g_pool[i];
      return 0.5 * b->mass * vlen(b->vel);
    }
  }
  return 0.0;
}

int phys_count(void){
  int n = 0;
  for(int i = 0; i < PHYS_POOL; i++) if(g_pool[i].id != 0) n++;
  return n;
}

void phys_debug(FILE *f){
  fprintf(f, "phys: %d active bodies\n", phys_count());
  for(int i = 0; i < PHYS_POOL; i++){
    RigidBody *b = &g_pool[i];
    if(b->id == 0) continue;
    fprintf(f, "  id=%u shape=%u owner=%u asleep=%u pos=(%.3f,%.3f,%.3f) vel=(%.3f,%.3f,%.3f)\n",
      b->id, b->shape, b->owner, b->asleep,
      b->pos.x, b->pos.y, b->pos.z,
      b->vel.x, b->vel.y, b->vel.z);
  }
}

/* tests/physics_test.c -- deterministic physics smoke tests.
 * Compile from repo root:
 *   cc -I../include -I. physics/phys.c core/math.c core/rng.c core/events.c core/strings.c tests/physics_test.c -o /tmp/physics_test && /tmp/physics_test
 */
#include "physics/phys.H"
#include <stdio.h>
#include <math.h>

/* ev_dispatch is implemented elsewhere; stub it here to observe emissions. */
static int g_collisions = 0;
static int g_damage = 0;
void ev_dispatch(Event e){
  if(e.type == EV_COLLISION) g_collisions++;
  else if(e.type == EV_DEAL_DAMAGE) g_damage++;
}

static int g_fail = 0;
#define CHECK(cond, msg) do { \
  if(cond){ printf("PASS: %s\n", msg); } \
  else { printf("FAIL: %s\n", msg); g_fail++; } \
} while(0)

int main(void){
  ev_init();
  phys_init();

  /* ---- Test 1: sphere drops onto ground plane and sleeps ---- */
  uint32_t plane = phys_spawn(PHYS_SHAPE_PLANE, (Vec3){0, 0, 0}, 0, 0);
  uint32_t ball  = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 5, 0}, 1.0, 1);
  CHECK(plane != 0 && ball != 0, "spawn plane + sphere");

  phys_burst(120); /* 2 seconds */
  ev_process_phase();

  Vec3 p = phys_pos(ball);
  printf("  ball final pos = (%.4f, %.4f, %.4f), asleep=%u\n", p.x, p.y, p.z, phys_asleep(ball));
  CHECK(fabs(p.y - 0.5) < 0.05, "sphere rests near y=0.5 (radius)");
  CHECK(phys_asleep(ball) == 1, "sphere falls asleep after resting");

  /* ---- Test 2: two spheres collide, exchange momentum, emit damage ---- */
  phys_init();
  g_collisions = 0; g_damage = 0;
  uint32_t a = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0, -1}, 1.0, 1);
  uint32_t b = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0,  1}, 1.0, 2);
  CHECK(a != 0 && b != 0, "spawn two spheres");

  /* ---- Geometry pass: phys_step so we can observe minimum separation ----
   * (restitution bounces them apart by the end, so final gap is not a good
   * collision signal; we track the closest approach instead.) */
  phys_init();
  a = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0, -1}, 1.0, 1);
  b = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0,  1}, 1.0, 2);
  Vec3 pa0 = phys_pos(a), pb0 = phys_pos(b);
  phys_apply_force(a, (Vec3){0, 0,  5}); /* push +z toward b */
  phys_apply_force(b, (Vec3){0, 0, -5}); /* push -z toward a */
  double minSep = 1e9;
  for(int s = 0; s < 60; s++){
    phys_step(1.0 / 60.0);
    Vec3 pa = phys_pos(a), pb = phys_pos(b);
    double dx = pa.x - pb.x, dy = pa.y - pb.y, dz = pa.z - pb.z;
    double d = sqrt(dx*dx + dy*dy + dz*dz);
    if(d < minSep) minSep = d;
  }
  Vec3 pa1 = phys_pos(a), pb1 = phys_pos(b);

  /* ---- Event pass: phys_burst emits EV_COLLISION / EV_DEAL_DAMAGE ---- */
  phys_init();
  a = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0, -1}, 1.0, 1);
  b = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0, 0,  1}, 1.0, 2);
  phys_apply_force(a, (Vec3){0, 0,  5});
  phys_apply_force(b, (Vec3){0, 0, -5});
  g_collisions = 0; g_damage = 0;
  phys_burst(60);
  ev_process_phase();

  printf("  a: (%.4f,%.4f,%.4f)  b: (%.4f,%.4f,%.4f)  minSep=%.4f\n",
    pa1.x, pa1.y, pa1.z, pb1.x, pb1.y, pb1.z, minSep);
  CHECK(fabs(pa1.z - pa0.z) > 0.01 || fabs(pb1.z - pb0.z) > 0.01, "spheres moved from start");
  CHECK(minSep < 1.0, "spheres actually touched (min separation < sum radii)");
  CHECK(g_collisions > 0, "collision events emitted");
  CHECK(g_damage > 0, "damage events emitted on strong dynamic-dynamic hit");

  if(g_fail == 0){ printf("\nALL PHYSICS TESTS PASSED\n"); return 0; }
  printf("\n%d PHYSICS TEST(S) FAILED\n", g_fail);
  return 1;
}

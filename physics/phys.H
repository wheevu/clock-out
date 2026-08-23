/* phys.H -- header for the minimal deterministic rigid-body physics engine.
 * Declarations only. Implementation lives in phys.HC.
 * Only shared header needed is contracts.HC (Vec3, Event, ev_emit, etc.). */
#ifndef PHYS_H
#define PHYS_H

#include "../include/contracts.HC"
#include <stdio.h>

/* ---- tunables ---- */
#define PHYS_POOL 64
#define PHYS_SHAPE_SPHERE 0
#define PHYS_SHAPE_AABB 1
#define PHYS_SHAPE_PLANE 2
#define PHYS_DMG_THRESHOLD 3.0
#define PHYS_SLEEP_SPEED 0.05
#define PHYS_SLEEP_TIME 0.5
#define PHYS_MAX_CONTACTS 2048
#define PHYS_DAMP 0.99          /* per-step velocity damping multiplier */
#define PHYS_RESTITUTION 0.2    /* bounciness */
#define PHYS_MU 0.5             /* friction coefficient */

/* ---- body ---- */
typedef struct {
  uint32_t id;
  Vec3 pos;
  Vec3 vel;
  Vec3 angVel;
  double mass;
  double invMass;
  uint8_t shape;
  uint16_t owner;
  uint8_t asleep;
  double sleepTimer;
  double radius;
  Vec3 half;
  Vec3 normal;
} RigidBody;

/* ---- API ---- */
void phys_init(void);
uint32_t phys_spawn(uint8_t shape, Vec3 pos, double mass, uint16_t owner);
void phys_apply_force(uint32_t id, Vec3 f);
void phys_set_gravity(Vec3 g);
void phys_step(double dt);
void phys_burst(int steps);
Vec3 phys_pos(uint32_t id);
uint8_t phys_asleep(uint32_t id);
double phys_ke(uint32_t id);
int phys_count(void);
void phys_destroy(uint32_t id);
void phys_debug(FILE *f);

#endif

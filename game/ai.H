/* ai.h -- utility combat AI. */
#ifndef AI_H
#define AI_H
#include "../include/contracts.HC"

/* forward decl so ai.h doesn't need combat.h (avoids include cycle) */
typedef struct Entity Entity;

typedef struct {
  uint8_t profile;     /* 0 aggressive,1 controller,2 summoner,3 balanced */
  int8_t  needs[6];    /* per-category weighting the AI prefers */
  uint8_t goal;        /* reserved intent hint */
} AIState;

/* choose the enemy's action for this turn; caller emits/executes the Event. */
Event ai_choose(Entity *e);

#endif

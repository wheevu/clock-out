/* combat.h -- combat state, entities, turn loop. */
#ifndef COMBAT_H
#define COMBAT_H
#include "../include/contracts.HC"
#include "ai.H"

#define MAX_PILE  256
#define MAX_DECK  256
#define MAX_HAND  10
#define N_STATUS  16

/* enemy intent constants (telegraphed one turn before execution) */
#define COMBAT_INTENT_ATTACK   1
#define COMBAT_INTENT_BLOCK    2
#define COMBAT_INTENT_PRESSURE 3
#define COMBAT_INTENT_GLITCH   4

typedef struct Entity {
  uint32_t id;
  int      hp, maxhp, block;
  uint8_t  team;                 /* 0 = player, 1 = enemy */
  int      energy, maxenergy;
  int      statuses[N_STATUS];   /* indexed by (Status-1) */
  int      stturns[N_STATUS];    /* remaining turns; -1 = permanent this combat */
  Vec3     pos;
  uint8_t  rank;
  AIState *ai;
} Entity;

typedef struct {
  Entity player;
  Entity enemy;
  uint32_t draw_pile[MAX_PILE];
  int      draw_n;
  uint32_t hand[MAX_HAND];
  int      hand_n;
  uint32_t discard[MAX_PILE];
  int      discard_n;
  uint32_t exhaust[MAX_PILE];
  int      exhaust_n;
  int      turn;
  int      state;   /* 0 running, 1 win, 2 lose */

  /* telegraphed enemy intent (one turn before execution) */
  int      enemy_intent_type;
  int      enemy_intent_value;
  int      last_player_damage;   /* damage the player took (post-modifier) */
  int      last_enemy_damage;    /* damage the enemy took (post-modifier) */
} CombatState;

extern CombatState g_combat;

/* setup / loop */
void combat_start(uint32_t enemy_id);
void combat_end_turn(void);
void combat_player_play(uint8_t hand_idx, uint32_t target_id);

/* pile helpers (shared with cards.c) */
void draw_cards(int n);
void shuffle_pile(uint32_t *arr, int n);

#endif

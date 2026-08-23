/* dsl.h -- scene scripting language (parser + interpreter) for 퇴근. */
#ifndef DSL_H
#define DSL_H
#include <stdint.h>
#include <stddef.h>
#include "../include/contracts.HC"

/* ===================== Player state ===================== */
typedef struct {
  int hp, energy, focus, nunchi, balls, perf, net, spec, mad, wlb;
  /* generic map for unknown stats like "stress" */
  char    gen_name[64][24];
  int     gen_val[64];
  int     gen_n;
} PlayerStats;

extern PlayerStats g_player;

/* ===================== External hooks (defined elsewhere) ===================== */
extern void on_combat_start(const char *name);
extern uint32_t card_id_by_name(const char *name);

/* ===================== Pending choice (set by dsl_run_scene) ===================== */
typedef struct {
  const char *label;    /* display text */
  const char *target;   /* node label to jump to */
  int         has_guard;
  int         guard_stat;  /* index into g_player, -1 if none */
  int         guard_min;   /* threshold for >= */
} ChoiceOption;

#define CHOICE_CAP 32
typedef struct {
  int        active;        /* 1 while awaiting dsl_choice */
  const char *scene_id;     /* scene the choice belongs to */
  int        n;
  ChoiceOption opt[CHOICE_CAP];
} PendingChoice;

extern PendingChoice g_pending_choice;

/* cards added by `card add` this run (real wiring done at integration) */
extern int g_cards_added;

/* ===================== API ===================== */
int  dsl_load(const char *path);     /* parse one .ssc file; returns 1 on ok */
void dsl_run_scene(const char *scene_id);
void dsl_choice(uint8_t idx);        /* apply chosen option, continue execution */

#endif /* DSL_H */

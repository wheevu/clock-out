/* scheduler.h -- deterministic, time-ordered scene scheduler (header). */
#ifndef SCHEDULER_H
#define SCHEDULER_H
#include "../include/contracts.HC"

#define SCHED_CAP 256
typedef struct {
  GameTime when;
  int      recurring;
  uint32_t id;
  char     node[64];
} ScheduledEvent;

void     sched_init(void);
void     sched_queue(GameTime when, const char *dsl_node, uint8_t recurring);
void     sched_advance(GameTime now);
int      sched_count(void);
GameTime time_add_min(GameTime t, int m);
int      time_cmp(GameTime a, GameTime b);

#endif /* SCHEDULER_H */

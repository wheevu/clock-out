/* scheduler.c -- deterministic, time-ordered scene scheduler. */
#include <math.h> /* contracts.h uses sqrt(); ensure declared before it is included */
#include "scheduler.H"
#include "dsl.H"
#include <string.h>

static ScheduledEvent g_q[SCHED_CAP];
static int  g_n = 0;
static uint32_t g_next_id = 1;

void sched_init(void){ g_n = 0; g_next_id = 1; }

/* insertion kept sorted by (when, id). */
static int sched_less(const ScheduledEvent *a, const ScheduledEvent *b){
  int c = time_cmp(a->when, b->when);
  if(c != 0) return c < 0;
  return a->id < b->id;
}

void sched_queue(GameTime when, const char *dsl_node, uint8_t recurring){
  if(g_n >= SCHED_CAP) return;
  ScheduledEvent e;
  e.when = when;
  e.recurring = recurring ? 1 : 0;
  e.id = g_next_id++;
  strncpy(e.node, dsl_node ? dsl_node : "", sizeof(e.node) - 1);
  e.node[sizeof(e.node) - 1] = 0;

  int i = g_n - 1;
  g_q[g_n] = e;
  while(i >= 0 && sched_less(&e, &g_q[i])){
    g_q[i + 1] = g_q[i];
    i--;
  }
  g_q[i + 1] = e;
  g_n++;
}

void sched_advance(GameTime now){
  int i = 0;
  while(i < g_n){
    if(time_cmp(g_q[i].when, now) <= 0){
      /* capture, then remove before running (a run may re-queue) */
      ScheduledEvent e = g_q[i];
      for(int k = i; k < g_n - 1; k++) g_q[k] = g_q[k + 1];
      g_n--;

      dsl_run_scene(e.node);
      if(e.recurring){
        GameTime nt = time_add_min(e.when, 1440); /* +1 day */
        sched_queue(nt, e.node, 1);
      }
      i = 0; /* queue may have changed order; rescan */
    } else {
      i++;
    }
  }
}

int sched_count(void){ return g_n; }

/* ===================== GameTime engine API (contracts.h) =====================
 * NOTE: these belong in core/ per contracts.h, but no implementation exists in
 * the repo yet and the brief's compile list omits a time source. They are
 * provided here so the NARRATIVE layer links and runs deterministically.
 * Replace with core/time.c at integration; signatures/semantics are identical. */
GameTime time_add_min(GameTime t, int m){
  int total = (int)t.minute + m;
  int day = (int)t.day;
  int wd = (int)t.weekday;
  while(total >= 1440){ total -= 1440; day++; wd = (wd % 7) + 1; }
  while(total < 0){ total += 1440; day--; wd = ((wd - 2 + 7) % 7) + 1; }
  GameTime r = t;
  r.day = (uint8_t)day;        /* may exceed 31; ordering still monotonic */
  r.minute = (uint16_t)total;
  r.weekday = (uint8_t)wd;
  return r;
}

int time_cmp(GameTime a, GameTime b){
  if(a.year != b.year)   return a.year   < b.year   ? -1 : 1;
  if(a.month != b.month) return a.month  < b.month  ? -1 : 1;
  if(a.day != b.day)     return a.day    < b.day    ? -1 : 1;
  if(a.weekday != b.weekday) return a.weekday < b.weekday ? -1 : 1;
  if(a.minute != b.minute)   return a.minute  < b.minute  ? -1 : 1;
  return 0;
}

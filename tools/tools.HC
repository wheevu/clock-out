/* tools.c -- dev debug overlay toolkit for 성광정보기술.
 * No graphics: pure state inspection. Loosely coupled to the narrative
 * module via extern prototypes (sched_count / campaign_act / msg_count).
 * Recreated after the bad rename; implements tools.H. */
#include "tools.H"
#include <stdio.h>

static int g_tool_on = 0;

/* narrative hooks (provided by the narrative module or test stubs) */
extern int sched_count(void);
extern int campaign_act(void);
extern int msg_count(void);

void tool_toggle(void){ g_tool_on = !g_tool_on; }
int  tool_is_on(void){ return g_tool_on; }

void tool_dump_state(void){
  printf("== 성광정보기술 debug dump ==\n");
  printf("overlay : %s\n", g_tool_on ? "on" : "off");
  printf("act     : %d\n", campaign_act());
  printf("sched q : %d\n", sched_count());
  printf("unread  : %d\n", msg_count());
}

void tool_frame(void){
  if(!g_tool_on) return;
  printf("[T] act=%d sched=%d msg=%d\n", campaign_act(), sched_count(), msg_count());
}

/* tools/tools.h -- dev debug overlay toolkit for 성광정보기술.
 * No graphics: pure state inspection. Loosely coupled to the narrative
 * module via extern prototypes (sched_count / campaign_act / msg_count). */
#ifndef TOOLS_H
#define TOOLS_H

/* Toggle the overlay on/off. */
void tool_toggle(void);
/* Current overlay state. */
int  tool_is_on(void);
/* Print a full state dump to stdout. */
void tool_dump_state(void);
/* Called once per frame; prints the one-line HUD when enabled. */
void tool_frame(void);

#endif

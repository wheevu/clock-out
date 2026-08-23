#include "contracts.HC"
#include <stdio.h>
#include <string.h>

#define EV_CAP 1024
static Event g_queue[EV_CAP];
static int g_head, g_tail;          /* ring: immediate queue */
static Event g_deferred[EV_CAP];
static int g_def_n;

uint32_t g_ev_seq = 0;
RNG *g_rng = NULL;                  /* set by engine_init via rng instance below */

void ev_init(void){ g_head=g_tail=0; g_def_n=0; g_ev_seq=0; }

void ev_emit(Event e){
  if(e.seq==0) e.seq = ++g_ev_seq;
  if(e.deferred){
    if(g_def_n < EV_CAP) g_deferred[g_def_n++] = e;
  } else {
    int nxt = (g_tail+1)%EV_CAP;
    if(nxt!=g_head){ g_queue[g_tail]=e; g_tail=nxt; }
    else fprintf(stderr,"[ev] queue full\n");
  }
}

/* handlers forward-declared by subsystems via a dispatch hook. */
extern void ev_dispatch(Event e);

static int cmp_ev(const void *p, const void *q){
  const Event *a=p, *b=q;
  if(a->seq!=b->seq) return a->seq < b->seq ? -1 : 1;
  if(a->type!=b->type) return a->type < b->type ? -1 : 1;
  return (a->src < b->src) ? -1 : (a->src > b->src ? 1 : 0);
}

void ev_process_phase(void){
  int guard = 0;
  /* run immediate queue */
  while(g_head != g_tail){
    Event e = g_queue[g_head]; g_head=(g_head+1)%EV_CAP;
    ev_dispatch(e);
    if(++guard > 4096){ fprintf(stderr,"[ev] explosion guard\n"); break; }
  }
  /* sort deferred by (seq,type,src) and run; they may emit new immediate (next phase) */
  /* simple insertion sort (small n) */
  for(int i=1;i<g_def_n;i++){
    Event key=g_deferred[i]; int j=i-1;
    while(j>=0 && cmp_ev(&g_deferred[j],&key)>0){ g_deferred[j+1]=g_deferred[j]; j--; }
    g_deferred[j+1]=key;
  }
  for(int i=0;i<g_def_n;i++) ev_dispatch(g_deferred[i]);
  g_def_n=0;
}

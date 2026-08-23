/* campaign.c -- act/flag state machine for the overall story.
 * Recreated implementation after a bad rename overwrote the original .c.
 * Act is derived from key flags: act = 1 + read_room + 2*boss_down. */
#include <string.h>
#include "campaign.H"

static char g_flags[CAMPAIGN_FLAG_CAP][64];
static int  g_flag_n = 0;

void campaign_init(void){
  memset(g_flags, 0, sizeof(g_flags));
  g_flag_n = 0;
}

static int flag_index(const char *f){
  for(int i=0;i<g_flag_n;i++) if(!strcmp(g_flags[i], f)) return i;
  return -1;
}

void campaign_set_flag(const char *f){
  if(!f) return;
  if(flag_index(f) >= 0) return; /* idempotent */
  if(g_flag_n < CAMPAIGN_FLAG_CAP){
    strncpy(g_flags[g_flag_n], f, 63); g_flags[g_flag_n][63] = 0;
    g_flag_n++;
  }
}

int campaign_has_flag(const char *f){
  return f && flag_index(f) >= 0;
}

void campaign_clear_flag(const char *f){
  int i = flag_index(f);
  if(i < 0) return;
  for(int k=i;k<g_flag_n-1;k++) strcpy(g_flags[k], g_flags[k+1]);
  g_flag_n--;
}

void campaign_tick(void){ /* act recomputed on read; kept for API symmetry */ }

int campaign_act(void){
  int act = 1;
  if(campaign_has_flag("read_room"))  act += 1;
  if(campaign_has_flag("boss_down"))  act += 2;
  return act;
}

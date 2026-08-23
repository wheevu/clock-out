/* relationships.c -- fixed array of 16 NPC relationship states. */
#include <math.h> /* contracts.h uses sqrt() in an inline; must be declared first */
#include "relationships.H"
#include <string.h>

static RelState g_rel[REL_CAP];
static char     g_names[REL_CAP][32];
static int      g_name_n = 0;

void rel_init(void){
  memset(g_rel, 0, sizeof(g_rel));
  memset(g_names, 0, sizeof(g_names));
  g_name_n = 0;
}

RelState *rel_get(uint16_t npc_id){
  if(npc_id >= REL_CAP) npc_id = (uint16_t)(npc_id % REL_CAP);
  return &g_rel[npc_id];
}

void rel_apply(uint16_t npc, int field, int delta){
  if(field < 0 || field >= REL_FIELD_COUNT) return;
  RelState *r = rel_get(npc);
  int8_t *p = (int8_t*)r + field;   /* fields are laid out in order, all int8_t */
  int v = (int)(*p) + delta;
  if(v > 127) v = 127;
  if(v < -128) v = -128;
  *p = (int8_t)v;
}

uint16_t rel_id_for_name(const char *name){
  if(!name) name = "";
  for(int i = 0; i < g_name_n; i++){
    if(strcmp(g_names[i], name) == 0) return (uint16_t)i;
  }
  if(g_name_n < REL_CAP){
    int id = g_name_n++;
    strncpy(g_names[id], name, sizeof(g_names[id]) - 1);
    g_names[id][sizeof(g_names[id]) - 1] = 0;
    return (uint16_t)id;
  }
  /* name table full: map deterministically */
  uint32_t h = 0;
  for(const char *p = name; *p; p++) h = (h * 31) + (uint8_t)(*p);
  return (uint16_t)(h % REL_CAP);
}

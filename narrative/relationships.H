/* relationships.h -- fixed array of NPC relationship states (header). */
#ifndef RELATIONSHIPS_H
#define RELATIONSHIPS_H
#include "../include/contracts.HC"

#define REL_CAP 16
enum RelField {
  REL_FAVOR=0, REL_TRUST, REL_DEBT, REL_SUSPICION, REL_INFLUENCE,
  REL_RESPECT, REL_RESENTMENT, REL_LOYALTY
};
#define REL_FIELD_COUNT 8

void      rel_init(void);
RelState *rel_get(uint16_t npc_id);
void      rel_apply(uint16_t npc, int field, int delta);
uint16_t  rel_id_for_name(const char *name);

#endif /* RELATIONSHIPS_H */

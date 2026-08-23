/* content/strings.h -- content string/registry API for 성광정보기술.
 * Declares the name->id map and the lookup helpers for card text.
 * Includes work only inside content/ and tools/. Narrative modules
 * (card_register/card_by_id, dsl_load, sched_count, campaign_act,
 * msg_count) are declared extern there and linked at integration. */
#ifndef CONTENT_STRINGS_H
#define CONTENT_STRINGS_H
#include <stdint.h>

/* Register the full content card set (calls card_register from contracts). */
void content_register_all(void);

/* name -> card id; returns 0 if unknown. */
uint32_t card_id_by_name(const char *name);

/* Korean display name / rules text / flavor for a card id (NULL if none). */
const char *card_name(uint32_t id);
const char *card_text(uint32_t id);
const char *card_flavor(uint32_t id);

#endif

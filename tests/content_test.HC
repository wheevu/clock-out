/* tests/content_test.c -- content + tools smoke test for 성광정보기술.
 *
 * The full integration build links the narrative modules (dsl, scheduler,
 * relationships, messenger, campaign) and the card registry, which live
 * in another worker's slice and are not present here. To verify THIS
 * slice standalone we provide minimal local stubs for those symbols;
 * the real definitions are linked at integration and replace these. */

#include "../include/contracts.HC"
#include "../content/strings.HC"
#include "../tools/tools.H"
#include <stdio.h>
#include <string.h>

/* ---- stub: card registry (normally in narrative/registry) ---- */
static CardDef g_reg[256];
static int     g_reg_n = 0;
void card_register(CardDef d) { if (g_reg_n < 256) g_reg[g_reg_n++] = d; }
CardDef *card_by_id(uint32_t id) {
  for (int i = 0; i < g_reg_n; i++) if (g_reg[i].id == id) return &g_reg[i];
  return NULL;
}

/* ---- stub: event dispatch hook (declared extern in core/events.c) ---- */
void ev_dispatch(Event e) { (void)e; }

/* ---- stubs: narrative module hooks ---- */
void dsl_load(const char *p) { (void)p; }     /* real parser in narrative */
int  sched_count(void)   { return 0; }
int  campaign_act(void)  { return 1; }
int  msg_count(void)     { return 0; }

static int fail = 0;
#define CHECK(cond, msg) do { if(!(cond)){ printf("FAIL: %s\n", msg); fail=1; } } while(0)

int main(void) {
  content_register_all();

  CHECK(g_reg_n == 20, "expected 20 cards registered");

  uint32_t id = card_id_by_name("의자 투척");
  CHECK(id != 0, "card_id_by_name(\"의자 투척\") > 0");
  CHECK(card_id_by_name("사직서") != 0, "card_id_by_name(\"사직서\") > 0");
  CHECK(card_id_by_name("없는카드") == 0, "unknown name maps to 0");

  const char *t = card_text(id);
  CHECK(t != NULL && t[0] != '\0', "card_text returns non-null for 의자 투척");
  CHECK(card_name(id) != NULL, "card_name returns non-null");
  CHECK(card_text(card_id_by_name("커피")) != NULL, "card_text for 커피");

  /* scene loads must not crash (real parse happens in narrative at integration) */
  dsl_load("content/scenes/late_office.ssc");
  dsl_load("content/scenes/boss_juin.ssc");

  /* tools */
  tool_toggle();
  CHECK(tool_is_on() == 1, "tool toggled on");
  tool_dump_state();
  tool_frame();
  tool_toggle();
  CHECK(tool_is_on() == 0, "tool toggled off");
  tool_frame(); /* should print nothing */

  if (fail) { printf("RESULT: FAIL\n"); return 1; }
  printf("RESULT: PASS (%d cards)\n", g_reg_n);
  return 0;
}

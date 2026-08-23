/* tests/narrative_test.c -- verifies the NARRATIVE layer.
 * Build from repo root:
 *   cc -I. -Iinclude -include math.h narrative/STAR.c core/math.c core/rng.c core/events.c core/strings.c tests/narrative_test.c -o /tmp/narr_test && /tmp/narr_test
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "narrative/relationships.H"
#include "narrative/scheduler.H"
#include "narrative/messenger.H"
#include "narrative/campaign.H"
#include "narrative/dsl.H"
#include "../include/contracts.HC"

/* ---- stubs for symbols defined by other modules (content/tools) ---- */
void on_combat_start(const char *n){ printf("combat:%s\n", n); }
uint32_t card_id_by_name(const char *n){ (void)n; return 1; }
void ev_dispatch(Event e){ (void)e; }

/* ---- tiny test harness ---- */
static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { \
  if(cond){ g_pass++; printf("PASS: %s\n", msg); } \
  else { g_fail++; printf("FAIL: %s\n", msg); } \
} while(0)

static GameTime mktime(uint16_t y, uint8_t mo, uint8_t d, uint8_t wd, uint16_t mi){
  GameTime t; t.year=y; t.month=mo; t.day=d; t.weekday=wd; t.minute=mi; return t;
}

/* write a tiny scene file for the scheduler test */
static void write_temp_scene(const char *path, const char *id){
  FILE *f = fopen(path, "w");
  if(!f) return;
  fprintf(f, "name: %s\n", id);
  fprintf(f, "bg: test\n");
  fprintf(f, "flag %s 1\n", id);
  fprintf(f, "return\n");
  fclose(f);
}

int main(void){
  /* ============ RELATIONSHIPS ============ */
  rel_init();
  rel_apply(0, REL_TRUST, 5);
  CHECK(rel_get(0)->trust == 5, "rel_apply increases trust");
  rel_apply(0, REL_TRUST, 3);
  CHECK(rel_get(0)->trust == 8, "rel_apply accumulates");
  rel_apply(0, REL_TRUST, 200); /* clamp to 127 */
  CHECK(rel_get(0)->trust == 127, "rel_apply clamps to int8 max");
  rel_apply(1, REL_FAVOR, -2);
  CHECK(rel_get(1)->favor == -2, "rel_apply negative delta");
  uint16_t kim0 = rel_id_for_name("김대리");
  CHECK(kim0 == rel_id_for_name("김대리"), "rel_id_for_name stable");

  /* ============ SCHEDULER ============ */
  sched_init();
  campaign_init();
  write_temp_scene("/tmp/sched_a.ssc", "sched_a");
  write_temp_scene("/tmp/sched_b.ssc", "sched_b");
  CHECK(dsl_load("/tmp/sched_a.ssc"), "load sched_a scene");
  CHECK(dsl_load("/tmp/sched_b.ssc"), "load sched_b scene");

  GameTime t1 = mktime(2025, 1, 1, 1, 0);
  GameTime t2 = time_add_min(t1, 100);
  /* queue out of order: later first, earlier second */
  sched_queue(t2, "sched_b", 0);
  sched_queue(t1, "sched_a", 0);
  CHECK(sched_count() == 2, "sched_queue two events");
  /* advance past both */
  sched_advance(time_add_min(t1, 200));
  CHECK(campaign_has_flag("sched_a"), "scheduled sched_a scene ran (flag set)");
  CHECK(campaign_has_flag("sched_b"), "scheduled sched_b scene ran (flag set)");
  CHECK(sched_count() == 0, "all due events consumed");

  /* ============ MESSENGER ============ */
  msg_init();
  uint32_t m1 = msg_deliver(0, "hi");
  uint32_t m2 = msg_deliver(0, "yo");
  CHECK(m1 == 1 && m2 == 2, "msg_deliver assigns sequential ids");
  CHECK(msg_count() == 2, "msg_count returns unread count");
  msg_mark_read(m1);
  CHECK(msg_count() == 1, "msg_mark_read reduces unread count");

  /* ============ CAMPAIGN ============ */
  campaign_init();
  campaign_set_flag("read_room");
  CHECK(campaign_has_flag("read_room") == 1, "campaign_set_flag then has_flag");
  campaign_tick();
  CHECK(campaign_act() == 2, "campaign_tick advances act on read_room");
  campaign_set_flag("boss_down");
  campaign_tick();
  CHECK(campaign_act() == 4, "campaign_tick advances act on boss_down");
  campaign_clear_flag("read_room");
  CHECK(campaign_has_flag("read_room") == 0, "campaign_clear_flag works");

  /* ============ DSL ============ */
  rel_init();
  campaign_init();
  g_cards_added = 0;
  memset(&g_player, 0, sizeof(g_player));

  CHECK(dsl_load("content/scenes/late_office.ssc"), "load late_office.ssc");
  CHECK(dsl_load("content/scenes/boss_juin.ssc"),  "load boss_juin.ssc");

  uint16_t kim = rel_id_for_name("김대리");
  int trust_before = rel_get(kim)->trust;
  g_player.nunchi = 8; /* enable the [nunchi>=6] option */

  dsl_run_scene("late_office");
  CHECK(g_pending_choice.active == 1, "dsl_run_scene stops at choice");

  /* find the 'smooth' option index */
  int smooth_idx = -1;
  for(int i=0;i<g_pending_choice.n;i++){
    if(strcmp(g_pending_choice.opt[i].target, "smooth")==0){ smooth_idx = i; break; }
  }
  CHECK(smooth_idx >= 0, "smooth option present (guard passed)");

  if(smooth_idx >= 0){
    dsl_choice((uint8_t)smooth_idx);
  }
  CHECK(campaign_has_flag("read_room") == 1, "choosing smooth sets read_room flag");
  CHECK(rel_get(kim)->trust == trust_before + 3, "smooth raised 김대리 trust by 3");
  CHECK(g_cards_added > 0, "smooth added a card (g_cards_added>0)");
  CHECK(g_pending_choice.active == 0, "scene returned (no pending choice)");

  /* boss_juin: choose charge which triggers combat_start */
  dsl_run_scene("boss_juin");
  CHECK(g_pending_choice.active == 1, "boss_juin stops at choice");
  dsl_choice(0); /* charge -> combat_start 주인 */
  CHECK(campaign_has_flag("boss_down") == 0, "boss_juin did not set boss_down (sanity)");

  /* ============ SUMMARY ============ */
  printf("\n==== %d passed, %d failed ====\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}

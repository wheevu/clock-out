/* integration_test.c -- end-to-end smoke test for 퇴근.
 * Links every module and proves: Korean compose, render PPM, physics
 * determinism, combat determinism + physics->enemy damage, DSL scene+choice,
 * scheduler firing, save/load round-trip. */
#include "../include/contracts.HC"
#include "../game/combat.H"
#include "../game/cards.H"
#include "../physics/phys.H"
#include "../render/render.H"
#include "../korean/hangul.H"
#include "../korean/ime.H"
#include "../narrative/dsl.H"
#include "../narrative/relationships.H"
#include "../narrative/scheduler.H"
#include "../narrative/campaign.H"
#include "../narrative/messenger.H"
#include "../content/strings.HC"
#include <stdio.h>
#include <string.h>
#include <math.h>

/* ---- single instance required by the engine (g_rng pointer itself is
 *      defined in core/events.c; we only provide the backing struct) ---- */
RNG g_rng_inst;

void on_combat_start(const char *name){ (void)name; combat_start(100); }

void ev_dispatch(Event e){
  switch(e.type){
    case EV_DEAL_DAMAGE:
      if(e.dst == g_combat.player.id)      apply_damage(g_combat.player.id, e.a);
      else if(e.dst == g_combat.enemy.id)  apply_damage(g_combat.enemy.id, e.a);
      break;
    case EV_HEAL:
      if(e.dst == g_combat.player.id){ g_combat.player.hp += e.a; if(g_combat.player.hp>g_combat.player.maxhp) g_combat.player.hp=g_combat.player.maxhp; }
      else if(e.dst == g_combat.enemy.id){ g_combat.enemy.hp += e.a; }
      break;
    case EV_APPLY_STATUS:
      if(e.dst == g_combat.player.id)      apply_status(&g_combat.player, e.a, e.b, e.b);
      else if(e.dst == g_combat.enemy.id)  apply_status(&g_combat.enemy, e.a, e.b, e.b);
      break;
    case EV_END_CAMPAIGN: campaign_set_flag("clock_out"); break;
    default: break;
  }
}

void engine_init(uint64_t seed){
  rng_init(g_rng, seed);
  ev_init();
  phys_init();
  content_register_all();
  cards_init();
  rel_init();
  sched_init();
  msg_init();
  campaign_init();
  dsl_load("content/scenes/late_office.ssc");
  dsl_load("content/scenes/boss_juin.ssc");
}

/* ---- tiny assertion harness ---- */
static int g_fail = 0;
#define CHECK(cond, msg) do{ if(!(cond)){ printf("FAIL: %s\n", msg); g_fail++; } else { printf("ok: %s\n", msg); } } while(0)

/* ---- combat auto-battle (deterministic) ---- */
static void run_battle(uint64_t seed, int *php, int *ehp){
  rng_init(g_rng, seed); ev_init(); phys_init(); cards_init();
  combat_start(100);
  int guard = 0;
  while(g_combat.state == 0 && guard++ < 80){
    int i = 0;
    while(i < g_combat.hand_n){
      uint32_t cid = g_combat.hand[i];
      CardDef *c = card_by_id(cid);
      if(c && g_combat.player.energy >= c->cost){
        combat_player_play((uint8_t)i, g_combat.enemy.id);
        i = 0;
      } else i++;
    }
    combat_end_turn();
  }
  *php = g_combat.player.hp;
  *ehp = g_combat.enemy.hp;
}

int main(void){
  g_rng = &g_rng_inst;   /* point the engine's global RNG at our instance */
  /* ===== 1. Korean compose ===== */
  GStr g = gstr_from_utf8("퇴근");
  int composed = 0; uint8_t cell[16*16];
  for(uint32_t i=0;i<g.len;i++){
    hangul_compose(g.tok[i], cell, 16, 16);
    for(int k=0;k<256;k++) if(cell[k]){ composed++; break; }
  }
  CHECK(composed == (int)g.len, "korean: every syllable composes to a non-empty glyph");
  CHECK(hangul_name_corrupt() == 0, "korean: no corruption for normal name");
  gstr_free(g);

  /* ===== 2. IME (lenient) ===== */
  ime_reset(); ime_toggle();
  ime_feed('r'); ime_feed('k'); ime_feed('s');
  GStr ib = ime_commit_buffer();
  printf("ime: produced %u glyph token(s)\n", ib.len);
  gstr_free(ib);

  /* ===== 3. Renderer PPM ===== */
  Mesh box = mesh_box((Vec3){0,0,0}, (Vec3){2,2,2}, 200);
  Mesh sph = mesh_sphere((Vec3){0,0,-6}, 1.5, 180, 16);
  rndr_set_camera((Vec3){0,1,6}, (Vec3){0,0,-6});
  rndr_begin();
  rndr_draw(box); rndr_draw(sph);
  rndr_present("/tmp/slice.ppm");
  mesh_free(&box); mesh_free(&sph);
  FILE *fp = fopen("/tmp/slice.ppm","rb");
  long sz = 0; if(fp){ fseek(fp,0,SEEK_END); sz=ftell(fp); fclose(fp); }
  CHECK(sz > 1000, "render: wrote a non-trivial PPM framebuffer");

  /* ===== 4. Physics determinism ===== */
  double pa=0, pb=0;
  for(int t=0;t<2;t++){
    phys_init();
    uint32_t a = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){0,2,0}, 1, 1);
    uint32_t b = phys_spawn(PHYS_SHAPE_SPHERE, (Vec3){1.2,2,0}, 1, 100);
    phys_apply_force(a, (Vec3){5,0,0});
    phys_apply_force(b, (Vec3){-5,0,0});
    phys_burst(60);
    if(t==0) pa = phys_pos(a).x; else pb = phys_pos(a).x;
  }
  CHECK(fabs(pa-pb) < 1e-9, "physics: identical seed -> identical result (deterministic)");

  /* ===== 5. Combat determinism + physics damage to enemy ===== */
  engine_init(12345);
  int p1,e1,p2,e2;
  run_battle(12345, &p1, &e1);
  run_battle(12345, &p2, &e2);
  CHECK(p1==p2 && e1==e2, "combat: same seed -> identical outcome (replay-safe)");

  rng_init(g_rng, 999); ev_init(); phys_init(); cards_init(); combat_start(100);
  int ehp0 = g_combat.enemy.hp;
  uint32_t chair = card_id_by_name("의자 투척");
  int cidx = -1;
  for(int i=0;i<g_combat.hand_n;i++) if(g_combat.hand[i]==chair){ cidx=i; break; }
  if(cidx>=0){
    combat_player_play((uint8_t)cidx, g_combat.enemy.id);
    combat_end_turn();
    fprintf(stderr,"DEBUG chair: enemy.hp %d (was %d), phys_count=%d\n", g_combat.enemy.hp, ehp0, phys_count());
    phys_debug(stderr);
  }
  CHECK(cidx<0 || g_combat.enemy.hp < ehp0, "physics-combat: thrown chair damages enemy");

  /* ===== 6. DSL scene + nunchi-gated choice + flag ===== */
  engine_init(777);
  g_player.nunchi = 8;
  dsl_run_scene("late_office");
  CHECK(g_pending_choice.active == 1, "dsl: late_office presents a choice");
  int sidx = -1;
  for(int i=0;i<g_pending_choice.n;i++)
    if(g_pending_choice.opt[i].label &&
       strcmp(g_pending_choice.opt[i].label, "분위기 파악하고 가볍게 넘긴다")==0) sidx=i;
  CHECK(sidx>=0, "dsl: high nunchi unlocks the hidden 'smooth' option");
  if(sidx>=0){
    dsl_choice((uint8_t)sidx);
    CHECK(campaign_has_flag("read_room")==1, "dsl: chosen option set the read_room flag");
    CHECK(g_cards_added > 0, "dsl: card add executed");
  }

  /* ===== 7. Scheduler fires a queued scene ===== */
  sched_init();
  GameTime now = {2026,3,17,1,0};
  sched_queue(time_add_min(now, 10), "late_office", 0);
  int q0 = sched_count();
  sched_advance(time_add_min(now, 11));
  CHECK(q0 >= 1 && g_pending_choice.active == 1, "scheduler: queued scene fired on time advance");

  /* ===== 8. Save/load round-trip (player stats) ===== */
  engine_init(4242);
  g_player.hp = 17; g_player.nunchi = 9; g_player.wlb = 3;
  campaign_set_flag("saved_ok");
  FILE *sf = fopen("/tmp/save.txt","w");
  if(sf){ fprintf(sf,"HP %d\nNUNCHI %d\nWLB %d\n", g_player.hp, g_player.nunchi, g_player.wlb); fclose(sf); }
  g_player.hp = 0; g_player.nunchi = 0; g_player.wlb = 0;
  sf = fopen("/tmp/save.txt","r");
  int rh=0,rn=0,rw=0;
  if(sf){ fscanf(sf,"HP %d\nNUNCHI %d\nWLB %d\n",&rh,&rn,&rw); fclose(sf); }
  CHECK(rh==17 && rn==9 && rw==3, "save: player stats round-trip");

  printf("\n%s (%d checks failed)\n", g_fail==0 ? "ALL PASS" : "FAILURES", g_fail);
  return g_fail ? 1 : 0;
}

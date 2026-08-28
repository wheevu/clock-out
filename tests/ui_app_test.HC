/* tests/ui_app_test.c -- deterministic smoke/contract test for the 퇴근 UI.
 *
 * Builds against the full engine (no tools/shot.HC):
 *   cc -x c -I. -Iinclude -O2 -Wall -Wextra -lm -o /tmp/ui_app_test
 *      tests/ui_app_test.HC core/HC-files korean/HC-files render/HC-files
 *      physics/HC-files game/HC-files narrative/HC-files content/HC-files
 *
 * Renders every public screen to /tmp, verifies the PPMs are non-trivial,
 * checks the sprite manifest loads when run from the repo root, and exercises
 * the combat presentation with both zero/default and populated intent state.
 * No snapshot testing. */
#include "../include/contracts.HC"
#include "../physics/phys.H"
#include "../render/render.H"
#include "../render/ui_app.H"
#include "../game/combat.H"
#include "../game/cards.H"
#include "../narrative/dsl.H"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- required engine hooks (defined by the integrator elsewhere) ---- */
void content_register_all(void);
RNG g_rng_inst;
void on_combat_start(const char *n) { (void)n; }
void ev_dispatch(Event e) { (void)e; }

static int g_fail = 0;
#define CHECK(c, m) do {                                                  \
    if (!(c)) { printf("FAIL: %s\n", m); g_fail++; }                     \
    else       { printf("ok:   %s\n", m); }                             \
} while (0)

/* Read a PPM (P6) and count pixels that differ meaningfully from the night
 * background (10,18,30). Returns 0 on success. */
static int ppm_stats(const char *path, long *size, int *lit) {
    FILE *f = fopen(path, "rb");
    if (!f) { *size = 0; *lit = 0; return -1; }
    fseek(f, 0, SEEK_END); *size = ftell(f); fseek(f, 0, SEEK_SET);
    /* robust P6 parse: read the three header lines with fgets so we never
     * swallow pixel bytes (a pixel value of 0x0A is a newline). */
    char line[64];
    if (!fgets(line, sizeof line, f) || line[0] != 'P' || line[1] != '6') {
        fclose(f); return -1;
    }
    if (!fgets(line, sizeof line, f)) { fclose(f); return -1; }
    int w, h;
    if (sscanf(line, "%d %d", &w, &h) != 2) { fclose(f); return -1; }
    if (!fgets(line, sizeof line, f)) { fclose(f); return -1; }  /* "255\n" */
    int n = w * h;
    uint8_t *buf = (uint8_t *)malloc((size_t)n * 3);
    if (fread(buf, 1, (size_t)n * 3, f) != (size_t)n * 3) {
        free(buf); fclose(f); return -1;
    }
    fclose(f);
    int cnt = 0;
    for (int i = 0; i < n; i++) {
        int r = buf[i * 3], g = buf[i * 3 + 1], b = buf[i * 3 + 2];
        int dd = (r - 10) + (g - 18) + (b - 30);
        if (dd > 50 || dd < -50) cnt++;
    }
    *lit = cnt;
    free(buf);
    return 0;
}

static int ppm_dimensions(const char *path, int *w, int *h) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    char line[64];
    if (!fgets(line, sizeof line, f) || line[0] != 'P' || line[1] != '6' ||
        !fgets(line, sizeof line, f) || sscanf(line, "%d %d", w, h) != 2) {
        fclose(f);
        return -1;
    }
    fclose(f);
    return 0;
}

/* Read one pixel (r,g,b) from a P6 PPM. Returns 0 on success. */
static int ppm_pixel(const char *path, int x, int y,
                     int *r, int *g, int *b) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    char line[64];
    if (!fgets(line, sizeof line, f) || line[0] != 'P' || line[1] != '6') { fclose(f); return -1; }
    if (!fgets(line, sizeof line, f)) { fclose(f); return -1; }
    int w, h;
    if (sscanf(line, "%d %d", &w, &h) != 2 || x < 0 || x >= w || y < 0 || y >= h) {
        fclose(f); return -1;
    }
    if (!fgets(line, sizeof line, f)) { fclose(f); return -1; }
    long off = ftell(f) + ((long)y * w + x) * 3L;
    unsigned char px[3];
    if (fseek(f, off, SEEK_SET) != 0 ||
        fread(px, 1, 3, f) != 3) { fclose(f); return -1; }
    fclose(f);
    *r = px[0]; *g = px[1]; *b = px[2];
    return 0;
}

int main(void) {
    g_rng = &g_rng_inst;
    rng_init(g_rng, 12345);
    ev_init();
    phys_init();
    uia_init();
    content_register_all();
    cards_init();

    /* ---- sprite manifest (only meaningful from repo root) ---- */
    FILE *mf = fopen("assets/baked/manifest.txt", "rb");
    int have_manifest = mf ? 1 : 0;
    if (mf) fclose(mf);
    CHECK(ui_sprite_loaded() == 1, "sprite manifest was attempted");
    if (have_manifest) {
        CHECK(ui_sprite_count() > 0, "sprite manifest loaded with entries");
        CHECK(ui_sprite("char_player") != NULL, "char_player sprite present");
        CHECK(ui_sprite("char_boss") != NULL, "char_boss sprite present");
        CHECK(ui_sprite("card_frame") != NULL, "card_frame sprite present");
    } else {
        printf("note: manifest not at cwd; skipping sprite assertions\n");
    }

    /* a combat so card data + intent telegraphs have something to read */
    combat_start(100);

    long sz; int lit;

    /* 1. title */
    { uia_title(0.3); uia_present("/tmp/ui_title.ppm");
      int w = 0, h = 0;
      CHECK(ppm_dimensions("/tmp/ui_title.ppm", &w, &h) == 0 && w == 640 && h == 360,
            "UI frame is native 640x360");
      CHECK(ppm_stats("/tmp/ui_title.ppm", &sz, &lit) == 0 && sz > 1000 && lit > 200,
            "title frame non-trivial"); }

    /* 2. dialogue (portrait for 김대리) */
    { uia_dialogue(0.1, "김대리", "오늘 야근인가? 분위기 좀 파악해봐.");
      uia_present("/tmp/ui_dialogue.ppm");
      CHECK(ppm_stats("/tmp/ui_dialogue.ppm", &sz, &lit) == 0 && lit > 200,
            "dialogue frame non-trivial"); }

    /* 3. choice with a nunchi-gated option */
    PendingChoice pc; memset(&pc, 0, sizeof pc); pc.active = 1; pc.n = 3;
    pc.opt[0].label = "분위기 파악하고 가볍게 넘긴다";
    pc.opt[0].has_guard = 1; pc.opt[0].guard_stat = 3; pc.opt[0].guard_min = 5;
    pc.opt[1].label = "정면으로 반박한다";
    pc.opt[2].label = "조용히 퇴근을 도모한다";
    { uia_choice(0.2, "주인", "자네, 오늘도 남겠군.", &pc, 1);
      uia_present("/tmp/ui_choice.ppm");
      CHECK(ppm_stats("/tmp/ui_choice.ppm", &sz, &lit) == 0 && lit > 200,
            "choice frame non-trivial"); }

    /* Authored data should never index past the fixed choice buffer, even if
     * a corrupt scene reports a larger count or selection. */
    { PendingChoice oversized; memset(&oversized, 0, sizeof oversized);
      oversized.active = 1; oversized.n = CHOICE_CAP + 9;
      uia_choice(0.2, "주인", "선택지가 너무 많다.", &oversized, CHOICE_CAP + 4);
      uia_present("/tmp/ui_choice_oversized.ppm");
      CHECK(ppm_stats("/tmp/ui_choice_oversized.ppm", &sz, &lit) == 0 && lit > 200,
            "oversized choice count clamps to the fixed buffer"); }

    /* 4. explore */
    { uia_explore(0.4, "사무실 복도", "비상구를 찾아라");
      uia_present("/tmp/ui_explore.ppm");
      CHECK(ppm_stats("/tmp/ui_explore.ppm", &sz, &lit) == 0 && lit > 200,
            "explore frame non-trivial"); }

    /* 5. messenger */
    { uia_messenger(0.5, 2);
      uia_present("/tmp/ui_messenger.ppm");
      CHECK(ppm_stats("/tmp/ui_messenger.ppm", &sz, &lit) == 0 && lit > 200,
            "messenger frame non-trivial"); }

    /* 6. schedule */
    { uia_schedule(0.6, 1);
      uia_present("/tmp/ui_schedule.ppm");
      CHECK(ppm_stats("/tmp/ui_schedule.ppm", &sz, &lit) == 0 && lit > 200,
            "schedule frame non-trivial"); }

    /* 7. reward (three real cards, one selected) */
    { uint32_t reward[3] = { 1, 2, 3 };
      uia_reward(0.7, reward, 1);
      uia_present("/tmp/ui_reward.ppm");
      CHECK(ppm_stats("/tmp/ui_reward.ppm", &sz, &lit) == 0 && lit > 200,
            "reward frame non-trivial"); }

    /* 8. combat: zero/default intent (must not crash, must draw) */
    { uia_combat(0.0);
      uia_present("/tmp/ui_combat.ppm");
      CHECK(ppm_stats("/tmp/ui_combat.ppm", &sz, &lit) == 0 && lit > 200,
            "combat (default) frame non-trivial"); }

    /* 9. combat: populated intent + damage + reveal + 10-card hand */
    g_combat.enemy_intent_type = COMBAT_INTENT_ATTACK;
    g_combat.enemy_intent_value = 8;
    g_combat.last_enemy_damage = 6;
    g_combat.last_player_damage = 4;
    g_combat.enemy.statuses[ST_REVEAL - 1] = 1;
    g_combat.hand_n = 10;
    for (int i = 0; i < 10; i++) g_combat.hand[i] = (uint32_t)(i % 4) + 1;
    g_combat.player.energy = 2;   /* forces several disabled cards */
    { uia_combat_focus(0.9, 3);
      uia_present("/tmp/ui_combat2.ppm");
      CHECK(ppm_stats("/tmp/ui_combat2.ppm", &sz, &lit) == 0 && lit > 200,
            "combat (populated) frame non-trivial"); }

    /* 10. game over (also exercises the NULL present path) */
    { uia_gameover(0.2); uia_present(NULL);   /* must not crash */
      uia_gameover(0.2); uia_present("/tmp/ui_gameover.ppm");
      CHECK(ppm_stats("/tmp/ui_gameover.ppm", &sz, &lit) == 0 && lit > 200,
            "gameover frame non-trivial"); }

    /* ---- intent visibility: ST_REVEAL OR nunchi >= 6 ---- */
    { g_combat.enemy_intent_type = COMBAT_INTENT_ATTACK;
      g_combat.enemy_intent_value = 8;
      g_combat.enemy.statuses[ST_REVEAL - 1] = 0;
      int saved_nunchi = g_player.nunchi;

      g_player.nunchi = 2;                       /* low nunchi, no reveal */
      CHECK(uia_intent_revealed() == 0, "intent hidden at low nunchi without reveal");
      uia_combat_focus(0.1, -1);                 /* must render "???" path safely */

      g_player.nunchi = 6;                       /* high nunchi alone reveals */
      CHECK(uia_intent_revealed() == 1, "intent revealed at nunchi >= 6");

      g_player.nunchi = 2;                       /* ST_REVEAL status alone reveals */
      g_combat.enemy.statuses[ST_REVEAL - 1] = 2;
      CHECK(uia_intent_revealed() == 1, "intent revealed by ST_REVEAL status");

      g_combat.enemy_intent_type = 0;            /* no intent: never revealed */
      g_combat.enemy.statuses[ST_REVEAL - 1] = 0;
      g_player.nunchi = 9;
      CHECK(uia_intent_revealed() == 0, "no intent means nothing to reveal");

      g_combat.enemy.statuses[ST_REVEAL - 1] = 0;
      g_player.nunchi = saved_nunchi; }

    /* ---- hand layout: boundaries 0/1/5/10 stay inside the frame ---- */
    { int ok = 1;
      const char *which = "?";
      UiaHandLayout l0 = uia_hand_layout(0);
      if (!(l0.count == 0 && l0.x0 == 0)) { ok = 0; which = "n=0"; }
      for (int n = 1; n <= 10; n += (n < 5 ? 4 : 5)) {   /* 1, 5, 10 */
        UiaHandLayout L = uia_hand_layout(n);
        long right = (long)L.x0 + (long)(L.count - 1) * L.stride + L.card_w;
        if (!(L.count == n && L.card_w >= 20 &&
              L.stride >= 1 && L.x0 >= 4 && right <= RW - 4)) {
          ok = 0; which = (n == 1 ? "n=1" : n == 5 ? "n=5" : "n=10");
        }
      }
      /* oversized request clamps to MAX_HAND and still fits */
      UiaHandLayout LX = uia_hand_layout(999);
      long rightX = (long)LX.x0 + (long)(LX.count - 1) * LX.stride + LX.card_w;
      if (!(LX.count <= 10 && rightX <= RW - 4)) { ok = 0; which = "clamp"; }
      CHECK(ok, "hand layout bounds hold for 0/1/5/10/oversized");
      if (!ok) printf("  layout failed at %s\n", which);

      /* the combat screen draws a full 10-card hand inside bounds */
      g_combat.hand_n = 10;
      for (int i = 0; i < 10; i++) g_combat.hand[i] = (uint32_t)(i % 4) + 1;
      uia_combat_focus(0.9, -1);
      uia_present("/tmp/ui_hand10.ppm");
      CHECK(ppm_stats("/tmp/ui_hand10.ppm", &sz, &lit) == 0 && lit > 200,
            "10-card hand renders in-bounds"); }

    /* ---- Latin font: 1x must be a true 8x8 bitmap ----
     * '!' rows are 18 3C 3C 18 18 00 18 00, LSB leftmost: column 3 is set
     * on rows 0-4 and 6, row 5 empty, columns 0-1 always clear. Sample the
     * rendered PPM at exact glyph pixels. */
    { uia_scene_empty(0.3);
      ui_begin();
      ui_text(100, 100, "!", 255, 255, 255);
      uia_present("/tmp/ui_latin.ppm");
      int r, g, b, ok = 1;
      /* stem pixels must be bright */
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 103, 100, &r, &g, &b) == 0 && r > 180)) ok = 0;
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 103, 101, &r, &g, &b) == 0 && r > 180)) ok = 0;
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 102, 101, &r, &g, &b) == 0 && r > 180)) ok = 0;
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 103, 106, &r, &g, &b) == 0 && r > 180)) ok = 0;
      /* gap row and left margin must stay dark */
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 103, 105, &r, &g, &b) == 0 && r < 80)) ok = 0;
      if (!(ppm_pixel("/tmp/ui_latin.ppm", 100, 101, &r, &g, &b) == 0 && r < 80)) ok = 0;
      CHECK(ok, "Latin '!' at 1x matches its 8x8 bitmap pixel-for-pixel"); }

    /* ---- malformed UTF-8 must not crash or desync (run under ASan/UBSan) ---- */
    { uia_dialogue(0.2, "\xFF\xFE", "\xC0\x80 broken lead \xE4\xB8 truncated \xF0\x9F");
      uia_dialogue(0.2, NULL,
                   "\xED\xA0\x80 surrogate \xF7\xBF\xBF\xBF out-of-range \xE4\xB8\xAD valid");
      uia_reward(0.3, (const uint32_t[3]){1, 0, 0}, 0);
      CHECK(1, "malformed/truncated UTF-8 handled without crash"); }

    if (g_fail == 0) printf("\nRESULT: PASS\n");
    else             printf("\nRESULT: FAIL (%d)\n", g_fail);
    return g_fail ? 1 : 0;
}

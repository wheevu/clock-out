/* render/ui_app.HC -- screen compositor for 퇴근.
 * Layers the true-color UI (ui.H) over the 3D palette scene (render.H).
 * Every uia_* screen draws the FULL frame: it calls rndr_begin (via a
 * uia_scene_*) and ui_begin itself, then the caller only needs uia_present.
 * Deterministic: reads game state and draws; never mutates shared state. */
#include "ui_app.H"
#include <math.h>
#include <string.h>

/* ---- private helpers ---- */

/* map a palette index (hue,step) to straight RGB bytes */
static void hcol(uint8_t hue, uint8_t step, uint8_t *r, uint8_t *g, uint8_t *b) {
    const uint8_t *pal = rndr_palette();
    uint8_t idx = RNDR_COL(hue, step);
    *r = pal[idx * 3];
    *g = pal[idx * 3 + 1];
    *b = pal[idx * 3 + 2];
}

/* forward-declared so this TU syntax-checks standalone; real defs in content/cards.HC */
const char *card_name(uint32_t id);
const char *card_text(uint32_t id);

/* =====================================================================
 * lifecycle
 * ===================================================================== */
void uia_init(void) {
    rndr_init();
    ui_init();
}

/* =====================================================================
 * scene overrides (3D world only)
 * ===================================================================== */
void uia_scene_office(double t) {
    rndr_begin();   /* clear palette fb + depth so frames never leak */
    rndr_set_camera((Vec3){0, 1.6, 5}, (Vec3){0, 0.6, 0});

    /* floor */
    Mesh floor = mesh_plane((Vec3){0, 0, 0}, (Vec3){0, 1, 0}, 8,
                            RNDR_COL(HUE_BROWN, RNDR_STEP_DARK));
    rndr_draw(floor); mesh_free(&floor);

    /* back wall */
    Mesh wall = mesh_plane((Vec3){0, 1.6, -3}, (Vec3){0, 0, 1}, 8,
                           RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(wall); mesh_free(&wall);

    /* 3 desks + monitors, in a row */
    for (int i = 0; i < 3; i++) {
        double dx = (i - 1) * 2.0;
        Mesh desk = mesh_box((Vec3){dx, 0.4, -0.4}, (Vec3){1.2, 0.1, 0.8},
                             RNDR_COL(HUE_BROWN, RNDR_STEP_MID));
        rndr_draw(desk); mesh_free(&desk);

        Mesh mon = mesh_box((Vec3){dx, 0.75, -0.4}, (Vec3){0.8, 0.5, 0.08},
                            RNDR_COL(HUE_TEAL, RNDR_STEP_MID));
        rndr_draw(mon); mesh_free(&mon);
    }

    /* ceiling light sways with t (voice of the room) */
    double lx = sin(t) * 0.3;
    Mesh light = mesh_box((Vec3){lx, 3.2, 0}, (Vec3){0.6, 0.1, 0.6},
                          RNDR_COL(HUE_GOLD, RNDR_STEP_LIT));
    rndr_draw(light); mesh_free(&light);
}

void uia_scene_boss(double t) {
    (void)t;
    rndr_begin();   /* clear palette fb + depth so frames never leak */
    rndr_set_camera((Vec3){0, 1.6, 5}, (Vec3){0, 0.6, 0});

    /* floor + dim indigo back wall */
    Mesh floor = mesh_plane((Vec3){0, 0, 0}, (Vec3){0, 1, 0}, 8,
                            RNDR_COL(HUE_BROWN, RNDR_STEP_DARK));
    rndr_draw(floor); mesh_free(&floor);

    Mesh wall = mesh_plane((Vec3){0, 1.6, -3}, (Vec3){0, 0, 1}, 8,
                           RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(wall); mesh_free(&wall);

    /* big vermilion desk */
    Mesh desk = mesh_box((Vec3){0, 0.6, 0}, (Vec3){2.5, 1.2, 1.0},
                         RNDR_COL(HUE_VERMILION, RNDR_STEP_MID));
    rndr_draw(desk); mesh_free(&desk);

    /* dark red "주인" silhouette far back */
    Mesh boss = mesh_box((Vec3){0, 1.4, -2.5}, (Vec3){0.8, 2.8, 0.4},
                         RNDR_COL(HUE_VERMILION, RNDR_STEP_DARK));
    rndr_draw(boss); mesh_free(&boss);

    /* single gold ceiling light */
    Mesh light = mesh_box((Vec3){0, 3.2, 0}, (Vec3){0.5, 0.1, 0.5},
                          RNDR_COL(HUE_GOLD, RNDR_STEP_LIT));
    rndr_draw(light); mesh_free(&light);
}

void uia_scene_empty(double t) {
    (void)t;
    rndr_begin();
    /* one dim gold lamp glint at screen center, written into the 3D fb */
    uint8_t *fb = (uint8_t *)rndr_fb();
    if (fb) fb[120 * RW + 160] = RNDR_COL(HUE_GOLD, RNDR_STEP_DARK);
}

/* =====================================================================
 * screens
 * ===================================================================== */
void uia_title(double t) {
    uia_scene_office(t);
    ui_begin();

    uint8_t dr, dg, db;   /* dark panel   */
    uint8_t vr, vg, vb;   /* vermilion    */
    uint8_t gr, gg, gb;   /* gold         */
    uint8_t wr, wg, wb;   /* off-white    */
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);

    /* translucent panel behind the title */
    ui_panel(60, 80, 200, 66, dr, dg, db, 200);

    /* title "퇴근" centered, scaled size 6 */
    int tw = ui_text_scaled(0, -1000, GAME_TITLE, 6, vr, vg, vb);
    ui_text_scaled(160 - tw / 2, 90, GAME_TITLE, 6, vr, vg, vb);

    /* subtitle "성광정보기술" centered, gold */
    int sw = ui_text(0, -1000, COMPANY_NAME, gr, gg, gb);
    ui_text(160 - sw / 2, 132, COMPANY_NAME, gr, gg, gb);

    /* thin gold underline */
    ui_fill_rect(60, 126, 200, 2, gr, gg, gb, 220);

    /* deterministic tagline near bottom, off-white */
    int lw = ui_text(0, -1000, "새벽 3시 17분.", wr, wg, wb);
    ui_text(160 - lw / 2, 210, "새벽 3시 17분.", wr, wg, wb);

    /* gold star sprites at each side */
    UISprite *star = ui_sprite("icon_star");
    if (star) {
        ui_blit(star, 30, 206, 1);
        ui_blit(star, 290, 206, 1);
    }
}

void uia_dialogue(double t, const char *speaker, const char *text) {
    int boss = (speaker && (strcmp(speaker, "주인") == 0 ||
                            strcmp(speaker, "사장") == 0));
    if (boss) uia_scene_boss(t);
    else      uia_scene_office(t);
    ui_begin();

    uint8_t dr, dg, db;
    uint8_t gr, gg, gb;
    uint8_t wr, wg, wb;
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);

    /* bottom dialogue box */
    ui_panel(16, 178, 288, 52, dr, dg, db, 220);

    /* nameplate: speaker or company */
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 16;
    ui_panel(20, 174, nw, 16, dr, dg, db, 220);
    ui_text(24, 177, label, gr, gg, gb);

    /* wrapped body text */
    if (text) ui_text_wrap(22, 184, 276, 40, text, wr, wg, wb);

    /* pulsing advance hint "▼" bottom-right of box */
    int hy = 178 + 52 - 12 + (int)(sin(t * 6.0) * 3.0);
    ui_text(292, hy, "▼", wr, wg, wb);
}

void uia_choice(double t, const char *speaker, const char *text,
                PendingChoice *c, int idx) {
    int boss = (speaker && (strcmp(speaker, "주인") == 0 ||
                            strcmp(speaker, "사장") == 0));
    if (boss) uia_scene_boss(t);
    else      uia_scene_office(t);
    ui_begin();

    uint8_t dr, dg, db;
    uint8_t gr, gg, gb;
    uint8_t wr, wg, wb;
    uint8_t sr, sg, sb;
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);

    /* dialogue box (reuse the dialogue layout) */
    ui_panel(16, 178, 288, 52, dr, dg, db, 220);
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 16;
    ui_panel(20, 174, nw, 16, dr, dg, db, 220);
    ui_text(24, 177, label, gr, gg, gb);
    if (text) ui_text_wrap(22, 184, 276, 40, text, wr, wg, wb);

    /* vertical choice list (right-aligned rows) */
    if (c && c->n > 0) {
        int x0 = 120, w0 = 180;
        for (int i = 0; i < c->n; i++) {
            int ry = 120 + i * 22;
            if (i == idx) {
                ui_panel(x0, ry, w0, 18, gr, gg, gb, 230);
                ui_text(x0 + 4, ry + 3, c->opt[i].label, wr, wg, wb);
            } else {
                ui_panel(x0, ry, w0, 18, sr, sg, sb, 200);
                ui_text(x0 + 4, ry + 3, c->opt[i].label, wr, wg, wb);
            }
        }
    }
}

void uia_combat(double t) {
    uia_scene_office(t);
    ui_begin();

    uint8_t gr, gg, gb;   /* gold      */
    uint8_t vr, vg, vb;   /* vermilion */
    uint8_t gn, gg2, gb2; /* green     */
    uint8_t wr, wg, wb;   /* white     */
    uint8_t dr, dg, db;   /* dark      */
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_JADE, RNDR_STEP_LIT, &gn, &gg2, &gb2);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);

    /* enemy nameplate + boss HP bar */
    const char *ename = g_combat.enemy.maxhp > 0 ? "주인" : "--";
    int ew = ui_text(16, 2, ename, wr, wg, wb);
    (void)ew;
    double epct = g_combat.enemy.maxhp > 0
                  ? (double)g_combat.enemy.hp / (double)g_combat.enemy.maxhp
                  : 0.0;
    ui_bar(16, 10, 288, 10, epct, vr, vg, vb, 255);

    /* intent strip (kept simple) */
    ui_text(16, 22, "의도: ???", gr, gg, gb);

    /* player resources top-left */
    double ppct = g_combat.player.maxhp > 0
                  ? (double)g_combat.player.hp / (double)g_combat.player.maxhp
                  : 0.0;
    ui_bar(16, 38, 120, 8, ppct, gn, gg2, gb2, 255);

    char buf[48];
    snprintf(buf, sizeof buf, "에너지 %d", g_combat.player.energy);
    ui_text(16, 50, buf, gr, gg, gb);

    /* energy pip row */
    int maxe = g_combat.player.maxenergy;
    for (int k = 0; k < maxe; k++) {
        if (k < g_combat.player.energy)
            ui_fill_rect(16 + k * 8, 64, 6, 6, gr, gg, gb, 255);
        else
            ui_fill_rect(16 + k * 8, 64, 6, 6, dr, dg, db, 255);
    }

    snprintf(buf, sizeof buf, "눈치 %d", g_player.nunchi);
    ui_text(16, 76, buf, wr, wg, wb);

    /* worker + boss sprites */
    UISprite *ps = ui_sprite("char_player");
    UISprite *bs = ui_sprite("char_boss");
    if (ps) ui_blit_fit(ps, 24, 100, 48, 80);
    if (bs) ui_blit_fit(bs, 248, 80, 56, 88);

    /* card hand -- fit within RW: shrink stride (overlap) if too wide */
    int hand_n = g_combat.hand_n;
    if (hand_n > 0) {
        int card_w = 52, gap = 6, stride = card_w + gap;
        int avail = RW - 8;                 /* 4px margin each side */
        if (hand_n > 0) {
            int min_stride = 34;            /* widest overlap allowed */
            while (hand_n * stride - gap > avail && stride > min_stride)
                stride--;
            /* if even min_stride is too wide, shrink card width too */
            if (hand_n * stride - gap > avail)
                card_w = avail / hand_n - (gap > 0 ? gap : 0);
        }
        int total = hand_n * stride - gap;
        int xstart = (RW - total) / 2;
        for (int i = 0; i < hand_n; i++) {
            uia_card(xstart + i * stride, 164, card_w, 70,
                     g_combat.hand[i], UIA_CARD_NORMAL);
        }
    }

    /* footer: turn / remaining deck */
    snprintf(buf, sizeof buf, "턴 %d", g_combat.turn);
    ui_text(16, 232, buf, wr, wg, wb);
    snprintf(buf, sizeof buf, "남은 덱 %d", g_combat.draw_n);
    ui_text(120, 232, buf, wr, wg, wb);

    /* end-state banners */
    if (g_combat.state == 1) {
        int bw = ui_text_scaled(0, -1000, "승리", 6, gr, gg, gb);
        ui_text_scaled(160 - bw / 2, 110, "승리", 6, gr, gg, gb);
    } else if (g_combat.state == 2) {
        int bw = ui_text_scaled(0, -1000, "사직", 6, vr, vg, vb);
        ui_text_scaled(160 - bw / 2, 110, "사직", 6, vr, vg, vb);
    }
}

void uia_card(int x, int y, int w, int h, uint32_t card_id, UiaCardSel sel) {
    if (sel == UIA_CARD_HOVER) y -= 4;   /* raised */

    uint8_t dr, dg, db;   /* dark base      */
    uint8_t sr, sg, sb;   /* slate border   */
    uint8_t wr, wg, wb;   /* white text     */
    uint8_t gr, gg, gb;   /* gold           */
    uint8_t vr, vg, vb;   /* vermilion      */
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);

    /* base panel */
    ui_panel(x, y, w, h, dr, dg, db, 235);

    /* inner art area */
    ui_panel(x + 3, y + 3, w - 6, h - 30, sr, sg, sb, 200);

    /* art fill by card type */
    CardDef *dc = card_by_id(card_id);
    uint8_t ah = HUE_INK, ar = 0, ag = 0, ab = 0;
    if (dc) {
        switch (dc->type) {
            case C_ATTACK:  ah = HUE_VERMILION; break;
            case C_DEFEND:  ah = HUE_TEAL;      break;
            case C_TECH:    ah = HUE_JADE;      break;
            case C_SOCIAL:  ah = HUE_PINK;      break;
            case C_SYSTEM:  ah = HUE_GOLD;      break;
            case C_CURSE:   ah = HUE_INK;       break;
            case C_SPECIAL: ah = HUE_VIOLET;    break;
            default:        ah = HUE_SLATE;     break;
        }
    }
    hcol(ah, RNDR_STEP_MID, &ar, &ag, &ab);
    ui_fill_rect(x + 3, y + 3, w - 6, h - 30, ar, ag, ab, 255);

    /* cost badge */
    int cost = dc ? dc->cost : 0;
    char cb[4];
    snprintf(cb, sizeof cb, "%d", cost);
    ui_fill_rect(x + 3, y + 3, 14, 14, gr, gg, gb, 255);
    ui_draw_rect(x + 3, y + 3, 14, 14, vr, vg, vb, 255);
    ui_text_align(x + 3, y + 3, 14, 14, cb, wr, wg, wb, 1);

    /* name */
    const char *name = card_name(card_id);
    if (!name) name = "?";
    ui_text(x + 18, y + 4, name, wr, wg, wb);

    /* body text */
    const char *body = card_text(card_id);
    if (body) ui_text_wrap(x + 3, y + h - 28, w - 6, 24, body, wr, wg, wb);
    else      ui_text(x + 3, y + h - 28, "—", wr, wg, wb);

    /* selection treatment */
    if (sel == UIA_CARD_HOVER) {
        ui_draw_rect(x, y, w, h, gr, gg, gb, 255);
        ui_draw_rect(x + 1, y + 1, w - 2, h - 2, gr, gg, gb, 255);
    } else if (sel == UIA_CARD_DISABLED) {
        ui_fill_rect(x, y, w, h, dr, dg, db, 120);
    } else { /* NORMAL */
        ui_draw_rect(x, y, w, h, sr, sg, sb, 255);
    }
}

void uia_gameover(double t) {
    uia_scene_empty(t);
    ui_begin();

    uint8_t dr, dg, db;
    uint8_t wr, wg, wb;
    uint8_t vr, vg, vb;
    hcol(HUE_CHARCOAL, RNDR_STEP_MID, &dr, &dg, &db);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);

    /* dark vignette */
    ui_fill_rect(0, 0, RW, RH, 0, 0, 0, 100);

    /* centered panel */
    ui_panel(60, 90, 200, 70, dr, dg, db, 220);

    /* "사직한다" */
    int tw = ui_text_scaled(0, -1000, "사직한다", 5, wr, wg, wb);
    ui_text_scaled(160 - tw / 2, 100, "사직한다", 5, wr, wg, wb);

    /* sub line in gray */
    int sw = ui_text(0, -1000, "퇴근은 꿈이었다.", wr, wg, wb);
    ui_text(160 - sw / 2, 140, "퇴근은 꿈이었다.", dr, dg, db);

    /* thin red line at bottom */
    ui_fill_rect(0, 236, RW, 2, vr, vg, vb, 220);
}

/* =====================================================================
 * present
 * ===================================================================== */
void uia_present(const char *ppm_path) {
    ui_present(ppm_path);
}

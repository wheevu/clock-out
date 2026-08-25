/* render/ui_app.HC -- screen compositor for 퇴근.
 * Layers the true-color UI (ui.H) over the 3D palette scene (render.H).
 * Every uia_* screen draws the FULL frame: it calls rndr_begin (via a
 * uia_scene_*) and ui_begin itself, then the caller only needs uia_present.
 * Deterministic: reads game state and draws; never mutates shared state.
 *
 * Visual direction: late-night Korean office horror, rendered like a 320x240
 * DOS / TempleOS game. Near-black indigo void, dirty fluorescent gold,
 * emergency vermilion, teal monitor spill, hard 1px frames, repeating
 * cubicles and city windows. Motion is diegetic: fluorescent flicker, clock
 * pulse, monitor scan, spark motion, warning flashes. */
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

/* forward-declared so this TU syntax-checks standalone; real defs in content. */
const char *card_name(uint32_t id);
const char *card_text(uint32_t id);

/* deterministic on/off flicker for a fixture seeded by `seed`. */
static int uia_flick(double t, int seed) {
    double v = sin(t * 9.0 + seed * 1.37) * 0.5 + 0.5;
    double n = sin(seed * 12.9898 + t * 4.7) * 43758.5453;
    n = n - floor(n);
    return (v > 0.18 + n * 0.5) ? 1 : 0;
}

/* corner brackets (sharp frame accents). */
static void uia_corners(uint8_t r, uint8_t g, uint8_t b, uint8_t a, int m) {
    int L = 10;
    ui_fill_rect(m, m, L, 1, r, g, b, a);            ui_fill_rect(m, m, 1, L, r, g, b, a);
    ui_fill_rect(RW - m - L, m, L, 1, r, g, b, a);   ui_fill_rect(RW - m - 1, m, 1, L, r, g, b, a);
    ui_fill_rect(m, RH - m - L, L, 1, r, g, b, a);   ui_fill_rect(m, RH - m - 1, 1, L, r, g, b, a);
    ui_fill_rect(RW - m - L, RH - m - L, L, 1, r, g, b, a);
    ui_fill_rect(RW - m - 1, RH - m - 1, 1, L, r, g, b, a);
}

/* ---- validated UTF-8 decoding (shared by glyph counting and slicing) ----
 *
 * Decodes one codepoint at p. Returns the byte length (1..4) and stores the
 * codepoint in *cp. Returns 0 for invalid or truncated input; callers then
 * advance exactly ONE byte so malformed text can never desync a loop or read
 * past the buffer. Every continuation byte is checked before being read:
 * the NUL terminator fails the continuation test, so truncation is safe.
 * Overlong encodings, UTF-16 surrogates, and values above U+10FFFF are all
 * rejected as invalid. */
static int uia_utf8_next(const unsigned char *p, uint32_t *cp) {
    unsigned char c = p[0];
    if (c == 0) return 0;
    if (c < 0x80) { *cp = c; return 1; }
    int n; uint32_t v;
    if      ((c & 0xE0) == 0xC0) { n = 2; v = c & 0x1Fu; }
    else if ((c & 0xF0) == 0xE0) { n = 3; v = c & 0x0Fu; }
    else if ((c & 0xF8) == 0xF0) { n = 4; v = c & 0x07u; }
    else return 0;                       /* stray continuation / 0xF8+ lead */
    for (int i = 1; i < n; i++) {
        unsigned char cc = p[i];
        if (cc == 0) return 0;           /* truncated before the NUL */
        if ((cc & 0xC0) != 0x80) return 0;
        v = (v << 6) | (uint32_t)(cc & 0x3F);
    }
    if (n == 2 && v < 0x80u)   return 0; /* overlong */
    if (n == 3 && v < 0x800u)  return 0; /* overlong */
    if (n == 4 && v < 0x10000u) return 0;/* overlong */
    if (v > 0x10FFFFu) return 0;
    if (v >= 0xD800u && v <= 0xDFFFu) return 0; /* surrogate */
    *cp = v;
    return n;
}

/* Advance to the next glyph boundary: returns bytes consumed (>=1). */
static int uia_utf8_step(const unsigned char *p) {
    uint32_t cp;
    int k = uia_utf8_next(p, &cp);
    return k > 0 ? k : 1;                /* invalid/truncated: one byte */
}

/* count glyphs (Korean syllable = 1, ASCII char = 1) in a UTF-8 string.
 * Malformed bytes each count as one glyph and consume one byte. */
static int uia_glyph_count(const char *s) {
    if (!s) return 0;
    int n = 0;
    const unsigned char *p = (const unsigned char *)s;
    while (*p) { p += uia_utf8_step(p); n++; }
    return n;
}

/* copy at most `maxg` glyphs starting at glyph offset `startg` into out.
 * Copies raw encoded bytes per glyph; malformed bytes advance one byte. */
static void uia_glyph_sub(const char *s, int startg, int maxg, char *out, int outsz) {
    out[0] = 0; if (!s || outsz < 2) return;
    const unsigned char *p = (const unsigned char *)s;
    for (int g = 0; g < startg && *p; g++) p += uia_utf8_step(p);
    char *o = out; int left = outsz - 1; int n = 0;
    while (*p && n < maxg) {
        int k = uia_utf8_step(p);
        if (k > left) break;             /* never split a glyph at the cap */
        for (int i = 0; i < k; i++) *o++ = (char)p[i];
        left -= k; p += k; n++;
    }
    *o = 0;
}

/* draw card body, line-wrapped by glyph count so it never overflows the card. */
static void uia_card_body(int x, int y, int w, int h, const char *s,
                          uint8_t r, uint8_t g, uint8_t b) {
    if (!s || h < 8) return;
    int maxg = w / 8; if (maxg < 1) maxg = 1;
    int total = uia_glyph_count(s);
    int off = 0, yy = y, lh = 9;
    while (off < total && yy + 8 <= y + h) {
        char line[64];
        uia_glyph_sub(s, off, maxg, line, sizeof line);
        if (line[0] == 0) break;
        ui_text(x, yy, line, r, g, b);
        yy += lh; off += maxg;
    }
}

/* Darken the near floor without flattening the palette-rendered room.
 * Sprites and interface elements are drawn after this pass, so they stay crisp. */
static void uia_world_grade(void) {
    uint8_t r, g, b, tr, tg, tb;
    hcol(HUE_CHARCOAL, 2, &r, &g, &b);
    hcol(HUE_TEAL, RNDR_STEP_DARK, &tr, &tg, &tb);
    ui_fill_rect(0, 108, RW, RH - 108, r, g, b, 170);
    ui_fill_rect(0, 108, RW, 1, tr, tg, tb, 100);
    for (int y = 119; y < RH; y += 12)
        ui_fill_rect(0, y, RW, 1, r, g, b, 45);
}

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
    rndr_begin();
    rndr_set_camera((Vec3){0, 1.6, 5.0}, (Vec3){0, 0.7, -0.5});

    /* room shell: floor, ceiling, side walls, back wall (near-black indigo) */
    Mesh floor = mesh_plane((Vec3){0, 0, 0}, (Vec3){0, 1, 0}, 20, RNDR_COL(HUE_BROWN, RNDR_STEP_DARK));
    rndr_draw(floor); mesh_free(&floor);
    Mesh ceil = mesh_plane((Vec3){0, 3.4, 0}, (Vec3){0, -1, 0}, 20, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(ceil); mesh_free(&ceil);
    Mesh lw = mesh_plane((Vec3){-4.4, 1.7, 0}, (Vec3){1, 0, 0}, 14, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(lw); mesh_free(&lw);
    Mesh rw = mesh_plane((Vec3){4.4, 1.7, 0}, (Vec3){-1, 0, 0}, 14, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(rw); mesh_free(&rw);
    Mesh bw = mesh_plane((Vec3){0, 1.7, -3.3}, (Vec3){0, 0, 1}, 16, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(bw); mesh_free(&bw);

    /* rear city windows: grid of small emissive panes, some flicker out */
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 7; i++) {
            double wx = -3.0 + i * 1.0;
            double wy = 0.6 + j * 0.8;
            int seed = i * 7 + j;
            int on = uia_flick(t * 0.7, seed);
            int hue = (seed % 5 == 0) ? HUE_VERMILION : (seed % 3 == 0 ? HUE_GOLD : HUE_TEAL);
            if (!on) hue = HUE_INDIGO;
            int step = on ? RNDR_STEP_LIT : RNDR_STEP_DARK;
            Mesh w = mesh_plane((Vec3){wx, wy, -3.25}, (Vec3){0, 0, 1}, 0.7, RNDR_COL(hue, step));
            rndr_draw(w); mesh_free(&w);
        }
    }

    /* cubicle banks: two sides, three rows deep, central aisle */
    for (int row = 0; row < 3; row++) {
        double z = -0.3 - row * 1.0;
        for (int side = -1; side <= 1; side += 2) {
            double cx = side * 1.7;
            Mesh desk = mesh_box((Vec3){cx, 0.42, z}, (Vec3){1.5, 0.1, 0.7}, RNDR_COL(HUE_BROWN, RNDR_STEP_MID));
            rndr_draw(desk); mesh_free(&desk);
            /* monitor face scans (brightness pulses with time) */
            int mseed = row * 2 + (side > 0 ? 1 : 0);
            int mstep = RNDR_STEP_MID + (int)(sin(t * 5.0 + mseed * 1.3) * 2.0);
            if (mstep < 6) mstep = 6; if (mstep > 14) mstep = 14;
            Mesh mon = mesh_box((Vec3){cx, 0.8, z - 0.15}, (Vec3){0.85, 0.5, 0.06}, RNDR_COL(HUE_TEAL, mstep));
            rndr_draw(mon); mesh_free(&mon);
            Mesh par = mesh_box((Vec3){cx, 1.1, z - 0.45}, (Vec3){0.08, 1.7, 0.75}, RNDR_COL(HUE_SLATE, RNDR_STEP_MID));
            rndr_draw(par); mesh_free(&par);
        }
    }

    /* fluorescent fixtures along ceiling; the middle one flickers (warning) */
    for (int f = 0; f < 3; f++) {
        double fx = -2.0 + f * 2.0;
        int on = (f == 1) ? uia_flick(t * 1.7, 50 + f) : 1;
        int stp = on ? RNDR_STEP_LIT : RNDR_STEP_DARK;
        Mesh fix = mesh_box((Vec3){fx, 3.3, 0.0}, (Vec3){1.4, 0.08, 0.3}, RNDR_COL(HUE_GOLD, stp));
        rndr_draw(fix); mesh_free(&fix);
    }
}

void uia_scene_boss(double t) {
    rndr_begin();
    rndr_set_camera((Vec3){0, 1.6, 5.0}, (Vec3){0, 0.9, -0.5});

    /* floor + back wall: near-black indigo void */
    Mesh floor = mesh_plane((Vec3){0, 0, 0}, (Vec3){0, 1, 0}, 20, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(floor); mesh_free(&floor);
    Mesh bw = mesh_plane((Vec3){0, 2.0, -3.2}, (Vec3){0, 0, 1}, 18, RNDR_COL(HUE_INDIGO, RNDR_STEP_DARK));
    rndr_draw(bw); mesh_free(&bw);

    /* long desk with a vermilion trim */
    Mesh desk = mesh_box((Vec3){0, 0.6, -0.6}, (Vec3){5.0, 1.1, 1.0}, RNDR_COL(HUE_BROWN, RNDR_STEP_DARK));
    rndr_draw(desk); mesh_free(&desk);
    Mesh trim = mesh_box((Vec3){0, 1.16, -0.6}, (Vec3){5.0, 0.06, 1.0}, RNDR_COL(HUE_VERMILION, RNDR_STEP_MID));
    rndr_draw(trim); mesh_free(&trim);

    /* server shrine: tall red pillars with flickering gold LEDs */
    for (int i = 0; i < 5; i++) {
        double px = -2.4 + i * 1.2;
        Mesh pil = mesh_box((Vec3){px, 1.6, -2.9}, (Vec3){0.32, 3.0, 0.32}, RNDR_COL(HUE_VERMILION, RNDR_STEP_DARK));
        rndr_draw(pil); mesh_free(&pil);
        for (int k = 0; k < 4; k++) {
            int on = uia_flick(t * 1.3, i * 10 + k);
            int stp = on ? RNDR_STEP_LIT : RNDR_STEP_DARK;
            Mesh led = mesh_box((Vec3){px, 0.7 + k * 0.7, -2.7}, (Vec3){0.12, 0.12, 0.06}, RNDR_COL(HUE_GOLD, stp));
            rndr_draw(led); mesh_free(&led);
        }
    }

    /* boss silhouette */
    Mesh boss = mesh_box((Vec3){0, 1.5, -2.4}, (Vec3){1.0, 3.0, 0.5}, RNDR_COL(HUE_VERMILION, RNDR_STEP_DARK));
    rndr_draw(boss); mesh_free(&boss);

    /* moving light sweeps across the room */
    double lx = sin(t * 0.8) * 2.2;
    Mesh lit = mesh_box((Vec3){lx, 3.2, 0.0}, (Vec3){0.5, 0.08, 0.5}, RNDR_COL(HUE_GOLD, RNDR_STEP_LIT));
    rndr_draw(lit); mesh_free(&lit);
}

void uia_scene_empty(double t) {
    rndr_begin();
    /* a broken neon sign glint near center, flickering on/off */
    int on = uia_flick(t * 2.0, 7);
    if (on) {
        uint8_t *fb = (uint8_t *)rndr_fb();
        if (fb) {
            uint8_t idx = RNDR_COL(HUE_VERMILION, RNDR_STEP_LIT);
            for (int y = 108; y < 132; y++)
                for (int x = 148; x < 172; x++)
                    if (x >= 0 && x < RW && y >= 0 && y < RH) fb[y * RW + x] = idx;
        }
    }
}

/* =====================================================================
 * shared portrait helper (dialogue / choice)
 * ===================================================================== */
static void uia_portrait(const char *speaker, int x, int y, int w, int h) {
    uint8_t gr, gg, gb, dr, dg, db, wr, wg, wb;
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);

    ui_fill_rect(x, y, w, h, dr, dg, db, 235);
    ui_draw_rect(x, y, w, h, gr, gg, gb, 230);

    UISprite *s = NULL;
    if (speaker && strcmp(speaker, "김대리") == 0) s = ui_sprite("char_kim");
    else if (speaker && (strcmp(speaker, "주인") == 0 || strcmp(speaker, "사장") == 0)) s = ui_sprite("char_boss");
    else s = ui_sprite("char_player");
    if (s) ui_blit_fit(s, x + 2, y + 2, w - 4, h - 4);

    const char *lab = speaker ? speaker : "회사";
    int nw = ui_text_width(lab) + 8;
    ui_fill_rect(x, y + h - 12, nw, 12, dr, dg, db, 240);
    ui_text(x + 4, y + h - 10, lab, gr, gg, gb);
}

/* =====================================================================
 * screens
 * ===================================================================== */
void uia_title(double t) {
    uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    /* sharp screen frame + corner brackets */
    ui_draw_rect(0, 0, RW, RH, vr, vg, vb, 200);
    uia_corners(gr, gg, gb, 230, 4);

    /* oversized 퇴근, left-biased, with a gold underline */
    int ts = 8;
    int tw = ui_text_scaled(0, -1000, GAME_TITLE, ts, vr, vg, vb);
    ui_text_scaled(26, 30, GAME_TITLE, ts, vr, vg, vb);
    ui_fill_rect(26, 30 + ts * 8 + 2, tw, 2, gr, gg, gb, 220);

    /* small system detail, top-right (03:17 timestamp) */
    ui_text(244, 10, "03:17", gr, gg, gb);
    ui_text(196, 20, "SEONGWANG OS", sr, sg, sb);
    ui_text(196, 29, "NIGHT SHIFT", sr, sg, sb);

    /* restrained company name, bottom-left */
    ui_text(26, 206, COMPANY_NAME, tr, tg, tb);

    /* tagline */
    ui_text(26, 222, "새벽 3시 17분, 아무도 퇴근하지 않았다.", wr, wg, wb);
}

void uia_dialogue(double t, const char *speaker, const char *text) {
    int boss = (speaker && (strcmp(speaker, "주인") == 0 || strcmp(speaker, "사장") == 0));
    if (boss) uia_scene_boss(t);
    else      uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, wr, wg, wb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);

    uia_portrait(speaker, 10, 22, 58, 96);

    /* bottom dialogue box */
    ui_fill_rect(14, 186, 292, 46, dr, dg, db, 235);
    ui_draw_rect(14, 186, 292, 46, gr, gg, gb, 220);
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 10;
    ui_fill_rect(16, 180, nw, 14, dr, dg, db, 240);
    ui_text(20, 183, label, gr, gg, gb);
    if (text) ui_text_wrap(18, 196, 284, 34, text, wr, wg, wb);

    /* pulsing advance hint */
    int hy = 186 + 46 - 12 + (int)(sin(t * 6.0) * 2.0);
    ui_text(296, hy, ">", wr, wg, wb);
}

void uia_choice(double t, const char *speaker, const char *text,
                PendingChoice *c, int idx) {
    int boss = (speaker && (strcmp(speaker, "주인") == 0 || strcmp(speaker, "사장") == 0));
    if (boss) uia_scene_boss(t);
    else      uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    uia_portrait(speaker, 10, 18, 56, 92);

    /* compact dialogue box at bottom */
    ui_fill_rect(14, 196, 292, 38, dr, dg, db, 235);
    ui_draw_rect(14, 196, 292, 38, gr, gg, gb, 220);
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 10;
    ui_fill_rect(16, 190, nw, 14, dr, dg, db, 240);
    ui_text(20, 193, label, gr, gg, gb);
    if (text) ui_text_wrap(18, 206, 284, 26, text, wr, wg, wb);

    /* vertical choice list (right side). selected row keeps its label visible. */
    if (c && c->n > 0) {
        int x0 = 78, w0 = 228;
        for (int i = 0; i < c->n; i++) {
            int ry = 20 + i * 30;
            int sel = (i == idx);
            if (sel) {
                ui_fill_rect(x0, ry, w0, 26, gr, gg, gb, 235);
                ui_draw_rect(x0, ry, w0, 26, wr, wg, wb, 255);
                ui_text(x0 + 6, ry + 5, c->opt[i].label, dr, dg, db);
            } else {
                ui_fill_rect(x0, ry, w0, 26, dr, dg, db, 220);
                ui_draw_rect(x0, ry, w0, 26, sr, sg, sb, 200);
                ui_text(x0 + 6, ry + 5, c->opt[i].label, wr, wg, wb);
            }
            /* nunchi / hidden-meaning treatment: a guard tag on gated options */
            if (c->opt[i].has_guard) {
                const char *tag = "[눈치]";
                int tw = ui_text_width(tag);
                ui_text(x0 + w0 - tw - 4, ry + 5, tag, tr, tg, tb);
            }
        }
    }
}

void uia_explore(double t, const char *location, const char *objective) {
    uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    /* player sprite standing in the central aisle */
    UISprite *ps = ui_sprite("char_player");
    if (ps) ui_blit_fit(ps, 132, 120, 60, 104);

    /* location plaque */
    const char *loc = location ? location : "사무실 통로";
    ui_fill_rect(8, 8, 180, 18, dr, dg, db, 235);
    ui_draw_rect(8, 8, 180, 18, gr, gg, gb, 220);
    ui_text(12, 12, "위치:", gr, gg, gb);
    ui_text(12 + ui_text_width("위치:") + 4, 12, loc, wr, wg, wb);

    /* objective line */
    const char *obj = objective ? objective : "비상구를 찾아라";
    ui_text(12, 32, "목표:", tr, tg, tb);
    ui_text(12 + ui_text_width("목표:") + 4, 32, obj, wr, wg, wb);

    /* compact HP / nunchi HUD, top-right */
    int hx = 210, hw = 102;
    ui_fill_rect(hx, 8, hw, 30, dr, dg, db, 230);
    ui_draw_rect(hx, 8, hw, 30, sr, sg, sb, 220);
    ui_text(hx + 4, 12, "HP", wr, wg, wb);
    double hpv = g_player.hp > 0 ? (double)g_player.hp / 60.0 : 0.0;
    if (hpv > 1) hpv = 1;
    ui_bar(hx + 24, 12, 50, 8, hpv, vr, vg, vb, 255);
    char hbuf[16];
    snprintf(hbuf, sizeof hbuf, "%d", g_player.hp);
    ui_text(hx + 78, 12, hbuf, wr, wg, wb);
    ui_text(hx + 4, 22, "눈치", tr, tg, tb);
    snprintf(hbuf, sizeof hbuf, "%d", g_player.nunchi);
    ui_text(hx + 30, 22, hbuf, wr, wg, wb);

    /* pulsing interaction prompt */
    int py = 210 + (int)(sin(t * 5.0) * 2.0);
    ui_text(116, py, "> E: 확인", gr, gg, gb);
}

void uia_messenger(double t, int selected) {
    uia_scene_empty(t);
    ui_begin();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);

    /* top bar */
    ui_fill_rect(0, 0, RW, 14, dr, dg, db, 240);
    ui_draw_rect(0, 0, RW, 14, gr, gg, gb, 220);
    ui_text(6, 3, "사내 메신저 v3.1", gr, gg, gb);
    ui_text(250, 3, "03:17", sr, sg, sb);

    /* split between sender list and message pane */
    ui_draw_rect(120, 14, 1, RH - 26, sr, sg, sb, 200);

    /* creepy inbox data (deterministic) */
    static const struct {
        const char *name; const char *time; int unread; const char *lines[3];
    } M[4] = {
        {"주인",   "03:11", 1, {"오늘도 늦었네. 사장님이 기다리신다.",
                                "퇴근? 그건 내일의 네가 알겠지.",
                                "사직서는 아직 안 받았지?"}},
        {"김대리", "02:54", 0, {"형, 서류 내가 대신 올려놨어.",
                                "근데 주임님이 이상하게 보더라.",
                                "오늘은 그냥 눈치 보자."}},
        {"인사팀", "01:40", 1, {"[자동] 사직서 양식 첨부.",
                                "미제출 시 갱신됩니다.",
                                "로그에 남깁니다."}},
        {"시스템", "--:--", 0, {"감사 로그 기록 중...",
                                "이 대화는 모니터링됨.",
                                "연결 유지됨."}},
    };
    int NM = 4;
    if (selected < 0) selected = 0;
    if (selected >= NM) selected = NM - 1;

    /* sender list */
    for (int i = 0; i < NM; i++) {
        int ry = 16 + i * 40;
        int sel = (i == selected);
        if (sel) {
            ui_fill_rect(2, ry, 116, 38, gr, gg, gb, 220);
            ui_draw_rect(2, ry, 116, 38, wr, wg, wb, 255);
        } else {
            ui_fill_rect(2, ry, 116, 38, dr, dg, db, 220);
            ui_draw_rect(2, ry, 116, 38, sr, sg, sb, 200);
        }
        ui_text(8, ry + 4, M[i].name, wr, wg, wb);
        ui_text(8, ry + 18, M[i].time, sr, sg, sb);
        if (M[i].unread) ui_fill_rect(104, ry + 6, 8, 8, vr, vg, vb, 255);
    }

    /* message pane */
    int px = 126;
    ui_text(px, 18, M[selected].name, gr, gg, gb);
    ui_draw_rect(px, 30, RW - px - 6, 1, sr, sg, sb, 200);
    int yy = 36;
    for (int k = 0; k < 3; k++) {
        ui_text_wrap(px, yy, RW - px - 8, 36, M[selected].lines[k], wr, wg, wb);
        yy += 34;
    }

    /* bottom input mock with a blinking caret */
    ui_fill_rect(0, RH - 12, RW, 12, dr, dg, db, 240);
    ui_draw_rect(0, RH - 12, RW, 12, sr, sg, sb, 200);
    ui_text(6, RH - 11, "메시지 입력", sr, sg, sb);
    if (((int)(t * 2.0)) % 2 == 0) ui_fill_rect(72, RH - 10, 4, 8, wr, wg, wb, 255);
}

void uia_schedule(double t, int selected) {
    uia_scene_empty(t);
    ui_begin();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    ui_text(8, 6, "저녁 일정", gr, gg, gb);
    char clock[16];
    snprintf(clock, sizeof clock, "21:47:%02d", ((int)(t * 10.0)) % 60);
    ui_text(232, 6, clock, vr, vg, vb);

    /* work-life tension bar: red work vs teal life */
    int bx = 8, by = 22, bw = 200, bh = 8;
    int wseg = (int)(bw * 0.65);
    ui_fill_rect(bx, by, wseg, bh, vr, vg, vb, 255);
    ui_fill_rect(bx + wseg, by, bw - wseg, bh, tr, tg, tb, 255);
    ui_draw_rect(bx, by, bw, bh, wr, wg, wb, 255);
    ui_text(214, 20, "일 65 / 삶 35", sr, sg, sb);

    /* three concrete evening activities with cost/consequence preview */
    static const struct { const char *name; const char *prev; } A[3] = {
        {"1. 잔업: 보고서 마감",     "HP-4  눈치+2  성과+3"},
        {"2. 퇴근: 자전거 라이딩",   "WLB+4  성과-1"},
        {"3. 회식: 팀 복닥",         "HP-3  눈치+1  스트레스+2"},
    };
    int NA = 3;
    if (selected < 0) selected = 0;
    if (selected >= NA) selected = NA - 1;
    for (int i = 0; i < NA; i++) {
        int ry = 70 + i * 44;
        int sel = (i == selected);
        if (sel) {
            ui_fill_rect(8, ry, 304, 38, gr, gg, gb, 225);
            ui_draw_rect(8, ry, 304, 38, wr, wg, wb, 255);
            ui_text(14, ry + 5, A[i].name, dr, dg, db);
            ui_text(14, ry + 22, A[i].prev, dr, dg, db);
        } else {
            ui_fill_rect(8, ry, 304, 38, dr, dg, db, 220);
            ui_draw_rect(8, ry, 304, 38, sr, sg, sb, 200);
            ui_text(14, ry + 5, A[i].name, wr, wg, wb);
            ui_text(14, ry + 22, A[i].prev, sr, sg, sb);
        }
    }

    ui_text(8, 214, "> 선택하면 시간이 흐른다", tr, tg, tb);
}

void uia_reward(double t, const uint32_t card_ids[3], int selected) {
    (void)t;
    uia_scene_empty(t);
    ui_begin();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    ui_text(8, 6, "보상: 카드 획득", gr, gg, gb);
    ui_text(8, 20, "덱에 추가할 카드를 고르세요 (1/2/3)", wr, wg, wb);

    int cw = 58, gap = 10, total = 3 * cw + 2 * gap;
    int x0 = (RW - total) / 2;
    for (int i = 0; i < 3; i++) {
        int x = x0 + i * (cw + gap);
        uint32_t id = (card_ids && card_ids[i]) ? card_ids[i] : 0;
        int sel = (i == selected);
        if (id == 0) {
            ui_fill_rect(x, 60, cw, 90, dr, dg, db, 200);
            ui_draw_rect(x, 60, cw, 90, sr, sg, sb, 200);
            ui_text(x + 12, 100, "(빈)", sr, sg, sb);
        } else {
            uia_card(x, 60, cw, 90, id, sel ? UIA_CARD_HOVER : UIA_CARD_NORMAL);
        }
        if (sel) ui_draw_rect(x - 2, 58, cw + 4, 94, gr, gg, gb, 255);
    }

    ui_text(8, 200, "> 선택 후 확인을 누르세요", tr, tg, tb);
}

/* =====================================================================
 * pure layout / intent queries (unit-testable)
 * ===================================================================== */
int uia_intent_revealed(void) {
    if (g_combat.enemy_intent_type == 0) return 0;
    if (g_combat.enemy.statuses[ST_REVEAL - 1] > 0) return 1;
    if (g_player.nunchi >= 6) return 1;
    return 0;
}

UiaHandLayout uia_hand_layout(int hand_n) {
    UiaHandLayout L = { 0, 0, 60, 54 };
    if (hand_n <= 0) { L.stride = 0; L.card_w = 0; return L; }
    if (hand_n > MAX_HAND) hand_n = MAX_HAND;
    L.count = hand_n;

    const int margin = 4, min_gap = 2, min_card = 20;
    int avail = RW - 2 * margin;         /* usable row width */
    L.card_w = 54;
    int stride = L.card_w + 6;           /* preferred gap */
    /* total row width, from the actual geometry: last card starts at
     * (hand_n-1)*stride and is card_w wide. */
    while ((hand_n - 1) * stride + L.card_w > avail) {
        if (stride > L.card_w + min_gap)      stride--;   /* tighten gaps first */
        else if (L.card_w > min_card)         L.card_w--; /* then narrow cards */
        else                                  stride--;   /* finally overlap */
    }
    L.stride = stride;
    int total = (hand_n - 1) * stride + L.card_w;
    L.x0 = margin + (avail - total) / 2;
    if (L.x0 < margin) L.x0 = margin;
    return L;
}

void uia_combat_focus(double t, int selected_card) {
    if (g_combat.enemy.maxhp >= 100) uia_scene_boss(t);
    else                             uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb, jr, jg, jb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);
    hcol(HUE_JADE, RNDR_STEP_LIT, &jr, &jg, &jb);

    /* ---- enemy name + HP numeric + bar ---- */
    const char *ename = g_combat.enemy.maxhp > 0 ? "주인" : "--";
    ui_text(16, 2, ename, wr, wg, wb);
    char buf[40];
    snprintf(buf, sizeof buf, "%d/%d", g_combat.enemy.hp, g_combat.enemy.maxhp);
    int enw = ui_text_width(ename);
    ui_text(16 + enw + 4, 2, buf, wr, wg, wb);
    double epct = g_combat.enemy.maxhp > 0 ? (double)g_combat.enemy.hp / g_combat.enemy.maxhp : 0.0;
    ui_bar(16, 12, 288, 8, epct, vr, vg, vb, 255);

    /* ---- intent telegraph (new fields) + reveal / nunchi ----
     * Type and value are only drawn when uia_intent_revealed() says the
     * player can read them (enemy ST_REVEAL status or nunchi >= 6). Otherwise
     * the line stays a bare "???". */
    int show_intent = uia_intent_revealed();
    const char *kind = "???";
    if (show_intent) {
        switch (g_combat.enemy_intent_type) {
            case COMBAT_INTENT_ATTACK:   kind = "공격"; break;
            case COMBAT_INTENT_BLOCK:    kind = "방어"; break;
            case COMBAT_INTENT_PRESSURE: kind = "압박"; break;
            case COMBAT_INTENT_GLITCH:   kind = "오류"; break;
            default:                     kind = "???"; break;
        }
    }
    if (show_intent)
        snprintf(buf, sizeof buf, "의도: %s %d", kind, g_combat.enemy_intent_value);
    else
        snprintf(buf, sizeof buf, "의도: ???");
    if (g_combat.enemy.statuses[ST_REVEAL - 1] > 0 && g_combat.enemy_intent_type != 0) {
        size_t rem = sizeof(buf) - strlen(buf) - 1;
        if (rem > 0) strncat(buf, " (확인)", rem);
    }
    ui_text(16, 24, buf, gr, gg, gb);
    if (g_combat.enemy.block > 0) {
        snprintf(buf, sizeof buf, "방어 %d", g_combat.enemy.block);
        ui_text(200, 24, buf, tr, tg, tb);
    }

    /* ---- player resources ---- */
    double ppct = g_combat.player.maxhp > 0 ? (double)g_combat.player.hp / g_combat.player.maxhp : 0.0;
    ui_bar(16, 38, 120, 8, ppct, jr, jg, jb, 255);
    snprintf(buf, sizeof buf, "%d/%d", g_combat.player.hp, g_combat.player.maxhp);
    ui_text(140, 38, buf, wr, wg, wb);
    snprintf(buf, sizeof buf, "에너지 %d", g_combat.player.energy);
    ui_text(16, 50, buf, gr, gg, gb);
    snprintf(buf, sizeof buf, "눈치 %d", g_player.nunchi);
    ui_text(110, 50, buf, wr, wg, wb);
    if (g_combat.player.block > 0) {
        snprintf(buf, sizeof buf, "방어 %d", g_combat.player.block);
        ui_text(190, 50, buf, tr, tg, tb);
    }

    /* energy pips */
    int maxe = g_combat.player.maxenergy;
    for (int k = 0; k < maxe; k++) {
        if (k < g_combat.player.energy) ui_fill_rect(16 + k * 8, 62, 6, 6, gr, gg, gb, 255);
        else                            ui_fill_rect(16 + k * 8, 62, 6, 6, dr, dg, db, 255);
    }

    /* ---- sprites + damage flashes ---- */
    UISprite *ps = ui_sprite("char_player");
    UISprite *bs = ui_sprite("char_boss");
    if (ps) ui_blit_fit(ps, 16, 96, 44, 70);
    if (bs) ui_blit_fit(bs, 260, 86, 48, 84);

    if (g_combat.last_enemy_damage > 0) {
        int fl = (int)(sin(t * 12.0) * 0.5 + 0.5);
        if (fl) {
            ui_text(248, 80, "-", vr, vg, vb);
            snprintf(buf, sizeof buf, "%d", g_combat.last_enemy_damage);
            ui_text(256, 80, buf, vr, vg, vb);
        }
        UISprite *sp = ui_sprite("fx_spark");
        if (sp) ui_blit_fit(sp, 248, 92, 30, 30);
    }
    if (g_combat.last_player_damage > 0) {
        int fl = (int)(sin(t * 12.0 + 1.0) * 0.5 + 0.5);
        if (fl) {
            ui_text(8, 90, "-", vr, vg, vb);
            snprintf(buf, sizeof buf, "%d", g_combat.last_player_damage);
            ui_text(16, 90, buf, vr, vg, vb);
        }
    }

    /* ---- hand (fits 10 cards; geometry from uia_hand_layout) ---- */
    int hand_n = g_combat.hand_n;
    if (hand_n > MAX_HAND) hand_n = MAX_HAND;
    if (hand_n > 0) {
        UiaHandLayout hl = uia_hand_layout(hand_n);
        for (int i = 0; i < hl.count; i++) {
            uint32_t cid = g_combat.hand[i];
            CardDef *dc = card_by_id(cid);
            int cost = dc ? dc->cost : 0;
            UiaCardSel sel = UIA_CARD_NORMAL;
            if (i == selected_card) sel = UIA_CARD_HOVER;
            else if (cost > g_combat.player.energy) sel = UIA_CARD_DISABLED;
            uia_card(hl.x0 + i * hl.stride, 160, hl.card_w, 74, cid, sel);
        }
    }

    /* ---- footer: turn + pile counts ---- */
    snprintf(buf, sizeof buf, "턴 %d", g_combat.turn);
    ui_text(16, 232, buf, wr, wg, wb);
    snprintf(buf, sizeof buf, "뽑음 %d 버림 %d 소모 %d",
             g_combat.draw_n, g_combat.discard_n, g_combat.exhaust_n);
    ui_text(80, 232, buf, wr, wg, wb);

    /* ---- end-state banners ---- */
    if (g_combat.state == 1) {
        int bw = ui_text_scaled(0, -1000, "승리", 6, gr, gg, gb);
        ui_text_scaled(160 - bw / 2, 110, "승리", 6, gr, gg, gb);
    } else if (g_combat.state == 2) {
        int bw = ui_text_scaled(0, -1000, "사직", 6, vr, vg, vb);
        ui_text_scaled(160 - bw / 2, 110, "사직", 6, vr, vg, vb);
    }
}

void uia_combat(double t) {
    uia_combat_focus(t, -1);
}

void uia_gameover(double t) {
    uia_scene_empty(t);
    ui_begin();

    uint8_t dr, dg, db, vr, vg, vb, wr, wg, wb, sr, sg, sb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);

    /* resignation form, offset to the left (not a centered panel) */
    ui_fill_rect(16, 36, 190, 150, dr, dg, db, 235);
    ui_draw_rect(16, 36, 190, 150, sr, sg, sb, 220);
    ui_text(24, 44, "사 직 서", vr, vg, vb);
    ui_draw_rect(24, 56, 174, 1, sr, sg, sb, 200);

    const char *fl[] = {
        "성  명 : ____________",
        "소  속 : 성광정보기술",
        "사  유 : 퇴근을 허락하지 않음",
        "비  고 : 새벽 3시 17분",
    };
    int fy = 66;
    for (int i = 0; i < 4; i++) { ui_text(24, fy, fl[i], wr, wg, wb); fy += 22; }

    /* red stamp, right side */
    ui_draw_rect(226, 70, 64, 64, vr, vg, vb, 230);
    ui_text_align(226, 92, 64, 20, "제 출", wr, wg, wb, 1);
    ui_text_align(226, 112, 64, 14, "03:17", wr, wg, wb, 1);

    /* system clock + tagline */
    char clock[16];
    snprintf(clock, sizeof clock, "03:17:%02d", ((int)(t * 10.0)) % 60);
    ui_text(232, 8, clock, vr, vg, vb);
    ui_text(40, 200, "퇴근은 꿈이었다.", wr, wg, wb);
    ui_draw_rect(0, 236, RW, 2, vr, vg, vb, 220);
}

/* =====================================================================
 * card
 * ===================================================================== */
void uia_card(int x, int y, int w, int h, uint32_t card_id, UiaCardSel sel) {
    if (sel == UIA_CARD_HOVER) y -= 4;   /* raised */

    uint8_t dr, dg, db, sr, sg, sb, wr, wg, wb, gr, gg, gb, vr, vg, vb, th, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);

    CardDef *dc = card_by_id(card_id);
    uint8_t ah = HUE_SLATE;
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
    hcol(ah, RNDR_STEP_MID, &th, &tg, &tb);

    /* base panel + type band */
    ui_fill_rect(x, y, w, h, dr, dg, db, 240);
    ui_fill_rect(x + 1, y + 1, w - 2, 12, th, tg, tb, 255);

    /* type symbol + clipped name on the band */
    const char *sym = "·";
    if (dc) {
        switch (dc->type) {
            case C_ATTACK:  sym = "공"; break;
            case C_DEFEND:  sym = "방"; break;
            case C_TECH:    sym = "기"; break;
            case C_SOCIAL:  sym = "사"; break;
            case C_SYSTEM:  sym = "시"; break;
            case C_CURSE:   sym = "저"; break;
            case C_SPECIAL: sym = "특"; break;
            default:        sym = "·";  break;
        }
    }
    ui_text(x + 3, y + 2, sym, wr, wg, wb);
    char nm[48];
    const char *nm0 = card_name(card_id); if (!nm0) nm0 = "?";
    uia_glyph_sub(nm0, 0, (w - 18) / 8, nm, sizeof nm);
    ui_text(x + 14, y + 2, nm, wr, wg, wb);

    /* cost badge (top-right) */
    int cost = dc ? dc->cost : 0;
    char cb[4];
    snprintf(cb, sizeof cb, "%d", cost);
    ui_fill_rect(x + w - 15, y + 1, 14, 14, gr, gg, gb, 255);
    ui_draw_rect(x + w - 15, y + 1, 14, 14, vr, vg, vb, 255);
    ui_text_align(x + w - 15, y + 1, 14, 14, cb, wr, wg, wb, 1);

    /* body copy, clipped within the card */
    const char *body = card_text(card_id);
    uia_card_body(x + 3, y + 16, w - 6, h - 18, body ? body : "-", wr, wg, wb);

    /* selection treatment */
    if (sel == UIA_CARD_HOVER) {
        ui_draw_rect(x, y, w, h, gr, gg, gb, 255);
        ui_draw_rect(x + 1, y + 1, w - 2, h - 2, wr, wg, wb, 255);
    } else if (sel == UIA_CARD_DISABLED) {
        ui_fill_rect(x, y, w, h, dr, dg, db, 150);
        ui_text(x + w - 12, y + 2, "X", vr, vg, vb);
        ui_draw_rect(x, y, w, h, sr, sg, sb, 200);
    } else {
        ui_draw_rect(x, y, w, h, sr, sg, sb, 255);
    }
}

/* =====================================================================
 * present
 * ===================================================================== */
void uia_present(const char *ppm_path) {
    ui_present(ppm_path);
}

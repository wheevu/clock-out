/* render/ui_app.HC -- screen compositor for 퇴근.
 * Layers the true-color UI (ui.H) over the 3D palette scene (render.H).
 * Every uia_* screen draws the FULL frame: it calls rndr_begin (via a
 * uia_scene_*) and ui_begin itself, then the caller only needs uia_present.
 * Deterministic: reads game state and draws; never mutates shared state.
 *
 * Visual direction: late-night Korean office horror at native 640x360,
 * with the hard-edged interface language of a 2000s console game. Near-black indigo void, dirty fluorescent gold,
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
    const int horizon = 162;
    ui_fill_rect(0, horizon, RW, RH - horizon, r, g, b, 170);
    ui_fill_rect(0, horizon, RW, 1, tr, tg, tb, 100);
    for (int y = horizon + 18; y < RH; y += 18)
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
    /* A thin broken-signal glint gives utility screens a living backdrop
     * without reading as a stray block through translucent panels. */
    int on = uia_flick(t * 2.0, 7);
    if (on) {
        uint8_t *fb = (uint8_t *)rndr_fb();
        if (fb) {
            uint8_t idx = RNDR_COL(HUE_VERMILION, RNDR_STEP_DARK);
            for (int x = RW / 2 - 28; x < RW / 2 + 28; x += 3) {
                fb[(RH / 2) * RW + x] = idx;
                fb[(RH / 2 + 2) * RW + x] = idx;
            }
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

/* Shared utility-screen chrome. The thin rail and quiet footer keep messenger,
 * schedule, and reward screens in one visual family without flattening their
 * different layouts. */
static void uia_top_bar(const char *title, const char *meta,
                        uint8_t br, uint8_t bg, uint8_t bb,
                        uint8_t tr, uint8_t tg, uint8_t tb,
                        uint8_t mr, uint8_t mg, uint8_t mb) {
    ui_fill_rect(0, 0, RW, 28, br, bg, bb, 245);
    ui_fill_rect(0, 27, RW, 1, tr, tg, tb, 220);
    ui_text(20, 10, title, tr, tg, tb);
    if (meta) ui_text_align(RW - 180, 0, 160, 28, meta, mr, mg, mb, 2);
}

static void uia_footer_hint(const char *text,
                            uint8_t br, uint8_t bg, uint8_t bb,
                            uint8_t tr, uint8_t tg, uint8_t tb) {
    ui_fill_rect(0, RH - 24, RW, 24, br, bg, bb, 245);
    ui_fill_rect(0, RH - 24, RW, 1, tr, tg, tb, 150);
    ui_text(20, RH - 16, text, tr, tg, tb);
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

    /* Widescreen title composition: old console framing, modern breathing room. */
    ui_draw_rect(3, 3, RW - 6, RH - 6, vr, vg, vb, 200);
    uia_corners(gr, gg, gb, 230, 10);
    ui_fill_rect(28, 24, 2, 100, vr, vg, vb, 220);

    int ts = 10;
    int tw = ui_text_scaled(0, -1000, GAME_TITLE, ts, vr, vg, vb);
    ui_text_scaled(48, 48, GAME_TITLE, ts, vr, vg, vb);
    ui_fill_rect(48, 48 + ts * 8 + 8, tw + 48, 2, gr, gg, gb, 220);
    ui_text(50, 145, "CLOCK OUT / PROTOCOL 03", gr, gg, gb);

    /* System detail reads like a boot screen, not an ornamental badge. */
    ui_text_scaled(456, 30, "03:17", 2, gr, gg, gb);
    ui_text(456, 54, "SEONGWANG OS", sr, sg, sb);
    ui_text(456, 68, "NIGHT SHIFT", sr, sg, sb);
    ui_fill_rect(456, 84, 136, 1, sr, sg, sb, 160);
    ui_text(456, 94, "FLOOR 17 / LOCKED", tr, tg, tb);

    ui_text(48, 286, COMPANY_NAME, tr, tg, tb);
    ui_text(48, 308, "새벽 3시 17분, 아무도 퇴근하지 않았다.", wr, wg, wb);

    int pulse = ((int)(t * 2.0)) % 2 == 0;
    if (pulse) ui_text(456, 314, "> ENTER  기록 열기", gr, gg, gb);
    else       ui_text(456, 314, "  ENTER  기록 열기", gr, gg, gb);
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

    ui_text(24, 18, "03:17 / 17층 / 대화", gr, gg, gb);
    ui_fill_rect(24, 32, 176, 1, gr, gg, gb, 180);
    uia_portrait(speaker, 32, 58, 96, 170);

    /* Lower-third dialogue panel leaves the world readable above it. */
    ui_fill_rect(32, 250, 576, 86, dr, dg, db, 238);
    ui_draw_rect(32, 250, 576, 86, gr, gg, gb, 220);
    ui_fill_rect(32, 250, 4, 86, gr, gg, gb, 255);
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 24;
    ui_fill_rect(48, 238, nw, 24, dr, dg, db, 245);
    ui_draw_rect(48, 238, nw, 24, gr, gg, gb, 220);
    ui_text(60, 246, label, gr, gg, gb);
    if (text) ui_text_wrap(52, 275, 520, 42, text, wr, wg, wb);

    int hx = 504 + (int)(sin(t * 6.0) * 2.0);
    ui_text(hx, 318, "ENTER  계속 >", wr, wg, wb);
}

void uia_choice(double t, const char *speaker, const char *text,
                PendingChoice *c, int idx) {
    int boss = (speaker && (strcmp(speaker, "주인") == 0 || strcmp(speaker, "사장") == 0));
    if (boss) uia_scene_boss(t);
    else      uia_scene_office(t);
    ui_begin();
    uia_world_grade();

    uint8_t dr, dg, db, gr, gg, gb, vr, vg, vb, wr, wg, wb, sr, sg, sb, tr, tg, tb;
    hcol(HUE_CHARCOAL, RNDR_STEP_DARK, &dr, &dg, &db);
    hcol(HUE_GOLD, RNDR_STEP_LIT, &gr, &gg, &gb);
    hcol(HUE_VERMILION, RNDR_STEP_LIT, &vr, &vg, &vb);
    hcol(HUE_WHITE, RNDR_STEP_LIT, &wr, &wg, &wb);
    hcol(HUE_SLATE, RNDR_STEP_MID, &sr, &sg, &sb);
    hcol(HUE_TEAL, RNDR_STEP_MID, &tr, &tg, &tb);

    ui_text(24, 18, "03:17 / 응답 선택", gr, gg, gb);
    ui_fill_rect(24, 32, 176, 1, gr, gg, gb, 180);
    uia_portrait(speaker, 32, 54, 96, 164);

    /* Dialogue stays anchored while the option window can scroll. */
    ui_fill_rect(32, 264, 576, 72, dr, dg, db, 238);
    ui_draw_rect(32, 264, 576, 72, gr, gg, gb, 220);
    ui_fill_rect(32, 264, 4, 72, gr, gg, gb, 255);
    const char *label = speaker ? speaker : COMPANY_NAME;
    int nw = ui_text_width(label) + 24;
    ui_fill_rect(48, 252, nw, 24, dr, dg, db, 245);
    ui_draw_rect(48, 252, nw, 24, gr, gg, gb, 220);
    ui_text(60, 260, label, gr, gg, gb);
    if (text) ui_text_wrap(52, 287, 520, 30, text, wr, wg, wb);

    if (c && c->n > 0) {
        int total_choices = c->n > CHOICE_CAP ? CHOICE_CAP : c->n;
        const int visible = total_choices < 5 ? total_choices : 5;
        int first = 0;
        if (idx >= visible) first = idx - visible + 1;
        if (first > total_choices - visible) first = total_choices - visible;
        int x0 = 152, w0 = 456;
        for (int row = 0; row < visible; row++) {
            int i = first + row;
            int ry = 54 + row * 38;
            int sel = (i == idx);
            if (sel) {
                ui_fill_rect(x0, ry, w0, 32, gr, gg, gb, 238);
                ui_draw_rect(x0, ry, w0, 32, wr, wg, wb, 255);
                ui_fill_rect(x0, ry, 4, 32, vr, vg, vb, 255);
                ui_text(x0 + 18, ry + 12, c->opt[i].label, dr, dg, db);
            } else {
                ui_fill_rect(x0, ry, w0, 32, dr, dg, db, 225);
                ui_draw_rect(x0, ry, w0, 32, sr, sg, sb, 190);
                ui_text(x0 + 18, ry + 12, c->opt[i].label, wr, wg, wb);
            }
            if (c->opt[i].has_guard) {
                const char *tag = "[눈치]";
                int tw = ui_text_width(tag);
                ui_text(x0 + w0 - tw - 14, ry + 12, tag, sel ? dr : tr, sel ? dg : tg, sel ? db : tb);
            }
        }
        char pos[24];
        snprintf(pos, sizeof pos, "%d / %d",
                 idx >= 0 && idx < total_choices ? idx + 1 : 0, total_choices);
        ui_text_align(480, 232, 128, 16, pos, sr, sg, sb, 2);
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

    /* Player stands in the aisle, with status kept inside two stable HUD zones. */
    UISprite *ps = ui_sprite("char_player");
    if (ps) ui_blit_fit(ps, 274, 172, 92, 150);

    const char *loc = location ? location : "사무실 통로";
    ui_fill_rect(20, 18, 378, 56, dr, dg, db, 232);
    ui_draw_rect(20, 18, 378, 56, gr, gg, gb, 210);
    ui_fill_rect(20, 18, 4, 56, gr, gg, gb, 255);
    ui_text(36, 30, "현재 위치", gr, gg, gb);
    ui_text_scaled(132, 24, loc, 2, wr, wg, wb);

    const char *obj = objective ? objective : "비상구를 찾아라";
    ui_text(36, 54, "목표", tr, tg, tb);
    ui_text(84, 54, obj, wr, wg, wb);

    int hx = 418, hw = 202;
    ui_fill_rect(hx, 18, hw, 56, dr, dg, db, 232);
    ui_draw_rect(hx, 18, hw, 56, sr, sg, sb, 210);
    ui_text(hx + 14, 30, "HP", wr, wg, wb);
    double hpv = g_player.hp > 0 ? (double)g_player.hp / 60.0 : 0.0;
    if (hpv > 1) hpv = 1;
    ui_bar(hx + 46, 30, 94, 8, hpv, vr, vg, vb, 255);
    char hbuf[16];
    snprintf(hbuf, sizeof hbuf, "%d", g_player.hp);
    ui_text(hx + 154, 30, hbuf, wr, wg, wb);
    ui_text(hx + 14, 52, "눈치", tr, tg, tb);
    snprintf(hbuf, sizeof hbuf, "%d", g_player.nunchi);
    ui_text(hx + 62, 52, hbuf, wr, wg, wb);
    ui_text(hx + 110, 52, "WLB", sr, sg, sb);
    snprintf(hbuf, sizeof hbuf, "%d", g_player.wlb);
    ui_text(hx + 150, 52, hbuf, wr, wg, wb);

    int px = 240 + (int)(sin(t * 5.0) * 2.0);
    ui_fill_rect(220, 314, 200, 28, dr, dg, db, 235);
    ui_draw_rect(220, 314, 200, 28, gr, gg, gb, 220);
    ui_text(px, 324, "> E  조사하기", gr, gg, gb);
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

    uia_top_bar("사내 메신저 / 야간망", "03:17  연결됨",
                dr, dg, db, gr, gg, gb, sr, sg, sb);

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

    /* Sender rail. Selection uses a stripe and label contrast, not color alone. */
    ui_fill_rect(20, 44, 176, 280, dr, dg, db, 226);
    ui_draw_rect(20, 44, 176, 280, sr, sg, sb, 190);
    ui_text(34, 56, "대화 목록", sr, sg, sb);
    ui_fill_rect(32, 72, 152, 1, sr, sg, sb, 130);
    for (int i = 0; i < NM; i++) {
        int ry = 84 + i * 52;
        int sel = (i == selected);
        if (sel) {
            ui_fill_rect(28, ry, 160, 44, gr, gg, gb, 228);
            ui_draw_rect(28, ry, 160, 44, wr, wg, wb, 255);
            ui_fill_rect(28, ry, 4, 44, vr, vg, vb, 255);
        } else {
            ui_fill_rect(28, ry, 160, 44, dr, dg, db, 220);
            ui_draw_rect(28, ry, 160, 44, sr, sg, sb, 170);
        }
        ui_text(42, ry + 9, M[i].name, wr, wg, wb);
        ui_text(42, ry + 25, M[i].time, sel ? dr : sr, sel ? dg : sg, sel ? db : sb);
        if (M[i].unread) {
            ui_fill_rect(168, ry + 10, 8, 8, vr, vg, vb, 255);
            ui_text(146, ry + 25, "NEW", sel ? dr : vr, sel ? dg : vg, sel ? db : vb);
        }
    }

    /* Message pane. Each line gets its own timestamped log row. */
    int px = 216;
    ui_fill_rect(px, 44, 404, 280, dr, dg, db, 220);
    ui_draw_rect(px, 44, 404, 280, sr, sg, sb, 190);
    ui_text(px + 18, 58, M[selected].name, gr, gg, gb);
    ui_text_align(px + 250, 50, 136, 24, M[selected].time, sr, sg, sb, 2);
    ui_fill_rect(px + 16, 78, 372, 1, sr, sg, sb, 140);
    int yy = 94;
    for (int k = 0; k < 3; k++) {
        ui_text(px + 18, yy, k == 0 ? ">" : "-", k == 0 ? gr : sr, k == 0 ? gg : sg, k == 0 ? gb : sb);
        ui_text_wrap(px + 38, yy, 334, 42, M[selected].lines[k], wr, wg, wb);
        ui_fill_rect(px + 18, yy + 38, 352, 1, sr, sg, sb, 80);
        yy += 54;
    }

    ui_fill_rect(px + 16, 282, 372, 28, dr, dg, db, 245);
    ui_draw_rect(px + 16, 282, 372, 28, sr, sg, sb, 180);
    ui_text(px + 28, 292, "메시지 입력", sr, sg, sb);
    if (((int)(t * 2.0)) % 2 == 0) ui_fill_rect(px + 120, 291, 4, 10, wr, wg, wb, 255);

    uia_footer_hint("W/S  대화 선택    ENTER  열기    ESC  닫기", dr, dg, db, gr, gg, gb);
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

    char clock[16];
    snprintf(clock, sizeof clock, "21:47:%02d", ((int)(t * 10.0)) % 60);
    uia_top_bar("퇴근 계획 / 8월 25일", clock,
                dr, dg, db, gr, gg, gb, vr, vg, vb);

    /* Work-life state gets a stable summary column. */
    ui_fill_rect(20, 48, 180, 274, dr, dg, db, 225);
    ui_draw_rect(20, 48, 180, 274, sr, sg, sb, 190);
    ui_text(36, 66, "오늘의 균형", gr, gg, gb);
    ui_text_scaled(36, 92, "65", 3, vr, vg, vb);
    ui_text(92, 112, "WORK", vr, vg, vb);
    ui_text_scaled(36, 148, "35", 3, tr, tg, tb);
    ui_text(92, 168, "LIFE", tr, tg, tb);

    int bx = 36, by = 202, bw = 148, bh = 12;
    int wseg = (int)(bw * 0.65);
    ui_fill_rect(bx, by, wseg, bh, vr, vg, vb, 255);
    ui_fill_rect(bx + wseg, by, bw - wseg, bh, tr, tg, tb, 255);
    ui_draw_rect(bx, by, bw, bh, wr, wg, wb, 255);
    ui_text(36, 232, "종료 예정", sr, sg, sb);
    ui_text(36, 250, "03:17  미정", wr, wg, wb);
    ui_fill_rect(36, 274, 148, 1, sr, sg, sb, 110);
    ui_text(36, 292, "선택하면 시간이 흐른다", sr, sg, sb);

    /* three concrete evening activities with cost/consequence preview */
    static const struct { const char *name; const char *prev; } A[3] = {
        {"1. 잔업: 보고서 마감",     "HP-4  눈치+2  성과+3"},
        {"2. 퇴근: 자전거 라이딩",   "WLB+4  성과-1"},
        {"3. 회식: 팀 복닥",         "HP-3  눈치+1  스트레스+2"},
    };
    int NA = 3;
    if (selected < 0) selected = 0;
    if (selected >= NA) selected = NA - 1;
    ui_text(224, 50, "다음 행동", sr, sg, sb);
    for (int i = 0; i < NA; i++) {
        int ry = 72 + i * 76;
        int sel = (i == selected);
        if (sel) {
            ui_fill_rect(224, ry, 396, 62, gr, gg, gb, 228);
            ui_draw_rect(224, ry, 396, 62, wr, wg, wb, 255);
            ui_fill_rect(224, ry, 4, 62, vr, vg, vb, 255);
            ui_text(246, ry + 15, A[i].name, dr, dg, db);
            ui_text(246, ry + 37, A[i].prev, dr, dg, db);
        } else {
            ui_fill_rect(224, ry, 396, 62, dr, dg, db, 220);
            ui_draw_rect(224, ry, 396, 62, sr, sg, sb, 180);
            ui_text(246, ry + 15, A[i].name, wr, wg, wb);
            ui_text(246, ry + 37, A[i].prev, sr, sg, sb);
        }
    }

    uia_footer_hint("W/S  일정 선택    ENTER  확정    ESC  돌아가기", dr, dg, db, gr, gg, gb);
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

    char meta[24];
    snprintf(meta, sizeof meta, "%d / 3", selected >= 0 && selected < 3 ? selected + 1 : 0);
    uia_top_bar("전투 보상 / 카드 획득", meta,
                dr, dg, db, gr, gg, gb, sr, sg, sb);
    ui_text(72, 48, "덱에 추가할 카드를 고르세요", wr, wg, wb);

    int cw = 150, gap = 24, total = 3 * cw + 2 * gap;
    int x0 = (RW - total) / 2;
    for (int i = 0; i < 3; i++) {
        int x = x0 + i * (cw + gap);
        uint32_t id = (card_ids && card_ids[i]) ? card_ids[i] : 0;
        int sel = (i == selected);
        if (id == 0) {
            ui_fill_rect(x, 82, cw, 220, dr, dg, db, 200);
            ui_draw_rect(x, 82, cw, 220, sr, sg, sb, 200);
            ui_text_align(x, 82, cw, 220, "(빈 슬롯)", sr, sg, sb, 1);
        } else {
            uia_card(x, 82, cw, 220, id, sel ? UIA_CARD_HOVER : UIA_CARD_NORMAL);
        }
        char num[8];
        snprintf(num, sizeof num, "%d", i + 1);
        ui_fill_rect(x + 8, 288, 24, 20, sel ? gr : dr, sel ? gg : dg, sel ? gb : db, 255);
        ui_draw_rect(x + 8, 288, 24, 20, sel ? wr : sr, sel ? wg : sg, sel ? wb : sb, 220);
        ui_text_align(x + 8, 288, 24, 20, num, sel ? dr : wr, sel ? dg : wg, sel ? db : wb, 1);
        if (sel) ui_draw_rect(x - 4, 74, cw + 8, 232, gr, gg, gb, 255);
    }

    uia_footer_hint("A/D  카드 선택    ENTER  덱에 추가    ESC  건너뛰기", dr, dg, db, tr, tg, tb);
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
    UiaHandLayout L = { 0, 0, 120, 108 };
    if (hand_n <= 0) { L.stride = 0; L.card_w = 0; return L; }
    if (hand_n > MAX_HAND) hand_n = MAX_HAND;
    L.count = hand_n;

    const int margin = 20, min_gap = 4, min_card = 72;
    int avail = RW - 2 * margin;         /* usable row width */
    L.card_w = 108;
    int stride = L.card_w + 12;          /* preferred gap */
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

    /* Enemy command rail. Name, health, and intent scan in one pass. */
    const char *ename = g_combat.enemy.maxhp > 0 ? "주인" : "--";
    ui_fill_rect(20, 14, 600, 54, dr, dg, db, 235);
    ui_draw_rect(20, 14, 600, 54, sr, sg, sb, 210);
    ui_fill_rect(20, 14, 4, 54, vr, vg, vb, 255);
    ui_text_scaled(38, 26, ename, 2, wr, wg, wb);
    char buf[40];
    snprintf(buf, sizeof buf, "%d/%d", g_combat.enemy.hp, g_combat.enemy.maxhp);
    double epct = g_combat.enemy.maxhp > 0 ? (double)g_combat.enemy.hp / g_combat.enemy.maxhp : 0.0;
    ui_bar(150, 28, 352, 10, epct, vr, vg, vb, 255);
    ui_text_align(520, 20, 82, 24, buf, wr, wg, wb, 2);

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
    ui_text(150, 48, buf, gr, gg, gb);
    if (g_combat.enemy.block > 0) {
        snprintf(buf, sizeof buf, "방어 %d", g_combat.enemy.block);
        ui_text_align(486, 42, 116, 22, buf, tr, tg, tb, 2);
    }

    /* Compact player status block leaves the room visible. */
    ui_fill_rect(20, 80, 250, 60, dr, dg, db, 230);
    ui_draw_rect(20, 80, 250, 60, sr, sg, sb, 190);
    ui_fill_rect(20, 80, 4, 60, gr, gg, gb, 255);
    ui_text(36, 94, "HP", wr, wg, wb);
    double ppct = g_combat.player.maxhp > 0 ? (double)g_combat.player.hp / g_combat.player.maxhp : 0.0;
    ui_bar(68, 94, 112, 8, ppct, jr, jg, jb, 255);
    snprintf(buf, sizeof buf, "%d/%d", g_combat.player.hp, g_combat.player.maxhp);
    ui_text(192, 94, buf, wr, wg, wb);
    ui_text(36, 118, "ENERGY", gr, gg, gb);
    snprintf(buf, sizeof buf, "눈치 %d", g_player.nunchi);
    ui_text(156, 118, buf, wr, wg, wb);
    if (g_combat.player.block > 0) {
        snprintf(buf, sizeof buf, "방어 %d", g_combat.player.block);
        ui_text(156, 130, buf, tr, tg, tb);
    }

    int maxe = g_combat.player.maxenergy;
    for (int k = 0; k < maxe; k++) {
        if (k < g_combat.player.energy) ui_fill_rect(92 + k * 14, 118, 10, 10, gr, gg, gb, 255);
        else                            ui_draw_rect(92 + k * 14, 118, 10, 10, sr, sg, sb, 220);
    }

    /* Combatants sit outside the HUD and above the card tray. */
    UISprite *ps = ui_sprite("char_player");
    UISprite *bs = ui_sprite("char_boss");
    if (ps) ui_blit_fit(ps, 48, 142, 88, 100);
    if (bs) ui_blit_fit(bs, 500, 126, 100, 118);

    if (g_combat.last_enemy_damage > 0) {
        int fl = (int)(sin(t * 12.0) * 0.5 + 0.5);
        if (fl) {
            ui_text_scaled(492, 118, "-", 2, vr, vg, vb);
            snprintf(buf, sizeof buf, "%d", g_combat.last_enemy_damage);
            ui_text_scaled(508, 118, buf, 2, vr, vg, vb);
        }
        UISprite *sp = ui_sprite("fx_spark");
        if (sp) ui_blit_fit(sp, 474, 142, 48, 48);
    }
    if (g_combat.last_player_damage > 0) {
        int fl = (int)(sin(t * 12.0 + 1.0) * 0.5 + 0.5);
        if (fl) {
            ui_text_scaled(44, 136, "-", 2, vr, vg, vb);
            snprintf(buf, sizeof buf, "%d", g_combat.last_player_damage);
            ui_text_scaled(60, 136, buf, 2, vr, vg, vb);
        }
    }

    /* Card tray remains legible at five cards and safely overlaps up to ten. */
    ui_fill_rect(0, 228, RW, 116, dr, dg, db, 180);
    ui_fill_rect(0, 228, RW, 1, gr, gg, gb, 170);
    int hand_n = g_combat.hand_n;
    if (hand_n > MAX_HAND) hand_n = MAX_HAND;
    if (hand_n > 0) {
        UiaHandLayout hl = uia_hand_layout(hand_n);
        for (int pass = 0; pass < 2; pass++) {
            for (int i = 0; i < hl.count; i++) {
                int focused = (i == selected_card);
                if ((pass == 0 && focused) || (pass == 1 && !focused)) continue;
                uint32_t cid = g_combat.hand[i];
                CardDef *dc = card_by_id(cid);
                int cost = dc ? dc->cost : 0;
                UiaCardSel sel = focused ? UIA_CARD_HOVER : UIA_CARD_NORMAL;
                if (!focused && cost > g_combat.player.energy) sel = UIA_CARD_DISABLED;
                uia_card(hl.x0 + i * hl.stride, 240, hl.card_w, 96, cid, sel);
            }
        }
    }

    ui_fill_rect(0, 344, RW, 16, dr, dg, db, 250);
    snprintf(buf, sizeof buf, "턴 %d", g_combat.turn);
    ui_text(20, 348, buf, wr, wg, wb);
    snprintf(buf, sizeof buf, "뽑음 %d 버림 %d 소모 %d",
             g_combat.draw_n, g_combat.discard_n, g_combat.exhaust_n);
    ui_text(96, 348, buf, sr, sg, sb);
    ui_text_align(430, 344, 190, 16, "A/D 선택  ENTER 사용", gr, gg, gb, 2);

    /* ---- end-state banners ---- */
    if (g_combat.state == 1) {
        int bw = ui_text_scaled(0, -1000, "승리", 7, gr, gg, gb);
        ui_text_scaled(RW / 2 - bw / 2, 144, "승리", 7, gr, gg, gb);
    } else if (g_combat.state == 2) {
        int bw = ui_text_scaled(0, -1000, "사직", 7, vr, vg, vb);
        ui_text_scaled(RW / 2 - bw / 2, 144, "사직", 7, vr, vg, vb);
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

    ui_text(24, 18, "SEONGWANG OS / SESSION TERMINATED", sr, sg, sb);
    ui_fill_rect(24, 32, 592, 1, vr, vg, vb, 180);

    /* Resignation form is still bureaucratic, now composed like a final screen. */
    ui_fill_rect(64, 56, 380, 246, dr, dg, db, 238);
    ui_draw_rect(64, 56, 380, 246, sr, sg, sb, 220);
    ui_fill_rect(64, 56, 4, 246, vr, vg, vb, 255);
    ui_text_scaled(88, 76, "사 직 서", 2, vr, vg, vb);
    ui_draw_rect(88, 104, 332, 1, sr, sg, sb, 180);

    const char *fl[] = {
        "성  명 : ____________",
        "소  속 : 성광정보기술",
        "사  유 : 퇴근을 허락하지 않음",
        "비  고 : 새벽 3시 17분",
    };
    int fy = 130;
    for (int i = 0; i < 4; i++) {
        ui_text(88, fy, fl[i], wr, wg, wb);
        ui_fill_rect(88, fy + 18, 332, 1, sr, sg, sb, 80);
        fy += 38;
    }

    ui_draw_rect(488, 116, 96, 96, vr, vg, vb, 230);
    ui_draw_rect(494, 122, 84, 84, vr, vg, vb, 150);
    ui_text_scaled(504, 140, "제출", 2, wr, wg, wb);
    ui_text_align(494, 176, 84, 20, "03:17", wr, wg, wb, 1);

    /* system clock + tagline */
    char clock[16];
    snprintf(clock, sizeof clock, "03:17:%02d", ((int)(t * 10.0)) % 60);
    ui_text_align(480, 12, 136, 20, clock, vr, vg, vb, 2);
    ui_text(488, 242, "퇴근은 꿈이었다.", wr, wg, wb);
    ui_text(488, 264, "ENTER  처음부터", sr, sg, sb);
    ui_draw_rect(0, 344, RW, 2, vr, vg, vb, 220);
}

/* =====================================================================
 * card
 * ===================================================================== */
void uia_card(int x, int y, int w, int h, uint32_t card_id, UiaCardSel sel) {
    if (sel == UIA_CARD_HOVER) y -= 8;   /* raised */

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

    /* Base panel + stronger type band. Cards stay square and information-first. */
    ui_fill_rect(x, y, w, h, dr, dg, db, 240);
    ui_fill_rect(x + 1, y + 1, w - 2, 22, th, tg, tb, 255);

    /* type symbol + clipped name on the band */
    const char *sym = "-";
    if (dc) {
        switch (dc->type) {
            case C_ATTACK:  sym = "공"; break;
            case C_DEFEND:  sym = "방"; break;
            case C_TECH:    sym = "기"; break;
            case C_SOCIAL:  sym = "사"; break;
            case C_SYSTEM:  sym = "시"; break;
            case C_CURSE:   sym = "저"; break;
            case C_SPECIAL: sym = "특"; break;
            default:        sym = "-";  break;
        }
    }
    ui_text(x + 7, y + 8, sym, wr, wg, wb);
    char nm[48];
    const char *nm0 = card_name(card_id); if (!nm0) nm0 = "?";
    int name_glyphs = (w - 62) / 8;
    if (name_glyphs < 1) name_glyphs = 1;
    uia_glyph_sub(nm0, 0, name_glyphs, nm, sizeof nm);
    ui_text(x + 25, y + 8, nm, wr, wg, wb);

    /* cost badge (top-right) */
    int cost = dc ? dc->cost : 0;
    char cb[4];
    snprintf(cb, sizeof cb, "%d", cost);
    ui_fill_rect(x + w - 27, y + 1, 26, 26, gr, gg, gb, 255);
    ui_draw_rect(x + w - 27, y + 1, 26, 26, vr, vg, vb, 255);
    ui_text_align(x + w - 27, y + 1, 26, 26, cb, dr, dg, db, 1);

    /* body copy, clipped within the card */
    const char *body = card_text(card_id);
    uia_card_body(x + 8, y + 34, w - 16, h - 42, body ? body : "-", wr, wg, wb);

    /* selection treatment */
    if (sel == UIA_CARD_HOVER) {
        ui_draw_rect(x, y, w, h, gr, gg, gb, 255);
        ui_draw_rect(x + 1, y + 1, w - 2, h - 2, wr, wg, wb, 255);
    } else if (sel == UIA_CARD_DISABLED) {
        ui_fill_rect(x, y, w, h, dr, dg, db, 150);
        ui_text(x + w - 18, y + 9, "X", vr, vg, vb);
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

/* render/ui.HC -- 2D true-color compositor for the 퇴근 engine.
 * Implements every function declared in render/ui.H. Portable C99.
 * The overlay is a full RGBA buffer composited over the palette scene. */
#include "ui.H"              /* bring in UI_W/UI_H, UISprite, all prototypes */
#include "../include/contracts.HC"
#include <stdlib.h>
#include <string.h>

/* ---- private state ---- */
#define MAX 64               /* max baked sprites */
#define CELL 8               /* on-screen glyph cell size (8x8) */
#define HICES 16             /* hi-res compose cell; Hangul bands are HICES/3 = 5px,
                                readable. Downsampled to CELL for 1x text. */

static int g_inited = 0;
static uint8_t g_ov[RW*RH*4];          /* overlay, RGBA, row-major */
static UISprite g_sprites[MAX];
static char g_skeys[MAX][64];          /* manifest key per sprite (private) */
static int g_sprite_n = 0;
static int g_manifest_loaded = 0;

/* Forward declarations: these live in core/strings.HC and korean/hangul.HC. */
GStr gstr_from_utf8(const char *s);
void gstr_free(GStr g);
void hangul_compose(uint16_t token, uint8_t *cell, int cw, int ch);

/* Generated 16x16 Hangul glyph atlas (tools/gen_glyphs.py). */
#include "../korean/syllable_data.h"

/* Decode a Hangul token into its codepoint (reverse of the tokenizer). */
static uint32_t tok_cp(uint16_t tok){
    uint16_t cho  = (uint16_t)((tok >> 10) & 0x1F);
    uint16_t jung = (uint16_t)((tok >> 5)  & 0x1F);
    uint16_t jong = (uint16_t)( tok        & 0x1F);
    return 0xAC00u + (uint32_t)cho * 588u + (uint32_t)jung * 28u + (uint32_t)jong;
}

/* bsearch SYL_CP for a codepoint; returns index or -1. */
static int syl_idx(uint32_t cp){
    int lo = 0, hi = SYL_N - 1;
    while (lo <= hi){
        int mid = (lo + hi) >> 1;
        uint32_t v = SYL_CP[mid];
        if (v == cp) return mid;
        if (v < cp) lo = mid + 1;
        else hi = mid - 1;
    }
    return -1;
}

/* ---- public-domain 8x8 Latin bitmap font (Daniel Hepper / M. Fraenkel) ---- */
static const uint8_t font8x8[128][8] = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0000
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0001
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0002
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0003
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0004
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0005
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0006
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0007
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0008
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0009
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000A
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000B
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000C
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000D
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000E
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000F
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0010
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0011
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0012
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0013
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0014
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0015
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0016
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0017
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0018
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0019
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001A
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001B
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001C
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001D
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001E
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001F
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0020 (space)
    { 0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00},   // U+0021 (!)
    { 0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0022 (")
    { 0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00},   // U+0023 (#)
    { 0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x0C, 0x00},   // U+0024 ($)
    { 0x00, 0x63, 0x33, 0x18, 0x0C, 0x66, 0x63, 0x00},   // U+0025 (%)
    { 0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00},   // U+0026 (&)
    { 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0027 (')
    { 0x18, 0x0C, 0x06, 0x06, 0x06, 0x0C, 0x18, 0x00},   // U+0028 (()
    { 0x06, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x06, 0x00},   // U+0029 ())
    { 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00},   // U+002A (*)
    { 0x00, 0x0C, 0x0C, 0x3F, 0x0C, 0x0C, 0x00, 0x00},   // U+002B (+)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x06},   // U+002C (,)
    { 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00},   // U+002D (-)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00},   // U+002E (.)
    { 0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00},   // U+002F (/)
    { 0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00},   // U+0030 (0)
    { 0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00},   // U+0031 (1)
    { 0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00},   // U+0032 (2)
    { 0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00},   // U+0033 (3)
    { 0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00},   // U+0034 (4)
    { 0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00},   // U+0035 (5)
    { 0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00},   // U+0036 (6)
    { 0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00},   // U+0037 (7)
    { 0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00},   // U+0038 (8)
    { 0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00},   // U+0039 (9)
    { 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x00},   // U+003A (:)
    { 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x06},   // U+003B (;)
    { 0x18, 0x0C, 0x06, 0x03, 0x06, 0x0C, 0x18, 0x00},   // U+003C (<)
    { 0x00, 0x00, 0x3F, 0x00, 0x00, 0x3F, 0x00, 0x00},   // U+003D (=)
    { 0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00},   // U+003E (>)
    { 0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00},   // U+003F (?)
    { 0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00},   // U+0040 (@)
    { 0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00},   // U+0041 (A)
    { 0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00},   // U+0042 (B)
    { 0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00},   // U+0043 (C)
    { 0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00},   // U+0044 (D)
    { 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00},   // U+0045 (E)
    { 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00},   // U+0046 (F)
    { 0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00},   // U+0047 (G)
    { 0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00},   // U+0048 (H)
    { 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0049 (I)
    { 0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00},   // U+004A (J)
    { 0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00},   // U+004B (K)
    { 0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00},   // U+004C (L)
    { 0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00},   // U+004D (M)
    { 0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00},   // U+004E (N)
    { 0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00},   // U+004F (O)
    { 0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00},   // U+0050 (P)
    { 0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00},   // U+0051 (Q)
    { 0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00},   // U+0052 (R)
    { 0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00},   // U+0053 (S)
    { 0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0054 (T)
    { 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00},   // U+0055 (U)
    { 0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00},   // U+0056 (V)
    { 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00},   // U+0057 (W)
    { 0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00},   // U+0058 (X)
    { 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00},   // U+0059 (Y)
    { 0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00},   // U+005A (Z)
    { 0x1E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1E, 0x00},   // U+005B ([)
    { 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00},   // U+005C (\)
    { 0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0x00},   // U+005D (])
    { 0x08, 0x1C, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00},   // U+005E (^)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF},   // U+005F (_)
    { 0x0C, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0060 (`)
    { 0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00},   // U+0061 (a)
    { 0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00},   // U+0062 (b)
    { 0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00},   // U+0063 (c)
    { 0x38, 0x30, 0x30, 0x3e, 0x33, 0x33, 0x6E, 0x00},   // U+0064 (d)
    { 0x00, 0x00, 0x1E, 0x33, 0x3f, 0x03, 0x1E, 0x00},   // U+0065 (e)
    { 0x1C, 0x36, 0x06, 0x0f, 0x06, 0x06, 0x0F, 0x00},   // U+0066 (f)
    { 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F},   // U+0067 (g)
    { 0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00},   // U+0068 (h)
    { 0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0069 (i)
    { 0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E},   // U+006A (j)
    { 0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00},   // U+006B (k)
    { 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+006C (l)
    { 0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00},   // U+006D (m)
    { 0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00},   // U+006E (n)
    { 0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00},   // U+006F (o)
    { 0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F},   // U+0070 (p)
    { 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78},   // U+0071 (q)
    { 0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00},   // U+0072 (r)
    { 0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00},   // U+0073 (s)
    { 0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00},   // U+0074 (t)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00},   // U+0075 (u)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00},   // U+0076 (v)
    { 0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00},   // U+0077 (w)
    { 0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00},   // U+0078 (x)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F},   // U+0079 (y)
    { 0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00},   // U+007A (z)
    { 0x38, 0x0C, 0x0C, 0x07, 0x0C, 0x0C, 0x38, 0x00},   // U+007B ({)
    { 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00},   // U+007C (|)
    { 0x07, 0x0C, 0x0C, 0x38, 0x0C, 0x0C, 0x07, 0x00},   // U+007D (})
    { 0x6E, 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+007E (~)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}    // U+007F
};

/* ---- blend helper: composite a src RGBA pixel onto the overlay ---- */
static void blend(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (a == 0) return;
    if (x < 0 || x >= RW || y < 0 || y >= RH) return;
    int idx = (y*RW + x)*4;
    uint8_t dr = g_ov[idx], dg = g_ov[idx+1], db = g_ov[idx+2], da = g_ov[idx+3];
    /* same alpha math as ui_present: src over existing overlay. */
    g_ov[idx]   = (uint8_t)((r*a + dr*(255 - a)) / 255);
    g_ov[idx+1] = (uint8_t)((g*a + dg*(255 - a)) / 255);
    g_ov[idx+2] = (uint8_t)((b*a + db*(255 - a)) / 255);
    g_ov[idx+3] = (uint8_t)((a*255 + da*(255 - a)) / 255);
}

/* ---- sprite manifest loader (tolerates absence) ---- */
static void load_manifest(void)
{
    if (g_manifest_loaded) return;
    g_manifest_loaded = 1;
    g_sprite_n = 0;

    FILE *f = fopen("assets/baked/manifest.txt", "r");
    if (!f) return;                     /* absent: leave sprite list empty */

    char line[1024];
    while (fgets(line, sizeof(line), f) && g_sprite_n < MAX) {
        char key[64], fname[256];
        int w = 0, h = 0;
        if (sscanf(line, "%63s %d %d %255s", key, &w, &h, fname) != 4)
            continue;
        if (w <= 0 || h <= 0) continue;

        UISprite *s = &g_sprites[g_sprite_n];
        s->w = w; s->h = h;
        /* overflow-safe check: w,h>0 and w*h*4 fits in size_t */
        if ((size_t)w * (size_t)h > ((size_t)-1) / 4) { continue; }
        size_t need = (size_t)w * (size_t)h * 4;
        s->rgba = (uint8_t *)malloc(need);
        if (!s->rgba) continue;

        char path[512];
        snprintf(path, sizeof(path), "assets/baked/%s", fname);
        FILE *bf = fopen(path, "rb");
        if (!bf) { free(s->rgba); s->rgba = NULL; continue; }
        /* reject truncated/oversized blobs: must match exactly */
        if (fread(s->rgba, 1, need, bf) != need) {
            free(s->rgba); s->rgba = NULL; fclose(bf); continue;
        }
        if (fgetc(bf) != EOF) {           /* blob larger than declared */
            free(s->rgba); s->rgba = NULL; fclose(bf); continue;
        }
        fclose(bf);
        strncpy(g_skeys[g_sprite_n], key, 63);
        g_skeys[g_sprite_n][63] = 0;
        g_sprite_n++;
    }
    fclose(f);
}

/* ===================== LIFECYCLE ===================== */
void ui_init(void)
{
    g_inited = 1;
    memset(g_ov, 0, sizeof(g_ov));
    load_manifest();
}

void ui_begin(void)
{
    memset(g_ov, 0, sizeof(g_ov));
}

void ui_present(const char *ppm_path)
{
    const uint8_t *fb = rndr_fb();
    const uint8_t *pal = rndr_palette();
    if (!ppm_path) return;             /* skip write, still fine */

    FILE *f = fopen(ppm_path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", RW, RH);

    for (int y = 0; y < RH; y++) {
        for (int x = 0; x < RW; x++) {
            int oi = (y*RW + x)*4;
            uint8_t a = g_ov[oi+3];
            uint8_t or_ = g_ov[oi], og = g_ov[oi+1], ob = g_ov[oi+2];

            int pi = fb[y*RW + x] * 3;   /* palette index -> 256*3 bytes */
            uint8_t sr = pal[pi], sg = pal[pi+1], sb = pal[pi+2];

            uint8_t out_r, out_g, out_b;
            if (a == 0) {
                out_r = sr; out_g = sg; out_b = sb;
            } else if (a == 255) {
                /* opaque overlay: premultiplied == straight when a==255 */
                out_r = or_; out_g = og; out_b = ob;
            } else {
                /* overlay stores premultiplied RGB (see blend). Composite over
                 * the opaque scene once: out = premul + scene*(1-a). Do NOT
                 * multiply or_ by a again (that would double-apply alpha). */
                out_r = (uint8_t)(or_ + (uint32_t)sr * (255 - a) / 255);
                out_g = (uint8_t)(og + (uint32_t)sg * (255 - a) / 255);
                out_b = (uint8_t)(ob + (uint32_t)sb * (255 - a) / 255);
            }
            fputc(out_r, f); fputc(out_g, f); fputc(out_b, f);
        }
    }
    fclose(f);
}

/* ===================== PALETTE ACCESS ===================== */
const uint8_t *ui_scene_fb(void)      { return rndr_fb(); }
const uint8_t *ui_scene_palette(void) { return rndr_palette(); }
uint8_t ui_scene_color_at(int x, int y)
{
    if (x < 0 || x >= RW || y < 0 || y >= RH) return 0;
    return rndr_fb()[y*RW + x];
}

/* ===================== SPRITE ACCESS ===================== */
UISprite *ui_sprite(const char *key)
{
    load_manifest();                   /* lazy load */
    for (int i = 0; i < g_sprite_n; i++)
        if (strcmp(g_skeys[i], key) == 0)
            return &g_sprites[i];
    return NULL;
}
int ui_sprite_loaded(void) { return g_manifest_loaded; }
int ui_sprite_count(void)  { return g_sprite_n; }

/* ===================== PRIMITIVES ===================== */
void ui_pixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    blend(x, y, r, g, b, a);
}

void ui_fill_rect(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    int x0 = x < 0 ? 0 : x;
    int y0 = y < 0 ? 0 : y;
    int x1 = x + w > RW ? RW : x + w;
    int y1 = y + h > RH ? RH : y + h;
    for (int j = y0; j < y1; j++)
        for (int i = x0; i < x1; i++)
            blend(i, j, r, g, b, a);
}

void ui_draw_rect(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (w <= 0 || h <= 0) return;
    ui_fill_rect(x, y, w, 1, r, g, b, a);
    ui_fill_rect(x, y + h - 1, w, 1, r, g, b, a);
    ui_fill_rect(x, y, 1, h, r, g, b, a);
    ui_fill_rect(x + w - 1, y, 1, h, r, g, b, a);
}

void ui_panel(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (w <= 0 || h <= 0) return;
    uint8_t lr = (uint8_t)(r + 40 > 255 ? 255 : r + 40);
    uint8_t lg = (uint8_t)(g + 40 > 255 ? 255 : g + 40);
    uint8_t lb = (uint8_t)(b + 40 > 255 ? 255 : b + 40);
    ui_fill_rect(x, y, w, h, r, g, b, a);
    ui_draw_rect(x, y, w, h, lr, lg, lb, a);
}

void ui_blit(UISprite *s, int x, int y, int scale)
{
    if (!s || !s->rgba) return;
    if (scale < 1) scale = 1;
    for (int sy = 0; sy < s->h; sy++) {
        for (int sx = 0; sx < s->w; sx++) {
            int si = (sy*s->w + sx)*4;
            uint8_t a = s->rgba[si+3];
            if (a == 0) continue;
            int bx = x + sx*scale;
            int by = y + sy*scale;
            for (int dy = 0; dy < scale; dy++)
                for (int dx = 0; dx < scale; dx++)
                    blend(bx + dx, by + dy,
                          s->rgba[si], s->rgba[si+1], s->rgba[si+2], a);
        }
    }
}

void ui_blit_fit(UISprite *s, int x, int y, int w, int h)
{
    if (!s || !s->rgba || w <= 0 || h <= 0) return;
    int scale = (s->w > 0 && s->h > 0)
        ? (int)((w / s->w < h / s->h) ? (w / s->w) : (h / s->h))
        : 1;
    if (scale < 1) scale = 1;
    int dw = s->w * scale;
    int dh = s->h * scale;
    int ox = x + (w - dw) / 2;
    int oy = y + (h - dh) / 2;
    ui_blit(s, ox, oy, scale);
}

/* ===================== TEXT ===================== */
static void draw_glyph_cell(int x, int y, const uint8_t *cell, int size,
                            uint8_t r, uint8_t g, uint8_t b)
{
    /* cell is HICES x HICES. Render into an on-screen box of CELL*size px.
     * When downsizing (box < HICES, e.g. 16->8) use 2x2 coverage averaging so
     * strokes are NOT dropped to a sparse lattice; a dst pixel fills when >=
     * half its source subpixels are on. When >= HICES use nearest sampling. */
    int box = CELL * size;                 /* destination pixel box side */
    if (box < 1) box = 1;
    if (box < HICES) {
        int ri = HICES / box;              /* source subpixels per axis */
        if (ri < 1) ri = 1;
        for (int j = 0; j < box; j++) {
            int sy = j * HICES / box;
            for (int i = 0; i < box; i++) {
                int sx = i * HICES / box;
                int on = 0;
                for (int dy = 0; dy < ri; dy++)
                    for (int dx = 0; dx < ri; dx++) {
                        int yy = sy + dy, xx = sx + dx;
                        if (yy < HICES && xx < HICES && cell[yy * HICES + xx]) on++;
                    }
                /* Preserve any covered stroke when reducing the 16px Korean
                 * atlas to the 8px UI cell. A half-coverage threshold erased
                 * one-pixel stems and made ordinary dialogue look broken. */
                if (on > 0) blend(x + i, y + j, r, g, b, 255);
            }
        }
        return;
    }
    for (int j = 0; j < box; j++) {
        int sj = j * HICES / box;
        if (sj >= HICES) sj = HICES - 1;
        for (int i = 0; i < box; i++) {
            int si = i * HICES / box;
            if (si >= HICES) si = HICES - 1;
            if (cell[sj * HICES + si]) {
                blend(x + i, y + j, r, g, b, 255);
            }
        }
    }
}

static void draw_latin(int x, int y, uint8_t ch, int size,
                       uint8_t r, uint8_t g, uint8_t b)
{
    uint8_t glyph[CELL];
    const uint8_t *src = font8x8[ch & 0x7F];
    for (int i = 0; i < CELL; i++) glyph[i] = src[i];
    /* expand to HICES x HICES cell, matching font8x8's LSB-left layout */
    uint8_t cell[HICES*HICES];
    memset(cell, 0, sizeof cell);
    /* Expand each 8x8 source pixel to a 2x2 block in the 16x16 intermediate,
     * so the Latin glyphs fill the HICES cell the same way Hangul atlas data
     * does. At 1x the 16px cell downsamples back to a true 8x8 bitmap, and
     * larger sizes scale from full coverage instead of a sparse half-cell. */
    for (int j = 0; j < CELL; j++)
        for (int i = 0; i < CELL; i++)
            if ((glyph[j] >> i) & 1) {
                int cj = j * 2, ci = i * 2;
                cell[ cj      * HICES + ci     ] = 1;
                cell[ cj      * HICES + ci + 1 ] = 1;
                cell[(cj + 1) * HICES + ci     ] = 1;
                cell[(cj + 1) * HICES + ci + 1 ] = 1;
            }
    draw_glyph_cell(x, y, cell, size, r, g, b);
}

/* Draw a Hangul token (or Latin) at 1x glyph size. */
static void draw_hangul(int x, int y, uint16_t tok, int size,
                        uint8_t r, uint8_t g, uint8_t b)
{
    uint8_t cell[HICES*HICES];
    int idx = syl_idx(tok_cp(tok));
    if (idx >= 0){
        /* atlas is 16x16 = HICES x HICES */
        const uint8_t *src = SYL_PIX[idx];
        for (int i = 0; i < HICES*HICES; i++) cell[i] = src[i];
    } else {
        hangul_compose(tok, cell, HICES, HICES);
    }
    draw_glyph_cell(x, y, cell, size, r, g, b);
}

int ui_text(int x, int y, const char *utf8, uint8_t r, uint8_t g, uint8_t b)
{
    int x0 = x;
    if (!utf8) return 0;
    GStr gs = gstr_from_utf8(utf8);
    for (uint32_t t = 0; t < gs.len; t++) {
        uint16_t tok = gs.tok[t];
        if (tok & 0x8000) {
            draw_hangul(x, y, tok, 1, r, g, b);
        } else {
            draw_latin(x, y, (uint8_t)tok, 1, r, g, b);
        }
        x += CELL;
    }
    gstr_free(gs);
    return x - x0;
}

int ui_text_scaled(int x, int y, const char *utf8, int size,
                   uint8_t r, uint8_t g, uint8_t b)
{
    int x0 = x;
    if (!utf8) return 0;
    if (size < 1) size = 1;
    GStr gs = gstr_from_utf8(utf8);
    for (uint32_t t = 0; t < gs.len; t++) {
        uint16_t tok = gs.tok[t];
        if (tok & 0x8000) {
            draw_hangul(x, y, tok, size, r, g, b);
        } else {
            draw_latin(x, y, (uint8_t)tok, size, r, g, b);
        }
        x += CELL * size;
    }
    gstr_free(gs);
    return x - x0;
}

int ui_text_width(const char *utf8)
{
    if (!utf8) return 0;
    GStr gs = gstr_from_utf8(utf8);
    int w = (int)gs.len * CELL;
    gstr_free(gs);
    return w;
}

void ui_text_align(int x, int y, int w, int h, const char *utf8,
                   uint8_t r, uint8_t g, uint8_t b, int align)
{
    int tw = ui_text_width(utf8);
    int yp = y + (h - CELL) / 2;
    if (yp < y) yp = y;
    int xp;
    if (align == 1)      xp = x + (w - tw) / 2;
    else if (align == 2) xp = x + w - tw;
    else                 xp = x;
    if (xp < x) xp = x;
    ui_text(xp, yp, utf8, r, g, b);
}

int ui_text_wrap(int x, int y, int w, int h, const char *utf8,
                 uint8_t r, uint8_t g, uint8_t b)
{
    if (!utf8) return 0;
    int bottom = y + h;      /* box bottom (exclusive); text may not pass it */
    if (bottom > RH) bottom = RH;
    int dy = y;
    int lines = 0;
    char buf[1024]; buf[0] = 0;
    int linew = 0;
    const char *p = utf8;
    while (*p) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        const char *ws = p;
        while (*p && *p != ' ' && *p != '\t') p++;
        char word[256]; int k = 0;
        while (ws < p && k < 255) word[k++] = *ws++;
        word[k] = 0;
        int ww = ui_text_width(word);
        int spc = (linew > 0) ? ui_text_width(" ") : 0;
        if (linew > 0 && linew + spc + ww > w) {
            if (dy + 10 > bottom) break;      /* no room for another line */
            ui_text(x, dy, buf, r, g, b);
            lines++; dy += 10;
            buf[0] = 0; linew = 0;
        }
        if (linew > 0) { strncat(buf, " ", sizeof(buf) - strlen(buf) - 1); linew += spc; }
        strncat(buf, word, sizeof(buf) - strlen(buf) - 1);
        linew += ww;
    }
    if (buf[0] && dy + CELL <= bottom) {
        ui_text(x, dy, buf, r, g, b);
        lines++;
    }
    return lines;
}

/* ===================== BARS ===================== */
static void lighten(uint8_t r, uint8_t g, uint8_t b, uint8_t *or_, uint8_t *og, uint8_t *ob)
{
    *or_ = (uint8_t)(r + 40 > 255 ? 255 : r + 40);
    *og  = (uint8_t)(g + 40 > 255 ? 255 : g + 40);
    *ob  = (uint8_t)(b + 40 > 255 ? 255 : b + 40);
}

void ui_bar(int x, int y, int w, int h, double pct,
            uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (w <= 0 || h <= 0) return;
    if (pct < 0) pct = 0; if (pct > 1) pct = 1;
    uint8_t dr = (uint8_t)(r / 2), dg = (uint8_t)(g / 2), db = (uint8_t)(b / 2);
    ui_fill_rect(x, y, w, h, dr, dg, db, a);                 /* dark bg */
    int fw = (int)(w * pct);
    if (fw > 0) ui_fill_rect(x, y, fw, h, r, g, b, a);       /* filled */
    uint8_t lr, lg, lb; lighten(r, g, b, &lr, &lg, &lb);
    ui_draw_rect(x, y, w, h, lr, lg, lb, a);                 /* border */
}

void ui_bar_v(int x, int y, int w, int h, double pct,
              uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (w <= 0 || h <= 0) return;
    if (pct < 0) pct = 0; if (pct > 1) pct = 1;
    uint8_t dr = (uint8_t)(r / 2), dg = (uint8_t)(g / 2), db = (uint8_t)(b / 2);
    ui_fill_rect(x, y, w, h, dr, dg, db, a);                 /* dark bg */
    int fh = (int)(h * pct);
    if (fh > 0) {
        int oy = y + (h - fh);                              /* fill from bottom */
        ui_fill_rect(x, oy, w, fh, r, g, b, a);
    }
    uint8_t lr, lg, lb; lighten(r, g, b, &lr, &lg, &lb);
    ui_draw_rect(x, y, w, h, lr, lg, lb, a);
}

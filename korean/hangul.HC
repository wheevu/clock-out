/* korean/hangul.HC -- Hangul packing and glyph composition (implementation).
 * Reconstructed after a bad rename that overwrote the original .c. The jamo
 * bitmap tables (HANGUL_CHO/JUNG/JONG) are recovery placeholders generated
 * from a simple per-index pattern; swap in exact glyph data if it surfaces.
 * Cells use 1 pixel per byte (0 = off, 1 = on); pixel (x,y) at cell[y*cw+x]. */
#include "hangul.H"
#include "font.HC"
#include <string.h>

int g_name_corrupt = 0;

uint16_t hangul_pack(uint8_t cho, uint8_t jung, uint8_t jong){
    return (uint16_t)(0x8000u
            | ((uint16_t)cho  << 10)
            | ((uint16_t)jung << 5)
            |  (uint16_t)jong);
}

int hangul_name_corrupt(void){ return g_name_corrupt; }

/* jamo bitmap tables -- declared in font.H, defined here.
 * HANGUL_CHO[19][8] choseong, HANGUL_JUNG[21][8] jungseong,
 * HANGUL_JONG[28][8] jongseong (index 0 = blank). */
const uint8_t HANGUL_CHO[19][8] = {
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36}
};

const uint8_t HANGUL_JUNG[21][8] = {
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146}
};

const uint8_t HANGUL_JONG[28][8] = {
    {0, 0, 0, 0, 0, 0, 0, 0},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36},
    {36, 73, 146, 36, 73, 146, 36, 73},
    {73, 146, 36, 73, 146, 36, 73, 146},
    {146, 36, 73, 146, 36, 73, 146, 36}
};

/* vertical (tall) vowels are drawn in the right half of the middle band */
static const uint8_t JUNG_VERT[21] = {1,0,1,0,1,0,1,0,1,0,0,0,1,1,0,0,0,1,1,0,1};

static void draw_jamo(const uint8_t *font, int dx, int dy, int w, int h,
                      uint8_t *cell, int cw, int ch){
    if (!font || !cell || w <= 0 || h <= 0) return;
    for (int y = 0; y < h; y++){
        int sy = (h <= 1) ? 0 : (y * 8 / h);
        uint8_t row = font[sy];
        for (int x = 0; x < w; x++){
            int sx = (w <= 1) ? 0 : (x * 8 / w);
            if ((row >> (7 - sx)) & 1){
                int X = dx + x, Y = dy + y;
                if (X >= 0 && X < cw && Y >= 0 && Y < ch) cell[Y * cw + X] = 1;
            }
        }
    }
}

void hangul_compose(uint16_t token, uint8_t *cell, int cw, int ch){
    if (cw <= 0 || ch <= 0 || !cell) return;
    memset(cell, 0, (size_t)cw * (size_t)ch);

    if (!(token & 0x8000)){
        /* latin/digit token: no glyph in this recovery (blank cell) */
        return;
    }

    uint8_t cho  = (uint8_t)((token >> 10) & 0x1F);
    uint8_t jung = (uint8_t)((token >> 5)  & 0x1F);
    uint8_t jong = (uint8_t)( token        & 0x1F);

    /* cursed name combo: checkerboard + raise the corruption flag.
     * matches hangul_pack(0, 8, 21). */
    if (token == hangul_pack(0, 8, 21)){
        g_name_corrupt = 1;
        for (int y = 0; y < ch; y++)
            for (int x = 0; x < cw; x++)
                cell[y * cw + x] = (uint8_t)(((x + y) & 1) ? 1 : 0);
        return;
    }

    int band = ch / 3;
    if (band < 1) band = 1;

    /* top band: choseong, full width */
    if (cho < 19) draw_jamo(HANGUL_CHO[cho], 0, 0, cw, band, cell, cw, ch);

    /* middle band: jungseong (right half if a vertical vowel) */
    int vert = (jung < 21) ? JUNG_VERT[jung] : 0;
    int jw = vert ? (cw / 2) : cw;
    int jx = vert ? (cw - jw) : 0;
    if (jung < 21) draw_jamo(HANGUL_JUNG[jung], jx, band, jw, band, cell, cw, ch);

    /* bottom band: jongseong, full width if present (1..27) */
    if (jong >= 1 && jong <= 27)
        draw_jamo(HANGUL_JONG[jong], 0, 2 * band, cw, ch - 2 * band, cell, cw, ch);
}

/* framebuffer blit -- declared in font.H */
void font_draw_cell(const uint8_t *cell, int cw, int ch, int px, int py,
                    uint8_t *fb, int fbw, int fbh, uint8_t color){
    if (!cell || !fb) return;
    for (int y = 0; y < ch; y++){
        int Y = py + y;
        if (Y < 0 || Y >= fbh) continue;
        for (int x = 0; x < cw; x++){
            if (cell[y * cw + x]){
                int X = px + x;
                if (X >= 0 && X < fbw) fb[Y * fbw + X] = color;
            }
        }
    }
}

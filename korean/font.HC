/* korean/font.h -- jamo/Latin bitmap font tables and framebuffer blit. */
#ifndef FONT_H
#define FONT_H
#include "../include/contracts.HC"

/* 8x8 bitmap font tables (defined in hangul.c). Each row is a byte whose MSB
 * is the leftmost pixel. Indexed by the same jamo ordering as gstr_from_utf8. */
extern const uint8_t HANGUL_CHO[19][8];
extern const uint8_t HANGUL_JUNG[21][8];
extern const uint8_t HANGUL_JONG[28][8]; /* index 0 = blank (no jongseong) */

/* Blit a composed cell (1px/byte, see hangul_compose) into a palette
 * framebuffer. fb is fbw*fbh bytes (1 byte per pixel). color is an 8-bit
 * palette index. Out-of-bounds pixels are clipped. */
void font_draw_cell(const uint8_t *cell, int cw, int ch, int px, int py,
                    uint8_t *fb, int fbw, int fbh, uint8_t color);

#endif

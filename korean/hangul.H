/* korean/hangul.h -- Hangul packing and glyph composition.
 * Cells produced by hangul_compose use 1 pixel per byte (0 = off, 1 = on);
 * pixel (x,y) lives at cell[y*cw + x]. The buffer must hold cw*ch bytes. */
#ifndef HANGUL_H
#define HANGUL_H
#include "../include/contracts.HC"

/* Pack a jamo triple into a glyph token. cho 0..18, jung 0..20, jong 0..27 (0 = none).
 * Matches the convention used by gstr_from_utf8. */
uint16_t hangul_pack(uint8_t cho, uint8_t jung, uint8_t jong);

/* Compose a glyph token into a caller-allocated cell buffer (cw*ch bytes).
 * Latin token: the 8x8 Latin glyph is scaled to cw x ch.
 * Korean token: a 3-band vertical stack --
 *   top band    -> choseong (full width)
 *   middle band -> jungseong (right half if a vertical vowel, else full width)
 *   bottom band -> jongseong (full width, if present) */
void hangul_compose(uint16_t token, uint8_t *cell, int cw, int ch);

/* Plot-flaw flag: set when hangul_compose draws the cursed name combo. */
int hangul_name_corrupt(void);

/* The same flag, exposed as a read/write global so callers can reset it. */
extern int g_name_corrupt;

#endif

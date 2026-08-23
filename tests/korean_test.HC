/* tests/korean_test.c -- Korean stack smoke tests.
 * Compiles the implementation .c files separately; this TU only includes
 * headers (see build command). Prints PASS/FAIL and exits non-zero on failure. */
#include "../include/contracts.HC"
#include "../korean/hangul.H"
#include "../korean/ime.H"
#include "../korean/font.HC"
#include <stdio.h>
#include <string.h>

#define W 12
#define H 12
static uint8_t cell[W*H];

static int count_set(void){
    int n = 0;
    for (int i = 0; i < W*H; i++) n += cell[i];
    return n;
}

static int failures = 0;
static void check(int cond, const char *msg){
    if (cond){ printf("PASS: %s\n", msg); }
    else { printf("FAIL: %s\n", msg); failures++; }
}

int main(void){
    /* 1. pack round-trips through the documented bit layout */
    {
        uint16_t t = hangul_pack(18, 0, 4);   /* ㅎ+ㅏ+ㄴ = 한 */
        uint8_t c = (uint8_t)((t >> 10) & 0x1F);
        uint8_t j = (uint8_t)((t >> 5)  & 0x1F);
        uint8_t g = (uint8_t)( t        & 0x1F);
        check((t & 0x8000) && c == 18 && j == 0 && g == 4, "hangul_pack(한) round-trip");
    }

    /* 2. compose the real word "한글" into glyph cells */
    {
        GStr g = gstr_from_utf8("한글");
        check(g.len == 2, "gstr_from_utf8(\"한글\") -> 2 tokens");
        int ok = 1;
        for (uint32_t i = 0; i < g.len; i++){
            memset(cell, 0, sizeof(cell));
            hangul_compose(g.tok[i], cell, W, H);
            if (count_set() == 0) ok = 0;
        }
        check(ok, "compose 한/글 -> non-empty 12x12 cells");
        gstr_free(g);
    }

    /* 3. the cursed name combo sets the corruption flag and a checkerboard */
    {
        g_name_corrupt = 0;
        uint16_t t = hangul_pack(0, 8, 21);
        memset(cell, 0, sizeof(cell));
        hangul_compose(t, cell, W, H);
        check(hangul_name_corrupt() == 1, "cursed combo sets g_name_corrupt");
        check(count_set() == (W*H)/2, "cursed combo fills checkerboard");
    }

    /* 4. two-beol IME types "한글" (v k s space r m f space) */
    {
        ime_reset();
        const char *seq = "vks rmf ";
        for (const char *p = seq; *p; p++) ime_feed((uint8_t)*p);
        GStr out = ime_commit_buffer();
        check(out.len == 2, "IME composes two syllables from 'vks rmf '");
        if (out.len == 2){
            uint16_t h = hangul_pack(18, 0, 4);  /* 한 */
            uint16_t l = hangul_pack(0, 18, 9);  /* 글 */
            check(out.tok[0] == h && out.tok[1] == l, "IME syllables equal 한,글");
        }
        gstr_free(out);
    }

    /* 5. Latin mode passes bytes through */
    {
        ime_reset();
        ime_toggle();                 /* -> Latin mode */
        const char *txt = "Hi";
        for (const char *p = txt; *p; p++) ime_feed((uint8_t)*p);
        GStr out = ime_commit_buffer();
        check(out.len == 2 && out.tok[0] == (uint16_t)'H' && out.tok[1] == (uint16_t)'i',
              "Latin mode passes 'Hi' through");
        gstr_free(out);
        ime_toggle();                 /* back to Korean for hygiene */
    }

    if (failures){
        printf("\n%d FAILURE(S)\n", failures);
        return 1;
    }
    printf("\nALL KOREAN TESTS PASSED\n");
    return 0;
}

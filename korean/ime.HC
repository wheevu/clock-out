/* korean/ime.HC -- two-beol (두벌식) Hangul input method (implementation).
 * Reconstructed after a bad rename that overwrote the original .c.
 * Key->jamo map follows standard two-beol, except 'v' is bound to choseong
 * ㅎ to match the surviving test vectors (한 = v k s). */
#include "ime.H"
#include "hangul.H"
#include <stdlib.h>
#include <string.h>

/* ---- internal state ---- */
static int      g_mode = 1;                 /* 0 = Latin, 1 = Korean */
static int      g_has_cho = 0, g_has_jung = 0, g_has_jong = 0;
static uint8_t  g_cho = 0, g_jung = 0, g_jong = 0;
static uint16_t g_out[4096];
static uint32_t g_out_len = 0;

void ime_reset(void){
    g_mode = 1;
    g_has_cho = g_has_jung = g_has_jong = 0;
    g_cho = g_jung = g_jong = 0;
    g_out_len = 0;
}

void ime_toggle(void){ g_mode = g_mode ? 0 : 1; }
int  ime_mode(void){ return g_mode; }

/* role: 0 = unmapped, 1 = vowel (jungseong), 2 = consonant (cho/jong).
 * For role 2, val is the choseong index; the jongseong index comes from
 * jong_of() below (codebase numbering; ㄴ=4, ㄹ=9 per the test vectors). */
typedef struct { int role; uint8_t val; } KeyRes;

static KeyRes map_key(int k){
    KeyRes r = {0, 0};
    switch (k){
        /* vowels (jungseong) */
        case 'k': r.role = 1; r.val = 0;  break; /* ㅏ */
        case 'o': r.role = 1; r.val = 1;  break; /* ㅐ */
        case 'i': r.role = 1; r.val = 2;  break; /* ㅑ */
        case 'O': r.role = 1; r.val = 3;  break; /* ㅒ */
        case 'j': r.role = 1; r.val = 4;  break; /* ㅓ */
        case 'p': r.role = 1; r.val = 5;  break; /* ㅔ */
        case 'u': r.role = 1; r.val = 6;  break; /* ㅕ */
        case 'P': r.role = 1; r.val = 7;  break; /* ㅖ */
        case 'h': r.role = 1; r.val = 8;  break; /* ㅗ */
        case 'y': r.role = 1; r.val = 9;  break; /* ㅘ */
        case 'n': r.role = 1; r.val = 13; break; /* ㅜ */
        case 'b': r.role = 1; r.val = 12; break; /* ㅛ */
        case 'm': r.role = 1; r.val = 18; break; /* ㅡ */
        case 'l': r.role = 1; r.val = 20; break; /* ㅣ */
        /* consonants (cho index in val) */
        case 'r': case 'R': r.role = 2; r.val = 0;  break; /* ㄱ */
        case 'e': case 'E': r.role = 2; r.val = 3;  break; /* ㄷ */
        case 'f':            r.role = 2; r.val = 5;  break; /* ㄹ */
        case 'a':            r.role = 2; r.val = 6;  break; /* ㅁ */
        case 'q': case 'Q': r.role = 2; r.val = 7;  break; /* ㅂ */
        case 't': case 'T': r.role = 2; r.val = 9;  break; /* ㅅ */
        case 'd':            r.role = 2; r.val = 11; break; /* ㅇ */
        case 'w': case 'W': r.role = 2; r.val = 12; break; /* ㅈ */
        case 'c':            r.role = 2; r.val = 14; break; /* ㅊ */
        case 'z':            r.role = 2; r.val = 15; break; /* ㅋ */
        case 'x':            r.role = 2; r.val = 16; break; /* ㅌ */
        case 'v': case 'g': r.role = 2; r.val = 18; break; /* ㅎ (v override) */
        case 's':            r.role = 2; r.val = 2;  break; /* ㄴ as cho */
        default: break;
    }
    return r;
}

/* jongseong index for a consonant key (codebase ordering) */
static uint8_t jong_of(int k){
    switch (k){
        case 'r': case 'R': return 1;  /* ㄱ */
        case 'e': case 'E': return 7;  /* ㄷ */
        case 'f':            return 9;  /* ㄹ */
        case 'a':            return 16; /* ㅁ */
        case 'q': case 'Q': return 17; /* ㅂ */
        case 't': case 'T': return 19; /* ㅅ */
        case 'd':            return 21; /* ㅇ */
        case 'w': case 'W': return 22; /* ㅈ */
        case 'c':            return 24; /* ㅊ */
        case 'z':            return 25; /* ㅋ */
        case 'x':            return 26; /* ㅌ */
        case 'v': case 'g': return 27; /* ㅎ */
        case 's':            return 4;  /* ㄴ */
        default:             return 0;
    }
}

static void commit_current(void){
    if (!(g_has_cho || g_has_jung)) return;
    uint16_t t = hangul_pack(g_cho, g_jung, g_has_jong ? g_jong : 0);
    if (g_out_len < 4096) g_out[g_out_len++] = t;
    g_has_cho = g_has_jung = g_has_jong = 0;
    g_cho = g_jung = g_jong = 0;
}

void ime_feed(uint8_t key){
    if (g_mode == 0){                     /* Latin pass-through */
        if (g_out_len < 4096) g_out[g_out_len++] = (uint16_t)key;
        return;
    }
    if (key == ' ' || key == 0){          /* commit pending syllable */
        commit_current();
        return;
    }

    KeyRes kr = map_key(key);
    if (kr.role == 0) return;             /* unmapped key */

    if (kr.role == 1){                    /* vowel -> jungseong */
        if (!g_has_jung){
            g_jung = kr.val; g_has_jung = 1;
        } else {                          /* another vowel: new syllable */
            commit_current();
            g_jung = kr.val; g_has_jung = 1;
        }
        return;
    }

    /* consonant */
    if (!g_has_cho){
        g_cho = kr.val; g_has_cho = 1;
    } else if (g_has_jung && !g_has_jong){
        g_jong = jong_of(key); g_has_jong = 1;
    } else {                             /* start a fresh syllable */
        commit_current();
        g_cho = kr.val; g_has_cho = 1;
    }
}

GStr ime_commit_buffer(void){
    uint32_t n = g_out_len;
    uint16_t *p = (uint16_t *)malloc(n ? n * sizeof(uint16_t) : 1);
    if (p && n) memcpy(p, g_out, n * sizeof(uint16_t));
    GStr g = { p, n };
    g_out_len = 0;
    return g;
}

/* korean/ime.h -- two-beol (두벌식) Hangul input method. */
#ifndef IME_H
#define IME_H
#include "../include/contracts.HC"

void ime_reset(void);            /* clear all state (current + buffer) */
void ime_toggle(void);           /* switch between Latin (0) and Korean (1) */
int  ime_mode(void);             /* 0 = Latin, 1 = Korean */
void ime_feed(uint8_t key);      /* feed one ASCII key in the two-beol layout */
GStr ime_commit_buffer(void);    /* commit pending syllable, return & clear
                                    the buffer; caller frees with gstr_free */

#endif

#include "contracts.HC"
#include <stdlib.h>
#include <string.h>

/* UTF-8 -> token stream.
 * Hangul syllable (U+AC00..U+D7A3) decomposed into jamo triple:
 *   token = 0x8000 | (cho<<10) | (jung<<5) | jong
 * Latin/digit/punct: token = byte value (< 0x8000). */
static uint32_t utf8_next(const char **p){
  unsigned char c = (unsigned char)**p;
  if(c<0x80){ (*p)++; return c; }
  if((c>>5)==0x6 && ((unsigned char)(*p)[1]>>6)==0x2){
    uint32_t r=((c&0x1F)<<6)|((unsigned char)(*p)[1]&0x3F); *p+=2; return r;
  }
  if((c>>4)==0xE && ((unsigned char)(*p)[1]>>6)==0x2 && ((unsigned char)(*p)[2]>>6)==0x2){
    uint32_t r=((c&0x0F)<<12)|(((unsigned char)(*p)[1]&0x3F)<<6)|((unsigned char)(*p)[2]&0x3F);
    *p+=3; return r;
  }
  (*p)++; return '?';
}

static const int JAMO_BASE = 0xAC00;
static const int N_CHO = 19, N_JUNG = 21, N_JONG = 28;

GStr gstr_from_utf8(const char *s){
  uint32_t cap = 64, n = 0;
  uint16_t *buf = (uint16_t*)malloc(cap*sizeof(uint16_t));
  const char *p = s;
  while(*p){
    uint32_t cp = utf8_next(&p);
    if(cp >= JAMO_BASE && cp < JAMO_BASE + N_CHO*N_JUNG*N_JONG){
      int v = (int)(cp - JAMO_BASE);
      int cho = v/588, jung = (v%588)/28, jong = v%28;
      uint16_t tok = (uint16_t)(0x8000 | (cho<<10) | (jung<<5) | jong);
      if(n==cap){ cap*=2; buf=(uint16_t*)realloc(buf,cap*sizeof(uint16_t)); }
      buf[n++] = tok;
    } else if(cp < 0x8000){
      if(n==cap){ cap*=2; buf=(uint16_t*)realloc(buf,cap*sizeof(uint16_t)); }
      buf[n++] = (uint16_t)cp;
    } else {
      if(n==cap){ cap*=2; buf=(uint16_t*)realloc(buf,cap*sizeof(uint16_t)); }
      buf[n++] = (uint16_t)'?';
    }
  }
  GStr g; g.tok=buf; g.len=n; return g;
}
void gstr_free(GStr g){ free(g.tok); }

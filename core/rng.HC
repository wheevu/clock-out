#include "contracts.HC"
/* xorshift64 — deterministic, fast, good enough for a game. */
void rng_init(RNG *r, uint64_t seed){ r->s = (seed==0)?0x9e3779b97f4a7c15ULL:seed; }
uint64_t rng_u32(RNG *r){
  uint64_t x = r->s;
  x ^= x << 13; x ^= x >> 7; x ^= x << 17;
  r->s = x;
  return (uint32_t)(x & 0xFFFFFFFFULL);
}
int rng_range(RNG *r, int a, int b){
  if(a>=b) return a;
  uint32_t v = rng_u32(r);
  return a + (int)(v % (uint32_t)(b-a+1));
}
double rng_f64(RNG *r){ return (double)rng_u32(r) / 4294967296.0; }

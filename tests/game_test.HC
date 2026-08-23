/* game_test.c -- self-contained smoke test for the game core.
 * Provides the integration hook ev_dispatch (applies damage to entities),
 * registers dummy cards, runs a turn, and asserts outcomes. */
#include <stdio.h>
#include <string.h>
#include "game/cards.H"
#include "game/combat.H"
#include "game/ai.H"
#include "physics/phys.H"

/* ---- integration hook: only EV_DEAL_DAMAGE applies hp/block here ---- */
void ev_dispatch(Event e){
  if(e.type == EV_DEAL_DAMAGE) apply_damage(e.dst, e.a);
  /* other event types ignored by this stub */
}

static int g_fail = 0;
#define CHECK(cond, msg) do{ if(!(cond)){ printf("FAIL: %s\n", msg); g_fail++; } \
                             else { printf("ok:   %s\n", msg); } }while(0)

static void reg(uint32_t id, uint8_t type, uint8_t cost, uint8_t nfx, EffectOpT fx[4]){
  CardDef d; memset(&d, 0, sizeof d);
  d.id = id; d.type = type; d.cost = cost; d.nfx = nfx;
  for(int i=0;i<nfx;i++) d.fx[i] = fx[i];
  card_register(d);
}

int main(void){
  RNG myrng;
  rng_init(&myrng, 0x1234ABCD);
  g_rng = &myrng;
  ev_init();

  /* register dummy cards */
  EffectOpT fx_dmg[1] = { { OP_DAMAGE, 8, 0, 0 } };
  EffectOpT fx_blk[1] = { { OP_BLOCK,  5, 0, 0 } };
  EffectOpT fx_spawn[1] = { { OP_SPAWN, 1, 0, 0 } };
  reg(1, C_ATTACK, 1, 1, fx_dmg);
  reg(2, C_DEFEND, 1, 1, fx_blk);
  reg(3, C_TECH,   1, 1, fx_spawn);

  cards_init();

  /* deterministic hand: a damage card then a spawn card */
  combat_start(100);
  int enemy_hp0 = g_combat.enemy.hp;
  CHECK(enemy_hp0 > 0, "enemy spawned with hp");

  g_combat.player.energy = 3;
  g_combat.hand[0] = 1;   /* strike */
  g_combat.hand[1] = 3;   /* spawn */
  g_combat.hand_n  = 2;

  /* play strike on enemy */
  combat_player_play(0, g_combat.enemy.id);
  CHECK(g_combat.enemy.hp == enemy_hp0 - 8, "damage card reduced enemy hp by 8");
  CHECK(g_combat.player.energy == 2, "energy deducted by card cost");
  CHECK(g_combat.hand_n == 1 && g_combat.hand[0] == 3, "strike moved to discard, spawn remains");

  /* play spawn card on enemy */
  int bodies_before_spawn = phys_count();   /* includes ground plane + enemy body */
  combat_player_play(0, g_combat.enemy.id);
  CHECK(g_combat.hand_n == 0, "spawn card left hand");
  CHECK(phys_count() == bodies_before_spawn + 1, "spawn card created one physics body");

  /* end turn: physics resolves, enemy acts, next turn begins */
  int bodies_before = phys_count();
  combat_end_turn();
  CHECK(phys_count() >= bodies_before, "physics bodies persist through burst");
  CHECK(g_combat.turn == 2, "turn advanced to 2");
  CHECK(g_combat.player.energy == 3, "energy refilled next turn");
  CHECK(g_combat.hand_n == 5, "drew 5 for next turn");

  CHECK(g_combat.state == 0, "combat still running");

  if(g_fail == 0) printf("\nPASS\n");
  else            printf("\n%d FAILURES\n", g_fail);
  return g_fail ? 1 : 0;
}

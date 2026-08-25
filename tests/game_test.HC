/* game_test.c -- self-contained smoke test for the game core.
 * Provides the integration hook ev_dispatch (applies damage to entities),
 * registers dummy cards, runs a turn, and asserts outcomes. */
#include <stdio.h>
#include <string.h>
#include "game/cards.H"
#include "game/combat.H"
#include "game/ai.H"
#include "physics/phys.H"

/* ---- integration hook: EV_DEAL_DAMAGE applies hp/block, EV_HEAL applies
 *      the clamped heal to the targeted entity. ---- */
void ev_dispatch(Event e){
  if(e.type == EV_DEAL_DAMAGE){
    apply_damage(e.dst, e.a);
  } else if(e.type == EV_HEAL){
    if(e.dst == g_combat.player.id)      apply_heal(&g_combat.player, e.a);
    else if(e.dst == g_combat.enemy.id)  apply_heal(&g_combat.enemy, e.a);
  }
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

  /* extra cards for lifecycle + effect-targeting checks */
  EffectOpT fx_exh[1] = { { OP_DAMAGE, 3, 0, 0 } };
  EffectOpT fx_ret[1] = { { OP_BLOCK,  3, 0, 0 } };
  EffectOpT fx_heal[1] = { { OP_HEAL, 25, 0, 0 } };
  EffectOpT fx_stathp[1] = { { OP_STAT, 1, -10, 0 } };   /* STAT_HP -10 */
  reg(4, C_ATTACK, 1, 1, fx_exh);
  reg(5, C_DEFEND, 1, 1, fx_ret);
  reg(6, C_DEFEND, 1, 1, fx_heal);
  reg(7, C_TECH,   1, 1, fx_stathp);
  CardDef *ce = card_by_id(4); if(ce) ce->exhaust = 1;
  CardDef *cr = card_by_id(5); if(cr) cr->retain  = 1;

  /* multi-spawn + force cards for pool-boundary checks */
  EffectOpT fx_swarm[2] = { { OP_SPAWN, 1, 20, 0 }, { OP_FORCE, 6, 2, 0 } };
  EffectOpT fx_flood[1] = { { OP_SPAWN, 1, 200, 0 } };   /* far beyond PHYS_POOL */
  reg(8, C_TECH,   0, 2, fx_swarm);
  reg(9, C_TECH,   0, 1, fx_flood);

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

  /* ===== lifecycle: exhaust -> exhaust pile, retain -> stays in hand ===== */
  combat_start(100);
  g_combat.hand_n = 2;
  g_combat.hand[0] = 4;   /* exhaust card */
  g_combat.hand[1] = 5;   /* retain card */
  {
    int ex0 = g_combat.exhaust_n, disc0 = g_combat.discard_n;
    combat_end_turn();
    CHECK(g_combat.exhaust_n == ex0 + 1, "exhaust card moved to exhaust pile");
    CHECK(g_combat.discard_n == disc0, "retain card not discarded");
    int found_retain = 0, found_exhaust_in_hand = 0;
    for(int i = 0; i < g_combat.hand_n; i++){
      if(g_combat.hand[i] == 5) found_retain = 1;
      if(g_combat.hand[i] == 4) found_exhaust_in_hand = 1;
    }
    CHECK(found_retain == 1, "retain card stayed in hand across end turn");
    CHECK(found_exhaust_in_hand == 0, "exhaust card left the hand");
  }

  /* ===== played exhaust card leaves via the exhaust pile (not discard) ===== */
  combat_start(100);
  g_combat.player.energy = 3;
  g_combat.hand_n = 1; g_combat.hand[0] = 4;
  {
    int ex0 = g_combat.exhaust_n, disc0 = g_combat.discard_n;
    combat_player_play(0, g_combat.enemy.id);
    CHECK(g_combat.exhaust_n == ex0 + 1, "played exhaust card goes to exhaust pile");
    CHECK(g_combat.discard_n == disc0, "played exhaust card not sent to discard");
  }

  /* ===== OP_HEAL heals the player even when the play target is the enemy ===== */
  combat_start(100);
  g_combat.player.hp = 30;
  g_combat.player.energy = 3;
  g_combat.hand_n = 1; g_combat.hand[0] = 6;   /* heal card */
  {
    int php0 = g_combat.player.hp;
    combat_player_play(0, g_combat.enemy.id);
    CHECK(g_combat.player.hp == php0 + 25, "OP_HEAL heals player despite enemy target");
  }

  /* ===== heal clamps to maxhp ===== */
  combat_start(100);
  g_combat.player.hp = 55;
  g_combat.player.energy = 3;
  g_combat.hand_n = 1; g_combat.hand[0] = 6;
  combat_player_play(0, g_combat.enemy.id);
  CHECK(g_combat.player.hp == g_combat.player.maxhp, "OP_HEAL clamps to maxhp");

  /* ===== OP_STAT HP clamps to >= 0 ===== */
  combat_start(100);
  g_combat.player.hp = 5;
  g_combat.player.energy = 3;
  g_combat.hand_n = 1; g_combat.hand[0] = 7;   /* STAT_HP -10 */
  combat_player_play(0, g_combat.enemy.id);
  CHECK(g_combat.player.hp == 0, "OP_STAT HP clamps to >= 0");

  /* ===== ST_WEAK reduces outgoing damage by 25% (floored) ===== */
  combat_start(100);
  g_combat.enemy.hp = 40;
  apply_status(&g_combat.player, ST_WEAK, 1, -1);
  {
    int ehp0 = g_combat.enemy.hp;
    deal_damage(&g_combat.player, &g_combat.enemy, 8);   /* 8*75/100 = 6 */
    ev_process_phase();                                  /* apply the emitted damage */
    CHECK(g_combat.last_enemy_damage == 6, "ST_WEAK reduces outgoing damage by 25% (floored)");
    CHECK(g_combat.enemy.hp == ehp0 - 6, "weak-modified damage applied to enemy");
  }

  /* ===== ST_VULN increases incoming damage by 50% (floored) ===== */
  combat_start(100);
  g_combat.enemy.hp = 40;
  apply_status(&g_combat.enemy, ST_VULN, 1, -1);
  {
    int ehp0 = g_combat.enemy.hp;
    deal_damage(&g_combat.player, &g_combat.enemy, 8);   /* 8*150/100 = 12 */
    ev_process_phase();                                  /* apply the emitted damage */
    CHECK(g_combat.last_enemy_damage == 12, "ST_VULN increases incoming damage by 50% (floored)");
    CHECK(g_combat.enemy.hp == ehp0 - 12, "vuln-modified damage applied to enemy");
  }

  /* ===== ST_ENERGYCAP lowers the turn refill by its stacks ===== */
  combat_start(100);
  g_combat.player.statuses[ST_ENERGYCAP - 1] = 2;
  combat_end_turn();
  CHECK(g_combat.player.energy == g_combat.player.maxenergy - 2,
        "ST_ENERGYCAP lowers energy refill by stacks");

  /* ===== poison + leak deal deterministic start-of-turn damage and decay ===== */
  combat_start(100);
  g_combat.enemy.statuses[ST_POISON - 1] = 5;
  g_combat.enemy.statuses[ST_LEAK - 1] = 3;
  {
    int ehp0 = g_combat.enemy.hp;
    combat_end_turn();
    CHECK(g_combat.enemy.hp == ehp0 - 8, "poison+leak deal start-of-turn damage");
    CHECK(g_combat.enemy.statuses[ST_POISON - 1] == 4, "poison decays by 1");
    CHECK(g_combat.enemy.statuses[ST_LEAK - 1] == 2, "leak decays by 1");
  }

  /* ===== enemy intent is telegraphed one turn before execution ===== */
  combat_start(100);
  CHECK(g_combat.enemy_intent_type == COMBAT_INTENT_ATTACK, "turn 1 intent is ATTACK");
  CHECK(g_combat.enemy_intent_value == 6, "turn 1 attack value 6");
  {
    int php0 = g_combat.player.hp;
    combat_end_turn();
    CHECK(g_combat.enemy_intent_type == COMBAT_INTENT_BLOCK, "turn 2 intent is BLOCK");
    CHECK(g_combat.enemy_intent_value == 8, "turn 2 block value 8");
    CHECK(g_combat.player.hp == php0 - 6, "enemy executed the telegraphed attack for 6");
  }

  /* ===== end-turn ordering: intent executes and events apply BEFORE the
   *      next start_player_turn resets player block ===== */
  combat_start(100);
  g_combat.player.block = 10;                 /* full absorption */
  {
    int php0 = g_combat.player.hp;
    combat_end_turn();
    CHECK(g_combat.player.hp == php0, "player block fully absorbs same-turn enemy attack");
    CHECK(g_combat.last_player_damage == 6, "enemy attack processed within end_turn");
  }
  combat_start(100);
  g_combat.player.block = 4;                  /* partial absorption: 6-4=2 leak */
  {
    int php0 = g_combat.player.hp;
    combat_end_turn();
    CHECK(g_combat.player.hp == php0 - 2, "partial block absorbs 4 of 6 damage");
  }

  /* ===== lethal stop: player killed by executed intent halts the turn ===== */
  combat_start(100);
  g_combat.player.hp = 5;                     /* attack for 6 is lethal */
  combat_end_turn();
  CHECK(g_combat.state == 2, "lethal enemy attack ends combat as loss");
  CHECK(g_combat.turn == 1, "turn does not advance after lethal stop");

  /* ===== lethal stop: enemy dies to its own start-of-turn DOT ===== */
  combat_start(100);
  g_combat.enemy.hp = 3;
  g_combat.enemy.statuses[ST_POISON - 1] = 5;
  {
    int php0 = g_combat.player.hp;
    combat_end_turn();
    CHECK(g_combat.state == 1, "enemy death from poison wins combat");
    CHECK(g_combat.turn == 1, "turn does not advance after enemy lethal stop");
    CHECK(g_combat.player.hp == php0, "dead enemy never executes its intent");
  }

  /* ===== finite action-status duration 2 covers exactly 2 relevant turns ===== */
  combat_start(100);                          /* turn-1 intent: ATTACK (no weak) */
  apply_status(&g_combat.player, ST_WEAK, 1, 2);
  combat_end_turn();                          /* player window closes -> tick 2->1 */
  CHECK(g_combat.player.statuses[ST_WEAK - 1] == 1 &&
        g_combat.player.stturns[ST_WEAK - 1] == 1,
        "weak persists into second turn after one end-of-action tick");
  {
    deal_damage(&g_combat.player, &g_combat.enemy, 8);
    ev_process_phase();
    CHECK(g_combat.last_enemy_damage == 6, "weak affects turn-2 outgoing damage");
  }
  combat_end_turn();                          /* tick 1->0, status cleared */
  CHECK(g_combat.player.statuses[ST_WEAK - 1] == 0, "weak expires after its 2 turns");
  g_combat.enemy.block = 0;   /* turn-2 intent gave enemy block; isolate the measurement */
  {
    int ehp0 = g_combat.enemy.hp;
    deal_damage(&g_combat.player, &g_combat.enemy, 8);
    ev_process_phase();
    CHECK(g_combat.last_enemy_damage == 8 && g_combat.enemy.hp == ehp0 - 8,
          "damage unmodified after weak expired");
  }

  /* enemy vuln applied during player turn covers exactly 2 enemy actions */
  combat_start(100);
  apply_status(&g_combat.enemy, ST_VULN, 1, 2);
  combat_end_turn();                          /* enemy acts under vuln, then ticks 2->1 */
  CHECK(g_combat.enemy.statuses[ST_VULN - 1] == 1, "vuln survives first enemy action");
  {
    deal_damage(&g_combat.player, &g_combat.enemy, 8);
    ev_process_phase();
    CHECK(g_combat.last_enemy_damage == 12, "vuln affects second turn's damage");
  }
  combat_end_turn();                          /* ticks 1->0 after second enemy action */
  CHECK(g_combat.enemy.statuses[ST_VULN - 1] == 0, "vuln expires after 2 turns");

  /* permanent (-1) action statuses are never decremented */
  combat_start(100);
  apply_status(&g_combat.player, ST_WEAK, 1, -1);
  combat_end_turn();
  combat_end_turn();
  CHECK(g_combat.player.stturns[ST_WEAK - 1] == -1 &&
        g_combat.player.statuses[ST_WEAK - 1] == 1,
        "permanent weak ignores end-of-action ticking");

  /* ===== multi-spawn beyond the old 16-body track: all bodies spawned AND forced ===== */
  combat_start(100);                          /* plane + enemy body = ids 1,2 */
  g_combat.player.energy = 3;
  g_combat.hand_n = 1; g_combat.hand[0] = 8;  /* spawn 20 spheres, force them up */
  combat_player_play(0, g_combat.enemy.id);
  CHECK(phys_count() == 22, "20 spawned bodies all exist");
  {
    int all_forced = 1;
    for(uint32_t bid = 3; bid <= 22; bid++)
      if(!(phys_ke(bid) > 0.0)) all_forced = 0;
    CHECK(all_forced, "OP_FORCE reached every spawned body including those past 16");
  }

  /* ===== spawn attempts clamp to the canonical PHYS_POOL ===== */
  combat_start(100);
  g_combat.hand_n = 1; g_combat.hand[0] = 9;  /* requests 200 spawns */
  combat_player_play(0, g_combat.enemy.id);
  CHECK(phys_count() == PHYS_POOL, "spawn attempts clamp to PHYS_POOL capacity");

  /* ===== reject illegal plays ===== */
  combat_start(100);
  g_combat.state = 1;   /* combat ended */
  {
    int before = g_combat.hand_n;
    combat_player_play(0, g_combat.enemy.id);
    CHECK(g_combat.hand_n == before, "play rejected after combat ended");
  }
  g_combat.state = 0;
  g_combat.hand_n = 0;
  combat_player_play(0, g_combat.enemy.id);
  CHECK(g_combat.hand_n == 0, "play rejected on empty/invalid hand");

  if(g_fail == 0) printf("\nPASS\n");
  else            printf("\n%d FAILURES\n", g_fail);
  return g_fail ? 1 : 0;
}

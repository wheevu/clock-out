/* ai.c -- utility combat AI.
 * Recreated after the bad rename destroyed the original implementation.
 * The matching header is ai.H (this file implements it). */
#include "ai.H"
#include "combat.H"   /* full Entity definition for ai_choose */

/* choose the enemy's action for this turn, informed by the telegraphed
 * intent already stored in g_combat. The caller is responsible for
 * emitting/executing the returned Event. The active turn loop uses
 * execute_intent(); this remains a utility that reads the same intent fields. */
Event ai_choose(Entity *e){
  Event ev;
  ev.type = EV_DEAL_DAMAGE;
  ev.src = e ? e->id : 0;
  ev.dst = (e && e->team == 1) ? g_combat.player.id : 0u;  /* enemy acts on the player */
  /* mirror the currently telegraphed intent value when it is an attack */
  ev.a = (g_combat.enemy_intent_type == COMBAT_INTENT_ATTACK) ? g_combat.enemy_intent_value : 0;
  ev.b = 0; ev.ref = 0; ev.deferred = 0; ev.seq = 0;
  return ev;
}

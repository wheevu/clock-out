/* ai.c -- utility combat AI.
 * Recreated after the bad rename destroyed the original implementation.
 * The matching header is ai.H (this file implements it). */
#include "ai.H"
#include "combat.H"   /* full Entity definition for ai_choose */

/* choose the enemy's action for this turn.
 * For now a simple aggressive profile: swing for a small fixed hit on the
 * player. The caller is responsible for emitting/executing the returned Event. */
Event ai_choose(Entity *e){
  Event ev;
  ev.type = EV_DEAL_DAMAGE;
  ev.src = e ? e->id : 0;
  ev.dst = (e && e->team == 1) ? 1u : 0u;   /* enemy acts on the player (id 1) */
  ev.a = 5; ev.b = 0; ev.ref = 0; ev.deferred = 0; ev.seq = 0;
  return ev;
}

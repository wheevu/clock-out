/* cards.h -- card registry, deck, effect interpreter, statuses. */
#ifndef CARDS_H
#define CARDS_H
#include "../include/contracts.HC"
#include "combat.H"

/* registers a single card definition (also backs contracts.h card_register). */
void card_register(CardDef d);
CardDef *card_by_id(uint32_t id);

/* build the player's collection deck from a starter set. */
void cards_init(void);

/* the player's collection (defined in cards.c). */
extern uint32_t g_deck[MAX_DECK];
extern int      g_deck_n;

/* apply a status to an entity. mag added to stacks; turns = lifetime
 * (negative turns => permanent this combat). */
void apply_status(Entity *e, int st, int mag, int turns);

/* damage application: block first, then hp. Routes to the player or enemy
 * entity by id. */
void apply_damage(uint32_t dst, int dmg);

/* run a card's effect list. target_body = physics body id for OP_FORCE, 0=default. */
void run_effects(CardDef *c, Entity *src, Entity *dst, uint32_t target_body);

#endif

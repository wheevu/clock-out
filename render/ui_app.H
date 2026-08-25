/* render/ui_app.h -- screen compositor: turns live game state into UI frames.
 * Portable C99. Layers the 2D UI module (ui.H) over the 3D palette scene
 * produced by render.H. Every function draws the FULL current frame (calls
 * rndr_begin + ui_begin internally), so the caller just picks a screen and
 * then calls uia_present. Deterministic: these only read state and draw.
 *
 * The 3D scene is authored by each screen (or shown via uia_scene_* overrides);
 * the UI widgets (title, dialogue box, card hand, bars) are the 2D layer.
 */
#ifndef UI_APP_H
#define UI_APP_H

#include "ui.H"
#include "../include/contracts.HC"
#include "../game/combat.H"
#include "../narrative/dsl.H"
#include <stdint.h>

/* Which screen to build. Kept as an enum so a future run-loop can switch on it. */
typedef enum {
  UIA_TITLE = 0,     /* 퇴근 logo over a night office diorama */
  UIA_DIALOGUE,      /* scene text + a nameplate + an "advance" hint */
  UIA_CHOICE,        /* dialogue + a vertical choice list */
  UIA_COMBAT,        /* boss bar top, hand bottom, energy/HP strip, enemy sprite */
  UIA_EXPLORE,       /* in-world exploration: player sprite, plaque, HUD */
  UIA_MESSENGER,     /* retro corporate messenger inbox */
  UIA_SCHEDULE,      /* evening activity choice with cost/consequence */
  UIA_REWARD,        /* three-card reward, one selected */
  UIA_GAMEOVER,      /* authored resignation form + red stamp + clock */
  UIA_COUNT
} UiaScreen;

/* Seed the screens: load baked sprites, warm palettes. Call once. */
void uia_init(void);

/* ---- scene overrides (draw the 3D world first; defaults auto-draw). ---- */

/* Draw a canned night office diorama: perspective room, rear city windows,
 * rows of cubicles + monitors, fluorescent fixtures that flicker. */
void uia_scene_office(double t);
/* Draw the boss room: long desk, vertical red server-shrine, moving light. */
void uia_scene_boss(double t);
/* Draw an empty dark night backdrop (mostly background + a broken neon sign). */
void uia_scene_empty(double t);

/* ---- screens (each draws the whole frame; take a time `t` for anim). ---- */
void uia_title(double t);

/* Dialogue: full scene for an arbitrary UTF-8 line. speaker can be NULL.
 * nameplate shows COMPAN (company) if speaker is NULL. */
void uia_dialogue(double t, const char *speaker, const char *text);

/* Choice: draws dialogue + a vertical list. idx (which option is hovered)
 * can be -1 for none. */
void uia_choice(double t, const char *speaker, const char *text,
                PendingChoice *c, int idx);

/* Explore: authored in-world screen. location/objective are UTF-8 strings
 * (NULL-safe). Shows the player sprite, a location plaque, an objective line,
 * an interaction prompt, and a compact HP/nunchi HUD. */
void uia_explore(double t, const char *location, const char *objective);

/* Messenger: retro corporate inbox. selected is the focused sender row. */
void uia_messenger(double t, int selected);

/* Schedule: evening activity choice. selected is the focused activity. */
void uia_schedule(double t, int selected);

/* Reward: three real cards (uia_card) from card_ids; selected is the focused
 * one (0..2) or -1. A NULL/0 id draws an empty slot. */
void uia_reward(double t, const uint32_t card_ids[3], int selected);

/* Combat: enemy name + HP bar + intent top, worker sprite left, boss right,
 * hand of cards bottom (from g_combat.hand), resources top-left.
 * selected_card raises that hand card; -1 means none. */
void uia_combat_focus(double t, int selected_card);

/* Combat compatibility wrapper: draws the whole combat frame with no card
 * raised. Calls uia_combat_focus(t, -1). */
void uia_combat(double t);

/* Game-over: dark screen + authored "사직서" form, red stamp, system clock. */
void uia_gameover(double t);

/* Present the composited frame to a PPM (path may be NULL). */
void uia_present(const char *ppm_path);

/* How to highlight a card in the hand (hovered = raised + bright border). */
typedef enum { UIA_CARD_NORMAL = 0, UIA_CARD_HOVER = 1, UIA_CARD_DISABLED = 2 } UiaCardSel;

/* Draw one card into (x,y,w,h). Reads id via card_name/card_text/card_by_id.
 * Picks an art scheme by CardDef.type. cost is drawn in a corner badge. */
void uia_card(int x, int y, int w, int h, uint32_t card_id, UiaCardSel sel);

/* ---- small pure queries (unit-testable) ---- */

/* True when the enemy intent telegraph may show its real type/value:
 * the enemy intent exists AND (the enemy has ST_REVEAL OR nunchi >= 6).
 * When false the UI renders only "???". */
int uia_intent_revealed(void);

 /* Computed bottom-hand layout for `hand_n` cards (clamped to [0, MAX_HAND]).
  * Guarantees every card stays inside the frame: x0 >= margin and
  * x0 + (count-1)*stride + card_w <= RW - margin. When 10 cards cannot fit
  * at full width the stride shrinks first, then the card width (down to a
  * floor), and only then cards may overlap rather than run off-screen. */
typedef struct {
    int count;   /* clamped card count actually laid out */
    int x0;      /* left edge of the first card */
    int stride;  /* per-card advance (may be < card_w only in overlap mode) */
    int card_w;  /* drawn card width */
} UiaHandLayout;

UiaHandLayout uia_hand_layout(int hand_n);

#endif

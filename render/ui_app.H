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
  UIA_GAMEOVER,      /* stiff "사직" / defeat */
  UIA_COUNT
} UiaScreen;

/* Seed the screens: load baked sprites, warm palettes. Call once. */
void uia_init(void);

/* ---- scene overrides (draw the 3D world first; defaults auto-draw). ---- */

/* Draw a canned night office diorama with desks + a sleeping worker, camera
 * pushed back. `t` in [0,1] can animate the air-conditioner/clock. */
void uia_scene_office(double t);
/* Draw the boss room: a lone desk, a big vermilion "주인" silhouette. */
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

/* Combat: enemy name + HP bar + intent top, worker sprite left, boss right,
 * hand of cards bottom (from g_combat.hand), resources top-left. */
void uia_combat(double t);

/* Game-over: dark screen + "사직한다" / "퇴근 실패" line. */
void uia_gameover(double t);

/* Present the composited frame to a PPM (path may be NULL). */
void uia_present(const char *ppm_path);

/* How to highlight a card in the hand (hovered = raised + bright border). */
typedef enum { UIA_CARD_NORMAL = 0, UIA_CARD_HOVER = 1, UIA_CARD_DISABLED = 2 } UiaCardSel;

/* Draw one card into (x,y,w,h). Reads id via card_name/card_text/card_by_id.
 * Picks an art scheme by CardDef.type. cost is drawn in a corner badge. */
void uia_card(int x, int y, int w, int h, uint32_t card_id, UiaCardSel sel);

#endif

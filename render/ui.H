/* render/ui.h -- 2D true-color compositor layered over the 3D palette scene.
 * Portable C99. This module draws immediate-mode 2D UI (panels, bars, cards,
 * Korean/Latin text) into an internal RGBA overlay, then composites it over the
 * deterministic palette framebuffer produced by render/render.HC. The 3D scene
 * stays palette-indexed and unchanged; the UI layer is full-color on top.
 *
 * Surface layout (must match render.H): RW=640, RH=360.
 * All coordinates are in this 640x360 space.
 *
 * Compositor model per frame:
 *   1) renderer draws the 3D scene into the palette buffer (rndr_*),
 *   2) ui_begin() clears the true-color overlay,
 *   3) ui_* widget calls record into the overlay,
 *   4) ui_present(ppm) maps palette->RGB, alpha-blends the overlay, writes PPM.
 * Overlay pixels are RGBA (4 bytes/px); alpha 0 writes through to the 3D scene.
 */
#ifndef UI_COM_H
#define UI_COM_H

#include "../include/contracts.HC"
#include "render.H"
#include <stdint.h>
#include <stdio.h>

#define UI_W RW
#define UI_H RH

/* ---- baked sprite ---- */
typedef struct {
  int w, h;
  uint8_t *rgba; /* w*h*4, loaded from an assets/baked blob (or NULL) */
} UISprite;

/* ---- lifecycle ---- */
void ui_init(void);          /* load manifest (once), reset overlay */

/* Clear the overlay for a new frame. */
void ui_begin(void);

/* Present: composite overlay over the palette scene and write a PPM.
 * Pixels with overlay.a==255 fully replace; a==0 keep the scene;
 * 1..254 alpha-blend. path may be NULL (skip write). */
void ui_present(const char *ppm_path);

/* ---- palette access (for pixel-level 3D scenes) ---- */
const uint8_t *ui_scene_fb(void);   /* live palette buffer (RW*RH) */
const uint8_t *ui_scene_palette(void);
uint8_t ui_scene_color_at(int x, int y);   /* palette index, 0 if OOB */

/* ---- sprite access (baked) ---- */
/* Load (if needed) and return a baked sprite by manifest key, or NULL.
 * Keys are fixed by asset_bake.py -- see assets/baked/manifest.txt. */
UISprite *ui_sprite(const char *key);
int ui_sprite_loaded(void);   /* 1 once the manifest has been read */
int ui_sprite_count(void);

/* ===================== PRIMITIVES (overlay) ===================== */
/* Fill a solid pixel with alpha (color is straight RGBA). */
void ui_pixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
/* Solid rectangle, alpha-blended. */
void ui_fill_rect(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
/* Rectangle outline (1px border), alpha-blended. */
void ui_draw_rect(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
/* Filled panel with a 1px raised border (keeps a subtle 9-slice feel). */
void ui_panel(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
/* Blit a baked sprite at (x,y) (top-left), scaling integer `scale` (>=1). */
void ui_blit(UISprite *s, int x, int y, int scale);
/* Blit a baked sprite into a target rect, scaling to fit (aspect kept). */
void ui_blit_fit(UISprite *s, int x, int y, int w, int h);

/* ---- text ---- */
/* Draw a UTF-8 string at (x,y) in color (r,g,b). Uses the korean hangul
 * compose path for syllables and the built-in Latin glyphs for ASCII.
 * Returns the pixel advance (width) used. */
int ui_text(int x, int y, const char *utf8, uint8_t r, uint8_t g, uint8_t b);
/* Same, but aligned within a box (align: 0 left, 1 center, 2 right). */
void ui_text_align(int x, int y, int w, int h, const char *utf8,
                   uint8_t r, uint8_t g, uint8_t b, int align);
/* Wrapped paragraph inside a box; returns number of lines drawn. */
int ui_text_wrap(int x, int y, int w, int h, const char *utf8,
                 uint8_t r, uint8_t g, uint8_t b);
int ui_text_width(const char *utf8);   /* pixel width of a single line */

/* Draw a UTF-8 string at (x,y) scaled to `size` px per glyph cell (>=1,
 * integer nearest). Uses the Korean compose path (Hangul) and Latin glyphs.
 * Returns the pixel advance width at that scale. */
int ui_text_scaled(int x, int y, const char *utf8, int size,
                   uint8_t r, uint8_t g, uint8_t b);

/* ---- bars ---- */
/* Horizontal fill bar. pct in [0,1]. */
void ui_bar(int x, int y, int w, int h, double pct,
            uint8_t r, uint8_t g, uint8_t b, uint8_t a);
/* Vertical fill bar (pct [0,1], fills upward). */
void ui_bar_v(int x, int y, int w, int h, double pct,
              uint8_t r, uint8_t g, uint8_t b, uint8_t a);

#endif

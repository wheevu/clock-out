/* render/render.h -- tiny software 3D renderer for 성광정보기술.
 * Portable C99. Framebuffer 640x360, palette-indexed.
 * Includes ../../include/contracts.h for Vec3/Mat4 math. */
#ifndef RENDER_H
#define RENDER_H

#include "../include/contracts.HC"

#define RW 640            /* framebuffer width  */
#define RH 360            /* framebuffer height */
#define RNDR_NPAL 256     /* palette size       */

/* Palette layout: 16 오방색 (obangsaek) hue columns x 16 luminance steps.
 * Index = (hueCol << 4) | step, where step 0 = darkest, 15 = brightest.
 * Scene code should pick a mid step (RNDR_STEP_MID) as "lit average"; the
 * renderer shades faces brighter/darker and fogs depth, all within the same
 * hue column so colors never hue-shift. Index 0 is the night background. */
enum {
    HUE_CHARCOAL = 0,  /* dark greys   */
    HUE_TEAL     = 1,  /* 청 cyan      */
    HUE_JADE     = 2,  /* 벽 jade green*/
    HUE_VERMILION= 3,  /* 홍 vermilion  */
    HUE_GOLD     = 4,  /* 황 gold       */
    HUE_WHITE    = 5,  /* 백 white      */
    HUE_VIOLET   = 6,  /* 자 violet     */
    HUE_INDIGO   = 7,  /* 남 indigo     */
    HUE_PINK     = 8,  /* 분홍 pink     */
    HUE_MOSS     = 9,  /* 녹 moss       */
    HUE_ORANGE   = 10, /* 주 orange     */
    HUE_BROWN    = 11, /* 목 brown      */
    HUE_SLATE    = 12, /* slate         */
    HUE_ROSE     = 13, /* rose          */
    HUE_INK      = 14, /* 흑 ink         */
    HUE_TAN      = 15, /* tan           */
};
#define RNDR_COL(hue, step)  ((uint8_t)((((hue) << 4) | (step)) & 0xFF))
#define RNDR_STEP_MID        8
#define RNDR_STEP_DARK       4
#define RNDR_STEP_LIT        11

/* A triangle: 3 world-space positions + a flat base color (0..255). */
typedef struct {
    Vec3 p[3];
    uint8_t color;
} Tri;

/* A mesh is a dynamic bag of triangles. */
typedef struct {
    Tri *t;
    int n;
    int cap;
} Mesh;

/* ---- mesh generators ---- */
Mesh mesh_box(Vec3 center, Vec3 size, uint8_t color);
Mesh mesh_plane(Vec3 center, Vec3 normal, double size, uint8_t color);
Mesh mesh_sphere(Vec3 c, double r, uint8_t color, int seg);
void mesh_free(Mesh *m);

/* ---- camera ---- */
void rndr_set_camera(Vec3 eye, Vec3 tgt);
void rndr_set_camera_pos(Vec3 eye);

/* ---- frame lifecycle ---- */
void rndr_init(void);     /* build default palette + reset state */
void rndr_begin(void);
void rndr_draw(Mesh m);
void rndr_present(const char *ppm_path);

/* ---- wireframe toggle ---- */
void rndr_set_wire(int on);

/* ---- read access (tests / debug) ---- */
const uint8_t *rndr_fb(void);   /* RW*RH palette indices */
const uint8_t *rndr_palette(void);

#endif

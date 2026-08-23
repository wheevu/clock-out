/* render/render.h -- tiny software 3D renderer for 성광정보기술.
 * Portable C99. Framebuffer 320x240, palette-indexed.
 * Includes ../../include/contracts.h for Vec3/Mat4 math. */
#ifndef RENDER_H
#define RENDER_H

#include "../include/contracts.HC"

#define RW 320            /* framebuffer width  */
#define RH 240            /* framebuffer height */
#define RNDR_NPAL 256     /* palette size       */

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

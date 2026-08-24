/* render/render.HC -- software 3D renderer implementation for 성광정보기술.
 * Portable C99. Framebuffer 320x240, palette-indexed.
 * Include guard lives in render.H; this file is the implementation only.
 * Includes contracts.HC for Vec3/Mat4 math (mat_lookat/mat_perspective/mat_transform). */
#include "render.H"
#include "../include/contracts.HC"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

/* near plane (homogeneous w) epsilon; verts with w <= this are behind the eye. */
#define RNDR_NEAR_W 1e-4

/* Lighting / fog tuning. Index 0 is the background; palette entries are laid
 * out as hue columns of 16 luminance steps each (index = hueCol*16 + step),
 * so a face's Lambert shade and per-pixel depth fog can move within a column
 * and always stay on the same hue. */
#define RNDR_PAL_STEP  16          /* luminance steps per hue column  */
#define RNDR_SHADE_SCALE 10        /* shade -> step delta per unit diffuse */
#define RNDR_SHADE_BIAS   5        /* bias so a dark face lands mid-column */
#define RNDR_FOG_STEPS    7        /* extra darkening at full fog distance */
#define RNDR_FOG_NEAR     6.0      /* view-space depth where fog starts (units) */
#define RNDR_FOG_FAR     42.0      /* view-space depth where fog saturates     */

/* local cross product (not in contracts.HC) */
static Vec3 vcross(Vec3 a, Vec3 b) {
    return (Vec3){ a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x };
}

/* moonlight from upper-left-behind; faces toward it read brighter */
static Vec3 g_light = {0, 0, 0};

/* HSV -> RGB on 0..255. s,v in [0,1]. */
static void hsv2rgb(double h, double s, double v, uint8_t *r, uint8_t *g, uint8_t *b) {
    double c = v * s;
    double hp = h / 60.0;
    double x = c * (1.0 - fabs(fmod(hp, 2.0) - 1.0));
    double rr = 0, gg = 0, bb = 0;
    if      (hp < 1) { rr = c; gg = x; }
    else if (hp < 2) { rr = x; gg = c; }
    else if (hp < 3) { gg = c; bb = x; }
    else if (hp < 4) { gg = x; bb = c; }
    else if (hp < 5) { rr = x; bb = c; }
    else             { rr = c; bb = x; }
    double m = v - c;
    *r = (uint8_t)((rr + m) * 255.0 + 0.5);
    *g = (uint8_t)((gg + m) * 255.0 + 0.5);
    *b = (uint8_t)((bb + m) * 255.0 + 0.5);
}

/* ===================== STATIC STATE ===================== */
static uint8_t  g_fb[RW * RH];        /* palette indices, 0 = background */
static double   g_zb[RW * RH];        /* depth buffer (ndc.z, smaller = nearer) */
static uint8_t  g_pal[RNDR_NPAL * 3]; /* RGB palette, 256 entries */
static Vec3     g_eye = {0, 0, 5};
static Vec3     g_tgt = {0, 0, 0};
static Mat4     g_vp;                 /* view-projection matrix */
static int      g_wire = 0;
static int      g_inited = 0;

static void build_palette(void) {
    /* Dancheong night palette. 16 hue columns x 16 luminance steps; each
     * column is an 오방색 (obangsaek) decorative color so level art reads as
     * Korean painted-wood, and every color sits on one hue horizontally so
     * per-face shading / fog never hue-shifts. */
    static const double hue_col[16] = {
        /* 0 charcoal   */ 210,
        /* 1 청 (teal)   */ 185,
        /* 2 벽 (jade)   */ 145,
        /* 3 홍 (verm.)  */ 8,
        /* 4 황 (gold)   */ 42,
        /* 5 백 (white)  */ 210,
        /* 6 자 (violet) */ 285,
        /* 7 남 (indigo) */ 232,
        /* 8 홍 (pink)   */ 330,
        /* 9 녹 (moss)   */ 90,
        /*10 주 (orange) */ 24,
        /*11 목 (brown)  */ 28,
        /*12 방 (slate)  */ 214,
        /*13 분 (rose)   */ 350,
        /*14 흑 (ink)    */ 220,
        /*15 다 (tan)    */ 34,
    };
    /* saturation per column; white/charcoal are near-neutral to glow/fall away */
    static const double sat_col[16] = {
        0.06, 0.62, 0.55, 0.78, 0.82, 0.05, 0.50, 0.62,
        0.58, 0.45, 0.80, 0.42, 0.18, 0.52, 0.30, 0.40,
    };

    for (int i = 0; i < RNDR_NPAL; i++) {
        int col = i / RNDR_PAL_STEP;
        int st  = i % RNDR_PAL_STEP;
        double s = sat_col[col];
        double v_min = (col == 0 || col == 5) ? 0.08 : 0.12;
        double v_max = (col == 5) ? 1.00 : 0.90;
        double v = v_min + (v_max - v_min) * (double)st / (double)(RNDR_PAL_STEP - 1);
        /* col 5 (백 white) has a narrow, cool hue so it stays clean */
        double h = hue_col[col] + ((col == 5) ? 0.0 : 0.0);
        uint8_t r, g, b;
        hsv2rgb(h, s, v, &r, &g, &b);
        g_pal[i * 3 + 0] = r;
        g_pal[i * 3 + 1] = g;
        g_pal[i * 3 + 2] = b;
    }
    /* Index 0 is the pure background: 3:17 AM night, not black. */
    g_pal[0] = 10; g_pal[1] = 18; g_pal[2] = 30;
    g_pal[5 * RNDR_PAL_STEP * 3 + 0] = 0; /* col5 step0 = clean white floor */
    g_pal[5 * RNDR_PAL_STEP * 3 + 1] = 0;
    g_pal[5 * RNDR_PAL_STEP * 3 + 2] = 0;
}

static void build_light(void) {
    g_light = vnorm((Vec3){ -0.45, 0.75, 0.50 });
}

static void rebuild_vp(void) {
    double aspect = (double)RW / (double)RH;
    Mat4 proj = mat_perspective(60.0 * (3.141592653589793 / 180.0), aspect, 0.1, 100.0);
    Mat4 view = mat_lookat(g_eye, g_tgt, (Vec3){0, 1, 0});
    /* mat_transform treats points as row vectors: combined = view * proj */
    g_vp = mat_mul(view, proj);
}

/* ===================== PUBLIC INIT ===================== */
void rndr_init(void) {
    build_palette();
    build_light();
    rebuild_vp();
    memset(g_fb, 0, sizeof(g_fb));
    for (int i = 0; i < RW * RH; i++) g_zb[i] = 1e30;
    g_inited = 1;
}

/* ===================== CAMERA ===================== */
void rndr_set_camera(Vec3 eye, Vec3 tgt) {
    g_eye = eye;
    g_tgt = tgt;
    rebuild_vp();
}
void rndr_set_camera_pos(Vec3 eye) {
    g_eye = eye;
    rebuild_vp();
}

/* ===================== FRAME LIFECYCLE ===================== */
void rndr_begin(void) {
    if (!g_inited) rndr_init();
    memset(g_fb, 0, sizeof(g_fb));
    for (int i = 0; i < RW * RH; i++) g_zb[i] = 1e30;
}

void rndr_set_wire(int on) { g_wire = on; }

/* ===================== ACCESSORS ===================== */
const uint8_t *rndr_fb(void)      { return g_fb; }
const uint8_t *rndr_palette(void) { return g_pal; }

/* ===================== RASTERIZATION ===================== */
/* clip a polygon (in clip space, each v = {x,y,z,w}) against w >= RNDR_NEAR_W.
 * out holds up to 8 verts (Vec3 reused: x,y,z = cx,cy,cz, w packed in ... we use
 * a parallel w array). Returns vertex count. */
static int clip_near(const double cx[8], const double cy[8], const double cz[8],
                     const double cw[8], int n,
                     double ox[8], double oy[8], double oz[8], double ow[8]) {
    if (n < 3) return 0;
    int cnt = 0;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        double w0 = cw[i], w1 = cw[j];
        int in0 = w0 > RNDR_NEAR_W, in1 = w1 > RNDR_NEAR_W;
        if (in0) {
            ox[cnt] = cx[i]; oy[cnt] = cy[i]; oz[cnt] = cz[i]; ow[cnt] = cw[i]; cnt++;
        }
        if (in0 != in1) {
            double t = (RNDR_NEAR_W - w0) / (w1 - w0);
            ox[cnt] = cx[i] + t * (cx[j] - cx[i]);
            oy[cnt] = cy[i] + t * (cy[j] - cy[i]);
            oz[cnt] = cz[i] + t * (cz[j] - cz[i]);
            ow[cnt] = cw[i] + t * (cw[j] - cw[i]);
            cnt++;
        }
    }
    return cnt;
}

/* rasterize one projected polygon (already w>0) using a triangle fan.
 * `color` is the base palette index (hue column + base step); `lightStep` is a
 * constant per-face Lambert offset, and each pixel applies a depth fog offset
 * so distant texels fall toward the column's dark end. Final index stays in
 * the same hue column (col*16 .. col*16+15). */
static void raster_poly(const double cx[8], const double cy[8], const double cz[8],
                        const double cw[8], int n, uint8_t color, int lightStep) {
    if (n < 3) return;
    /* project vertices once */
    double sx[8], sy[8], dz[8], iw[8];
    for (int i = 0; i < n; i++) {
        double inv = 1.0 / cw[i];
        double nx = cx[i] * inv, ny = cy[i] * inv, nz = cz[i] * inv;
        sx[i] = (nx * 0.5 + 0.5) * (double)RW;
        sy[i] = (1.0 - (ny * 0.5 + 0.5)) * (double)RH;
        dz[i] = nz;  /* ndc.z, smaller = nearer (z-buffer) */
        iw[i] = inv; /* 1/w is affine in screen space -> perspective-correct depth */
    }

    int col = color / RNDR_PAL_STEP;
    int baseStep = color % RNDR_PAL_STEP;

    for (int f = 1; f + 1 < n; f++) {
        double ax = sx[0],  ay = sy[0],  az = dz[0],  ai = iw[0];
        double bx = sx[f],  by = sy[f],  bz = dz[f],  bi = iw[f];
        double dx = sx[f+1], dy = sy[f+1], dz2 = dz[f+1], di = iw[f+1];

        double minx = floor(fmin(fmin(ax, bx), dx));
        double maxx = ceil (fmax(fmax(ax, bx), dx));
        double miny = floor(fmin(fmin(ay, by), dy));
        double maxy = ceil (fmax(fmax(ay, by), dy));
        int x0 = (int)minx, x1 = (int)maxx, y0 = (int)miny, y1 = (int)maxy;
        if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0;
        if (x1 > RW) x1 = RW; if (y1 > RH) y1 = RH;

        double area = (bx - ax) * (dy - ay) - (dx - ax) * (by - ay);
        if (fabs(area) < 1e-9) continue;

        for (int y = y0; y < y1; y++) {
            double py = (double)y + 0.5;
            for (int x = x0; x < x1; x++) {
                double px = (double)x + 0.5;
                double w0 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) / area;
                double w1 = ((dx - bx) * (py - by) - (dy - by) * (px - bx)) / area;
                double w2 = ((ax - dx) * (py - dy) - (ay - dy) * (px - dx)) / area;
                if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) continue;
                double zp = w0 * az + w1 * bz + w2 * dz2;
                int idx = y * RW + x;
                if (zp < g_zb[idx]) {
                    g_zb[idx] = zp;
                    /* depth fog from perspective-correct view depth (1/w) */
                    double vdepth = 1.0 / (w0 * ai + w1 * bi + w2 * di);
                    double fog = (vdepth - RNDR_FOG_NEAR) / (RNDR_FOG_FAR - RNDR_FOG_NEAR);
                    if (fog < 0.0) fog = 0.0;
                    if (fog > 1.0) fog = 1.0;
                    int step = baseStep + lightStep - (int)(fog * RNDR_FOG_STEPS + 0.5);
                    if (step < 1) step = 1;   /* never resolve to background index 0 */
                    if (step > RNDR_PAL_STEP - 1) step = RNDR_PAL_STEP - 1;
                    uint8_t out = (uint8_t)(col * RNDR_PAL_STEP + step);
                    if (g_wire) {
                        /* draw only near edges: cheap wire = top/bottom rows of bbox */
                        int edge = (y == y0) || (y == y1 - 1) || (x == x0) || (x == x1 - 1);
                        if (edge) g_fb[idx] = out;
                    } else {
                        g_fb[idx] = out;
                    }
                }
            }
        }
    }
}

static void draw_tri_clip(const double cx[3], const double cy[3],
                          const double cz[3], const double cw[3],
                          uint8_t color, int lightStep) {
    double oxx[8], oyy[8], ozz[8], oww[8];
    int m = clip_near(cx, cy, cz, cw, 3, oxx, oyy, ozz, oww);
    if (m < 3) return; /* fully behind camera -> culled (writes nothing) */
    raster_poly(oxx, oyy, ozz, oww, m, color, lightStep);
}

/* Face-normal Lambert shading for one triangle. The mesh helpers wind their
 * faces inward, and the rasterizer draws both sides (no back-face culling), so
 * flip the normal toward the eye: points away from the eye get their outward
 * normal. This keeps lighting correct for box/sphere primitives and any
 * hand-built surface regardless of winding. */
static int face_light(Vec3 a, Vec3 b, Vec3 c) {
    Vec3 e1 = vsub(b, a);
    Vec3 e2 = vsub(c, a);
    Vec3 n = vcross(e1, e2);
    double l = vlen(n);
    if (l < 1e-12) return 0;
    n = vscale(n, 1.0 / l);
    /* orient the normal toward the viewer */
    if (vdot(n, vsub(g_eye, a)) < 0.0) n = vscale(n, -1.0);
    double diffuse = vdot(n, g_light);
    if (diffuse < 0.0) diffuse = 0.0;
    double eff = 0.18 + 0.82 * diffuse;   /* ambient floor so back faces stay visible */
    int step = (int)((eff - 0.5) * RNDR_SHADE_SCALE + (eff >= 0.5 ? 0.5 : -0.5));
    return step;
}

/* ===================== DRAW ===================== */
void rndr_draw(Mesh m) {
    if (!g_inited) rndr_init();
    for (int i = 0; i < m.n; i++) {
        Tri *t = &m.t[i];
        double cx[3], cy[3], cz[3], cw[3];
        for (int k = 0; k < 3; k++) {
            mat_transform(g_vp, t->p[k], &cx[k], &cy[k], &cz[k], &cw[k]);
        }
        int light = face_light(t->p[0], t->p[1], t->p[2]);
        draw_tri_clip(cx, cy, cz, cw, t->color, light);
    }
}

/* ===================== PRESENT ===================== */
void rndr_present(const char *ppm_path) {
    FILE *fp = fopen(ppm_path, "wb");
    if (!fp) return;
    fprintf(fp, "P6\n%d %d\n255\n", RW, RH);
    for (int i = 0; i < RW * RH; i++) {
        uint8_t idx = g_fb[i];
        fputc(g_pal[idx * 3 + 0], fp);
        fputc(g_pal[idx * 3 + 1], fp);
        fputc(g_pal[idx * 3 + 2], fp);
    }
    fclose(fp);
}

/* ===================== MESH GENERATORS ===================== */
static Mesh mesh_push(Mesh m, Tri t) {
    if (m.n == m.cap) {
        int nc = m.cap ? m.cap * 2 : 16;
        Tri *nt = realloc(m.t, nc * sizeof(Tri));
        if (!nt) return m;
        m.t = nt; m.cap = nc;
    }
    m.t[m.n++] = t;
    return m;
}

Mesh mesh_box(Vec3 center, Vec3 size, uint8_t color) {
    Mesh m = {0};
    Vec3 h = { size.x * 0.5, size.y * 0.5, size.z * 0.5 };
    Vec3 c[8];
    for (int i = 0; i < 8; i++) {
        c[i] = (Vec3){ center.x + (i & 1 ? h.x : -h.x),
                       center.y + (i & 2 ? h.y : -h.y),
                       center.z + (i & 4 ? h.z : -h.z) };
    }
    int faces[6][4] = {
        {0,1,3,2}, {4,6,7,5}, {0,4,5,1}, {2,3,7,6}, {0,2,6,4}, {1,5,7,3}
    };
    for (int f = 0; f < 6; f++) {
        int *v = faces[f];
        Tri t1 = { {c[v[0]], c[v[1]], c[v[2]]}, color };
        Tri t2 = { {c[v[0]], c[v[2]], c[v[3]]}, color };
        m = mesh_push(m, t1);
        m = mesh_push(m, t2);
    }
    return m;
}

Mesh mesh_plane(Vec3 center, Vec3 normal, double size, uint8_t color) {
    Mesh m = {0};
    Vec3 n = vnorm(normal);
    /* pick a non-parallel axis to build a tangent basis */
    Vec3 ref = (fabs(n.y) < 0.99) ? (Vec3){0,1,0} : (Vec3){1,0,0};
    Vec3 u = vnorm(vsub((Vec3){0,0,0}, vscale(n, vdot(n, ref))));
    if (vlen2(u) < 1e-9) u = (Vec3){1,0,0};
    Vec3 w = vnorm(vcross(n, u));
    double hs = size * 0.5;
    Vec3 c[4];
    c[0] = vadd(center, vadd(vscale(u, -hs), vscale(w, -hs)));
    c[1] = vadd(center, vadd(vscale(u,  hs), vscale(w, -hs)));
    c[2] = vadd(center, vadd(vscale(u,  hs), vscale(w,  hs)));
    c[3] = vadd(center, vadd(vscale(u, -hs), vscale(w,  hs)));
    Tri t1 = { {c[0], c[1], c[2]}, color };
    Tri t2 = { {c[0], c[2], c[3]}, color };
    m = mesh_push(m, t1);
    m = mesh_push(m, t2);
    return m;
}

Mesh mesh_sphere(Vec3 c, double r, uint8_t color, int seg) {
    Mesh m = {0};
    if (seg < 3) seg = 3;
    for (int iy = 0; iy < seg; iy++) {
        double v0 = (iy)     * (3.141592653589793 / seg) - 1.5707963267948966;
        double v1 = (iy + 1) * (3.141592653589793 / seg) - 1.5707963267948966;
        for (int ix = 0; ix < seg; ix++) {
            double u0 = (ix)     * (2.0 * 3.141592653589793 / seg);
            double u1 = (ix + 1) * (2.0 * 3.141592653589793 / seg);
            Vec3 p00 = { c.x + r*cos(v0)*cos(u0), c.y + r*sin(v0), c.z + r*cos(v0)*sin(u0) };
            Vec3 p10 = { c.x + r*cos(v0)*cos(u1), c.y + r*sin(v0), c.z + r*cos(v0)*sin(u1) };
            Vec3 p01 = { c.x + r*cos(v1)*cos(u0), c.y + r*sin(v1), c.z + r*cos(v1)*sin(u0) };
            Vec3 p11 = { c.x + r*cos(v1)*cos(u1), c.y + r*sin(v1), c.z + r*cos(v1)*sin(u1) };
            Tri t1 = { {p00, p10, p11}, color };
            Tri t2 = { {p00, p11, p01}, color };
            m = mesh_push(m, t1);
            m = mesh_push(m, t2);
        }
    }
    return m;
}

void mesh_free(Mesh *m) {
    if (m && m->t) { free(m->t); m->t = NULL; m->n = m->cap = 0; }
}

/* tests/render_test.c -- renderer smoke test for 성광정보기술.
 * Builds a box + sphere, draws them, and checks the framebuffer has lit pixels.
 * Also confirms a triangle fully behind the camera is culled without crashing. */
#include "../render/render.H"
#include "../include/contracts.HC"
#include <stdio.h>

int main(void) {
    int fail = 0;

    /* camera looking down -Z at the origin */
    rndr_set_camera((Vec3){0, 0, 5}, (Vec3){0, 0, 0});
    rndr_set_wire(0);

    rndr_begin();

    Mesh box = mesh_box((Vec3){0, 0, 0}, (Vec3){2, 2, 2}, 1);
    Mesh sph = mesh_sphere((Vec3){1.5, 0, 0}, 1.0, 2, 16);
    rndr_draw(box);
    rndr_draw(sph);

    rndr_present("/tmp/out.ppm");

    /* count non-background pixels (bg = palette index 0) */
    const uint8_t *f = rndr_fb();
    int lit = 0;
    for (int i = 0; i < RW * RH; i++) if (f[i] != 0) lit++;

    printf("lit pixels: %d / %d\n", lit, RW * RH);
    if (lit < 100) { printf("FAIL: too few lit pixels\n"); fail = 1; }

    /* sanity: a lit pixel must carry a non-bg palette entry */
    int bad = 0;
    for (int i = 0; i < RW * RH; i++) {
        if (f[i] != 0 && (f[i] % 8) == 0 && (f[i] / 8) == 0) bad++;
    }
    if (bad) { printf("FAIL: bg-colored lit pixel count = %d\n", bad); fail = 1; }

    mesh_free(&box);
    mesh_free(&sph);

    /* behind-camera triangle: all verts behind the eye -> must be culled. */
    rndr_begin();
    Mesh behind = {0};
    Tri t; t.color = 3;
    t.p[0] = (Vec3){0, 0, 8};   /* eye is at z=5, so z=8 is BEHIND camera */
    t.p[1] = (Vec3){1, 0, 8};
    t.p[2] = (Vec3){0, 1, 8};
    behind.t = &t; behind.n = 1; behind.cap = 1;
    rndr_draw(behind);          /* must not crash; writes nothing */
    rndr_present("/tmp/out_behind.ppm");
    int lit2 = 0;
    const uint8_t *f2 = rndr_fb();
    for (int i = 0; i < RW * RH; i++) if (f2[i] != 0) lit2++;
    printf("behind-camera lit pixels: %d (expect 0)\n", lit2);
    if (lit2 != 0) { printf("FAIL: behind-camera triangle was drawn\n"); fail = 1; }

    if (fail) { printf("RESULT: FAIL\n"); return 1; }
    printf("RESULT: PASS\n");
    return 0;
}

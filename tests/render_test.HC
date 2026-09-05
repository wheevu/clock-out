/* tests/render_test.c -- renderer smoke test for 성광정보기술.
 * Builds a box + sphere, draws them, and checks the framebuffer has lit pixels.
 * Also confirms a triangle fully behind the camera is culled without crashing. */
#include "../render/render.H"
#include "../include/contracts.HC"
#include <stdio.h>
#include <string.h>

int main(void) {
    int fail = 0;
    Vec3 normals[] = {{1,0,0}, {0,1,0}, {0,0,1}, {1,2,3}};
    for (int j = 0; j < 4; j++) {
        Vec3 n = vnorm(normals[j]);
        Mesh p = mesh_plane((Vec3){0,0,0}, n, 2, 1);
        Vec3 a = vsub(p.t[0].p[1], p.t[0].p[0]);
        Vec3 b = vsub(p.t[0].p[2], p.t[0].p[0]);
        double area2 = vlen2(a)*vlen2(b)-vdot(a,b)*vdot(a,b);
        if (area2 < 1 || fabs(vdot(a,n)) > 1e-8 || fabs(vdot(b,n)) > 1e-8) {
            printf("FAIL: plane basis %d is degenerate or not tangent\n", j);
            fail = 1;
        }
        mesh_free(&p);
    }

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

    /* Reversing winding cannot change depth in a two-sided rasterizer. */
    rndr_begin();
    Tri slope = {{{-2,-1,1},{2,-1,-3},{0,2,-1}}, RNDR_COL(HUE_TEAL,10)};
    Mesh sloped = {&slope,1,1};
    Mesh front = mesh_box((Vec3){0,0,-.5}, (Vec3){1,1,.1}, RNDR_COL(HUE_GOLD,10));
    rndr_draw(sloped); rndr_draw(front);
    static uint8_t reference[RW*RH];
    memcpy(reference,rndr_fb(),sizeof reference);
    Vec3 first=slope.p[1];slope.p[1]=slope.p[2];slope.p[2]=first;
    rndr_begin();rndr_draw(sloped);rndr_draw(front);
    int changed=0;
    for(int i=0;i<RW*RH;i++)if(reference[i]!=rndr_fb()[i])changed++;
    printf("reversed triangle winding: %d changed pixels\n",changed);
    if(changed>4) {puts("FAIL: depth interpolation depends on vertex order");fail=1;}
    mesh_free(&front);

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

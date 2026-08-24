/* tools/shot.HC -- demo-reel runner for 퇴근 (Clock Out).
 *
 * STANDALONE program (has int main). Drives the renderer + UI compositor from
 * live engine state and emits a sequence of 320x240 PPM frames into
 * assets/shots/frame_NNN.ppm. The Makefile `gif` recipe (tools/asm_gif.py)
 * then assembles those frames into animated GIFs for the README.
 *
 * It links the full engine via the wildcard globs in the Makefile: all of the
 * core, korean, render, physics, game, narrative and content sources, plus
 * this file. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "include/contracts.HC"
#include "physics/phys.H"
#include "game/cards.H"
#include "render/render.H"
#include "render/ui.H"
#include "render/ui_app.H"
#include "narrative/relationships.H"
#include "narrative/scheduler.H"
#include "narrative/messenger.H"
#include "narrative/campaign.H"
#include "narrative/dsl.H"          /* g_player, g_pending_choice, dsl_* */

/* ---- content card registry registration (defined in content/cards.HC) ---- */
void content_register_all(void);

/* ---- engine globals the linker needs (g_rng itself is defined in
 *      core/events.HC as NULL; we point it at our instance, like the
 *      integration test does). ---- */
RNG g_rng_inst;

/* ---- combat-start hook (declared extern in narrative/dsl.H) ----
 * When a narrative scene triggers a fight, begin enemy 100. */
void on_combat_start(const char *name) {
    (void)name;
    combat_start(100);
}

/* ---- event dispatch hook (extern in core/events.HC) ----
 * Applies combat events to the battle entities, mirroring the integration
 * test, so the demo reel's combat screen reflects real damage/heal. */
void ev_dispatch(Event e) {
    switch (e.type) {
        case EV_DEAL_DAMAGE:
            if      (e.dst == g_combat.player.id) apply_damage(g_combat.player.id, e.a);
            else if (e.dst == g_combat.enemy.id)  apply_damage(g_combat.enemy.id, e.a);
            break;
        case EV_HEAL:
            if (e.dst == g_combat.player.id) {
                g_combat.player.hp += e.a;
                if (g_combat.player.hp > g_combat.player.maxhp) g_combat.player.hp = g_combat.player.maxhp;
            } else if (e.dst == g_combat.enemy.id) {
                g_combat.enemy.hp += e.a;
                if (g_combat.enemy.hp > g_combat.enemy.maxhp) g_combat.enemy.hp = g_combat.enemy.maxhp;
            }
            break;
        case EV_APPLY_STATUS:
            if      (e.dst == g_combat.player.id) apply_status(&g_combat.player, e.a, e.b, e.b);
            else if (e.dst == g_combat.enemy.id)  apply_status(&g_combat.enemy, e.a, e.b, e.b);
            break;
        case EV_END_CAMPAIGN: campaign_set_flag("clock_out"); break;
        default: break;
    }
}

/* ---- frame emission helper: increments a counter and builds the path ---- */
static int   g_fc    = 0;
static char  g_ppath[320];

static const char *emiti(const char *name) {
    g_fc++;
    snprintf(g_ppath, sizeof g_ppath, "assets/shots/frame_%03d.ppm", g_fc);
    printf("frame %03d [%s] -> %s\n", g_fc, name ? name : "", g_ppath);
    return g_ppath;
}

/* ========================================================================= */
int main(void) {
    /* 1) engine globals + init order (per contract) */
    g_rng = &g_rng_inst;
    rng_init(g_rng, 12345);
    ev_init();
    phys_init();
    content_register_all();
    cards_init();
    rel_init();
    sched_init();
    msg_init();
    campaign_init();
    /* on_combat_start is defined above as the dsl combat hook */

    /* 2) UI compositor */
    uia_init();

    /* make sure the output directory exists at runtime */
    system("mkdir -p assets/shots");

    /* ---- Frames 1..6 : TITLE ---- */
    for (int i = 0; i < 6; i++) {
        g_combat.player.hp = 60;
        uia_title(i * 0.2);
        const char *p = emiti("title");
        uia_present(p);
    }

    /* ---- Frames 7..14 : OFFICE DIALOGUE ---- */
    for (int i = 0; i < 8; i++) {
        rndr_init();
        uia_dialogue(i * 0.2,
                     "김대리",
                     "야, 오늘 마감 늦었잖아. 네가 책임 좀 져.");
        const char *p = emiti("dialogue");
        uia_present(p);
    }

    /* ---- Frames 15..22 : CHOICE (fabricated, mirrors late_office) ---- */
    g_pending_choice.active    = 1;
    g_pending_choice.n         = 3;
    g_pending_choice.opt[0].label = "사과한다";
    g_pending_choice.opt[1].label = "침묵한다";
    g_pending_choice.opt[2].label = "분위기 파악하고 가볍게 넘긴다";
    g_player.nunchi = 8;
    for (int i = 0; i < 8; i++) {
        int idx = (i / 2) % 3;
        uia_choice(i * 0.2, "김대리", "...", &g_pending_choice, idx);
        const char *p = emiti("choice");
        uia_present(p);
    }

    /* ---- Frames 23..32 : COMBAT ---- */
    combat_start(100);
    {
        int set[] = {1, 10, 12, 15, 9, 6, 2, 17, 19, 20};
        int n = (int)(sizeof set / sizeof set[0]);
        if (n > MAX_HAND) n = MAX_HAND;
        g_combat.player.hp        = 60;
        g_combat.player.energy    = 3;
        g_combat.player.maxenergy = 3;
        for (int k = 0; k < n; k++) g_combat.hand[k] = (uint32_t)set[k];
        g_combat.hand_n = n;
    }
    for (int i = 0; i < 10; i++) {
        uia_combat(i * 0.2);
        const char *p = emiti("combat");
        uia_present(p);
    }

    /* ---- Frames 33..36 : BOSS ---- */
    for (int i = 0; i < 4; i++) {
        uia_scene_boss(i * 0.2);
        uia_dialogue(i * 0.2,
                     "주인",
                     "이번 분기 실적, 다 네 탓이다.");
        const char *p = emiti("boss");
        uia_present(p);
    }

    /* ---- Frames 37..40 : GAMEOVER ---- */
    for (int i = 0; i < 4; i++) {
        uia_gameover(i * 0.2);
        const char *p = emiti("gameover");
        uia_present(p);
    }

    printf("SHOTS DONE: %d frames -> assets/shots/\n", g_fc);
    return 0;
}

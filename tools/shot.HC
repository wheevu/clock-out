/* tools/shot.HC -- demo-reel runner for 퇴근 (Clock Out).
 *
 * STANDALONE program (has int main). Drives the renderer + UI compositor from
 * live engine state and emits a deterministic sequence of 640x360 PPM frames
 * into assets/shots/frame_NNN.ppm. The Makefile `gif` recipe (tools/asm_gif.py)
 * then assembles those frames into 10 animated GIFs plus reel.gif for the README.
 *
 * It links the full engine via the wildcard globs in the Makefile: all of the
 * core, korean, render, physics, game, narrative and content sources, plus
 * this file.
 *
 * Frame plan (exactly 84 frames, deterministic):
 *   title     1..8      uia_title
 *   explore   9..16     uia_explore (player/prompt move via t + location)
 *   dialogue 17..24     uia_dialogue
 *   choice   25..32     uia_choice (varies selection)
 *   messenger 33..40    uia_messenger (varies selection)
 *   schedule  41..48    uia_schedule (varies selection)
 *   combat   49..60     uia_combat_focus (plays a real affordable card)
 *   reward   61..68     uia_reward (varies selection)
 *   boss     69..76     boss-like combat, intent/damage progression
 *   gameover 77..84     uia_gameover
 */

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

    /* NOTE: directory creation is owned by the Makefile (`shots` recipe),
     * so no system("mkdir") call here. */

    /* ---- Frames 1..8 : TITLE ---- */
    for (int i = 0; i < 8; i++) {
        g_combat.player.hp = 60;
        uia_title(i * 0.2);
        const char *p = emiti("title");
        uia_present(p);
    }

    /* ---- Frames 9..16 : EXPLORE ----
     * Player/prompt movement is driven by t; we also cycle the location text
     * so the screen varies on more than just t. */
    {
        const char *locs[3] = {"사무실", "회의실", "휴게실"};
        const char *obj = "퇴근까지 남은 시간: 단축";
        g_player.hp = 52;
        g_player.nunchi = 7;
        g_player.wlb = 4;
        for (int i = 0; i < 8; i++) {
            uia_explore(i * 0.2, locs[i % 3], obj);
            const char *p = emiti("explore");
            uia_present(p);
        }
    }

    /* ---- Frames 17..24 : OFFICE DIALOGUE ---- */
    for (int i = 0; i < 8; i++) {
        rndr_init();
        uia_dialogue(i * 0.2,
                     "김대리",
                     "야, 오늘 마감 늦었잖아. 네가 책임 좀 져.");
        const char *p = emiti("dialogue");
        uia_present(p);
    }

    /* ---- Frames 25..32 : CHOICE (fabricated, mirrors late_office) ---- */
    g_pending_choice.active    = 1;
    g_pending_choice.scene_id  = "late_office";
    g_pending_choice.n         = 3;
    g_pending_choice.opt[0].label = "사과한다";
    g_pending_choice.opt[0].target = "apologize";
    g_pending_choice.opt[1].label = "침묵한다";
    g_pending_choice.opt[1].target = "silence";
    g_pending_choice.opt[2].label = "분위기 파악하고 가볍게 넘긴다";
    g_pending_choice.opt[2].target = "deflect";
    g_player.nunchi = 8;
    for (int i = 0; i < 8; i++) {
        int idx = (i / 2) % 3;          /* hover drifts across options */
        uia_choice(i * 0.2, "김대리", "...", &g_pending_choice, idx);
        const char *p = emiti("choice");
        uia_present(p);
    }

    /* ---- Frames 33..40 : MESSENGER ----
     * Seed an inbox, then vary the selected message. */
    {
        uint32_t m0 = msg_deliver(2,  "팀장: 새벽까지 회의 있음. 좀 와라.");
        uint32_t m1 = msg_deliver(3,  "동료: 커피 사올게. 혹시 마감 도와줄까?");
        uint32_t m2 = msg_deliver(4,  "본사: 이번 분기 실적 보고서 제출 바람.");
        uint32_t m3 = msg_deliver(5,  "알림: 오늘 초과근무 3시간 돌파.");
        (void)m0; (void)m1; (void)m2; (void)m3;
        int n = msg_count() > 0 ? msg_count() : 4;
        for (int i = 0; i < 8; i++) {
            int sel = i % n;
            uia_messenger(i * 0.2, sel);
            const char *p = emiti("messenger");
            uia_present(p);
        }
    }

    /* ---- Frames 41..48 : SCHEDULE ----
     * Queue a few scene events, then vary the selected entry. */
    {
        GameTime base = {2026, 8, 25, 1, 540};   /* 09:00 */
        sched_queue(time_add_min(base,   0), "standup",    0);
        sched_queue(time_add_min(base, 120), "lunch",      0);
        sched_queue(time_add_min(base, 240), "meeting",    0);
        sched_queue(time_add_min(base, 360), "clock_out",  0);
        int n = sched_count() > 0 ? sched_count() : 4;
        for (int i = 0; i < 8; i++) {
            int sel = i % n;
            uia_schedule(i * 0.2, sel);
            const char *p = emiti("schedule");
            uia_present(p);
        }
    }

    /* ---- Frames 49..60 : COMBAT (focused) ----
     * Real hand, a real affordable card played once to show damage. */
    combat_start(100);
    {
        int set[] = {10, 12, 1, 4, 9};   /* 세그폴트(2), 월요일(1), 의자(1), 눈치(0), 커피(0) */
        int n = (int)(sizeof set / sizeof set[0]);
        if (n > MAX_HAND) n = MAX_HAND;
        g_combat.player.hp        = 60;
        g_combat.player.energy    = 3;
        g_combat.player.maxenergy = 3;
        for (int k = 0; k < n; k++) g_combat.hand[k] = (uint32_t)set[k];
        g_combat.hand_n = n;
    }
    for (int i = 0; i < 12; i++) {
        int sel = i % g_combat.hand_n;        /* focus drifts across the hand */
        /* play the first affordable card once, mid-sequence, then flush events
         * so the HP bar reflects a real gameplay state change. */
        if (i == 5) {
            CardDef *c = card_by_id(g_combat.hand[0]);
            if (c && g_combat.player.energy >= c->cost) {
                combat_player_play(0, g_combat.enemy.id);
                ev_process_phase();
            }
        }
        uia_combat_focus(i * 0.2, sel);
        const char *p = emiti("combat");
        uia_present(p);
    }

    /* ---- Frames 61..68 : REWARD (card pick) ---- */
    {
        uint32_t card_ids[3] = {10, 15, 20};   /* 세그폴트, 백업, 긴급 배포 */
        for (int i = 0; i < 8; i++) {
            int sel = i % 3;
            uia_reward(i * 0.2, card_ids, sel);
            const char *p = emiti("reward");
            uia_present(p);
        }
    }

    /* ---- Frames 69..76 : BOSS (boss-like combat, intent/damage progression) ---- */
    combat_start(100);
    {
        int set[] = {10, 12, 20, 9, 4};
        int n = (int)(sizeof set / sizeof set[0]);
        if (n > MAX_HAND) n = MAX_HAND;
        g_combat.player.hp        = 60;
        g_combat.player.maxhp     = 60;
        g_combat.player.energy    = 3;
        g_combat.player.maxenergy = 3;
        g_combat.enemy.maxhp      = 120;     /* boss has more HP */
        g_combat.enemy.hp         = 120;
        for (int k = 0; k < n; k++) g_combat.hand[k] = (uint32_t)set[k];
        g_combat.hand_n = n;
    }
    for (int i = 0; i < 8; i++) {
        /* damage progression: enemy HP drops each frame toward defeat */
        int hp = 120 - i * 13;
        if (hp < 1) hp = 1;
        g_combat.enemy.hp = hp;
        int sel = i % g_combat.hand_n;
        uia_combat_focus(i * 0.2, sel);
        const char *p = emiti("boss");
        uia_present(p);
    }

    /* ---- Frames 77..84 : GAMEOVER ---- */
    for (int i = 0; i < 8; i++) {
        uia_gameover(i * 0.2);
        const char *p = emiti("gameover");
        uia_present(p);
    }

    printf("SHOTS DONE: %d frames -> assets/shots/\n", g_fc);
    return 0;
}

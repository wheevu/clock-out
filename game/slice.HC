/* The playable night is input-driven. No wall-clock time enters the simulation. */
#include "slice.H"
#include "cards.H"
#include "../narrative/dsl.H"
#include <string.h>

Slice g_slice;
static RNG night_rng;
void content_register_all(void);
static const uint32_t rewards[] = {10, 15, 20};

void slice_dispatch(Event e) {
    Entity *dst = e.dst == g_combat.player.id ? &g_combat.player :
                  e.dst == g_combat.enemy.id ? &g_combat.enemy : NULL;
    if (!dst) return;
    if (e.type == EV_DEAL_DAMAGE) apply_damage(e.dst, e.a);
    if (e.type == EV_HEAL) apply_heal(dst, e.a);
}

void slice_init(void) {
    int reduced = g_slice.reduced_motion;
    memset(&g_slice, 0, sizeof g_slice);
    memset(&g_combat, 0, sizeof g_combat);
    memset(&g_player, 0, sizeof g_player);
    g_slice.reduced_motion = reduced;
    g_slice.hp = g_player.hp = 60;
    g_player.nunchi = 4;
    g_player.wlb = 4;
    g_rng = &night_rng;
    rng_init(g_rng, 317);
    ev_init();
    content_register_all();
    cards_init();
    /* An introductory deck with attacks, protection, information and recovery. */
    const uint32_t deck[] = {1,12,12,19,9,3,20,12,19,15};
    g_deck_n = 10;
    memcpy(g_deck, deck, sizeof deck);
}

static void enter(SliceScreen screen) {
    g_slice.screen = screen;
    g_slice.selected = 0;
    g_slice.notice = NULL;
}

static void battle(int boss) {
    ev_init();
    combat_start(boss ? 101 : 100);
    g_combat.player.hp = g_slice.hp;
    if (boss) {
        g_combat.enemy.hp = g_combat.enemy.maxhp = 100;
        /* Reading the attendance slip lets the worker challenge the accusation. */
        if (g_slice.clue && g_slice.selected == 1) {
            g_combat.enemy.hp = 76;
            apply_status(&g_combat.enemy, ST_WEAK, 1, 2);
        }
    }
    enter(boss ? SL_BOSS : SL_COPIER);
}

static void outcome(void) {
    /* Card damage is queued, so settle it before deciding the next screen. */
    ev_process_phase();
    if (g_combat.player.hp <= 0) g_combat.state = 2;
    else if (g_combat.enemy.hp <= 0) g_combat.state = 1;
    g_slice.hp = g_player.hp = g_combat.player.hp;
    if (g_combat.state == 2) enter(SL_DEFEAT);
    else if (g_combat.state == 1) {
        if (g_slice.screen == SL_BOSS) enter(SL_EXIT);
        else { g_slice.cleared = 1; enter(SL_REWARD); }
    }
    if (g_slice.selected >= g_combat.hand_n)
        g_slice.selected = g_combat.hand_n > 0 ? g_combat.hand_n-1 : 0;
}

void slice_input(SliceInput input) {
    if(input==SL_PAUSE) { g_slice.paused=!g_slice.paused;return; }
    if (input == SL_BACK) {
        if(g_slice.paused) {g_slice.paused=0;return;}
        if (g_slice.screen == SL_NOTE || g_slice.screen == SL_KIM ||
            g_slice.screen == SL_MANAGER) { enter(SL_OFFICE); return; }
        g_slice.paused = !g_slice.paused;
        return;
    }
    if (g_slice.paused) return;
    int count = 1;
    switch (g_slice.screen) {
        case SL_OFFICE: count = 4; break;
        case SL_MANAGER: count = g_slice.clue ? 2 : 1; break;
        case SL_REWARD: count = 3; break;
        case SL_COPIER: case SL_BOSS: count = g_combat.hand_n; break;
        default: break;
    }
    if (input == SL_LEFT || input == SL_UP || input == SL_RIGHT || input == SL_DOWN) {
        int delta = (input == SL_LEFT || input == SL_UP) ? -1 : 1;
        if (count > 0) g_slice.selected = (g_slice.selected+delta+count)%count;
        g_slice.notice = NULL;
        return;
    }
    if (g_slice.screen == SL_COPIER || g_slice.screen == SL_BOSS) {
        if (input == SL_END_TURN) {
            combat_end_turn();
            g_slice.notice = "새 턴 / 기력 회복";
        } else if (input == SL_CONFIRM && g_combat.hand_n > 0) {
            CardDef *card = card_by_id(g_combat.hand[g_slice.selected]);
            if (!card || card->cost > g_combat.player.energy) {
                g_slice.notice = "기력 부족 / SPACE 턴 종료";
                return;
            }
            combat_player_play((uint8_t)g_slice.selected, g_combat.enemy.id);
            g_slice.notice = "카드 사용";
        } else return;
        outcome();
        return;
    }
    if (input != SL_CONFIRM) return;
    switch (g_slice.screen) {
        case SL_TITLE: enter(SL_OFFICE); break;
        case SL_OFFICE:
            if (g_slice.selected == 0) {
                g_slice.clue = 1; g_player.nunchi = 6; enter(SL_NOTE);
            } else if (g_slice.selected == 1) {
                g_slice.talked = 1; enter(SL_KIM);
            } else if (g_slice.selected == 2) {
                if (!g_slice.talked) g_slice.notice = "먼저 김대리에게 말을 걸자.";
                else if (!g_slice.cleared) battle(0);
                else g_slice.notice = "복사기는 이제 조용하다.";
            } else if (!g_slice.cleared) g_slice.notice = "문이 잠겼다. 복사기에서 소리가 난다.";
            else enter(SL_MANAGER);
            break;
        case SL_NOTE: case SL_KIM: enter(SL_OFFICE); break;
        case SL_REWARD:
            if (g_deck_n < MAX_DECK) {
                g_slice.reward = (int)rewards[g_slice.selected];
                g_deck[g_deck_n++] = (uint32_t)g_slice.reward;
            }
            enter(SL_OFFICE);
            g_slice.selected = 3;
            break;
        case SL_MANAGER: battle(1); break;
        case SL_EXIT: case SL_DEFEAT: slice_init(); break;
        default: break;
    }
}

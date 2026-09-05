#include "game/slice.H"
#include "game/cards.H"
#include "render/ui_app.H"
#include "narrative/dsl.H"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void ev_dispatch(Event e) {slice_dispatch(e);}
void on_combat_start(const char *name) {(void)name;}
static int failures;
#define CHECK(c,s) do {if(!(c)){printf("FAIL %s\n",s);failures++;}else printf("PASS %s\n",s);}while(0)

static void press(SliceInput i) {slice_input(i);}
static void reach_copier(int clue) {
    slice_init();press(SL_CONFIRM);
    if(clue){press(SL_CONFIRM);press(SL_CONFIRM);}
    press(SL_RIGHT);press(SL_CONFIRM);press(SL_CONFIRM);
    press(SL_RIGHT);press(SL_RIGHT);press(SL_CONFIRM);
}

/* Play real affordable cards through the same input commands as the host. */
static void win_battle(void) {
    int steps=0;
    while((g_slice.screen==SL_COPIER||g_slice.screen==SL_BOSS)&&steps++<300) {
        int idx=-1;
        for(int i=0;i<g_combat.hand_n;i++) {
            CardDef *c=card_by_id(g_combat.hand[i]);
            if(c&&c->cost<=g_combat.player.energy){idx=i;break;}
        }
        if(idx<0)press(SL_END_TURN);
        else {
            for(int hops=0;g_slice.selected!=idx&&hops<MAX_HAND;hops++)press(SL_RIGHT);
            press(SL_CONFIRM);
        }
    }
    CHECK(steps<300,"combat terminates within input budget");
}

static int journey(int clue) {
    reach_copier(clue);
    CHECK(g_slice.screen==SL_COPIER,"office to coworker to copier");
    win_battle();
    CHECK(g_slice.screen==SL_REWARD,"copier victory offers reward");
    int deck=g_deck_n;
    press(SL_CONFIRM);
    CHECK(g_deck_n==deck+1&&g_slice.reward==10,"reward adds exactly one selected card");
    press(SL_CONFIRM);
    CHECK(g_slice.screen==SL_MANAGER&&g_deck_n==deck+1,"confirm cannot claim reward twice");
    if(clue)press(SL_RIGHT);
    press(SL_CONFIRM);
    CHECK(g_combat.enemy.hp==(clue?76:100),"observed attendance clue changes confrontation");
    win_battle();
    CHECK(g_slice.screen==SL_EXIT,"manager victory reaches clock-out ending");
    return g_slice.hp;
}

/* Gallery fixtures follow legal input paths, including carried health/deck. */
static void reach_screen(SliceScreen screen) {
    slice_init();
    if(screen==SL_TITLE)return;
    press(SL_CONFIRM);
    if(screen==SL_OFFICE)return;
    if(screen==SL_NOTE){press(SL_CONFIRM);return;}
    if(screen==SL_KIM){press(SL_RIGHT);press(SL_CONFIRM);return;}
    reach_copier(1);
    if(screen==SL_COPIER)return;
    if(screen==SL_DEFEAT) {
        for(int i=0;g_slice.screen==SL_COPIER&&i<100;i++)press(SL_END_TURN);
        return;
    }
    win_battle();
    if(screen==SL_REWARD)return;
    press(SL_CONFIRM);press(SL_CONFIRM);press(SL_RIGHT);
    if(screen==SL_MANAGER)return;
    press(SL_CONFIRM);
    if(screen==SL_BOSS)return;
    win_battle();
}

int main(void) {
    uia_init();
    int hp=journey(1);
    CHECK(journey(1)==hp,"same inputs reproduce final health");
    journey(0);
    reach_copier(0);
    press(SL_BACK);
    CombatState saved=g_combat;
    press(SL_CONFIRM);press(SL_END_TURN);press(SL_RIGHT);
    CHECK(memcmp(&saved,&g_combat,sizeof saved)==0,"pause blocks all gameplay actions");
    press(SL_BACK);
    g_combat.player.energy=0;
    /* Select a paid card, not a free coffee. */
    for(int i=0;i<g_combat.hand_n;i++)if(card_by_id(g_combat.hand[i])->cost>0){g_slice.selected=i;break;}
    saved=g_combat;press(SL_CONFIRM);
    CHECK(memcmp(&saved,&g_combat,sizeof saved)==0&&g_slice.notice,"unaffordable card leaves combat unchanged");
    int turns=0;
    while(g_slice.screen==SL_COPIER&&turns++<100)press(SL_END_TURN);
    CHECK(g_slice.screen==SL_DEFEAT,"passing turns can lose and reaches defeat");
    press(SL_CONFIRM);
    CHECK(g_slice.screen==SL_TITLE&&g_slice.hp==60&&g_deck_n==10&&!g_slice.clue&&!g_slice.reward,
          "retry resets deck, health, clue and reward");
    press(SL_CONFIRM);press(SL_LEFT);
    CHECK(g_slice.selected==3,"navigation wraps backwards");
    press(SL_CONFIRM);
    CHECK(g_slice.screen==SL_OFFICE&&g_slice.notice,"locked exit cannot skip encounter");
    press(SL_RIGHT);press(SL_CONFIRM);
    CHECK(g_slice.screen==SL_NOTE,"attendance record can still be inspected");
    press(SL_PAUSE);press(SL_BACK);
    CHECK(!g_slice.paused&&g_slice.screen==SL_NOTE,"back resumes a focus-paused dialogue without leaving it");
    press(SL_BACK);
    CHECK(g_slice.screen==SL_OFFICE,"back closes unpaused dialogue");

    /* Render each playable state and prove presentation does not mutate combat. */
    const struct {SliceScreen screen;const char *name;} screens[]={
        {SL_TITLE,"title"},{SL_OFFICE,"office"},{SL_NOTE,"attendance"},
        {SL_KIM,"coworker"},{SL_COPIER,"combat"},{SL_REWARD,"reward"},
        {SL_MANAGER,"response"},{SL_BOSS,"boss"},{SL_EXIT,"exit"},
        {SL_DEFEAT,"defeat"},{SL_OFFICE,"pause"}};
    static uint8_t rgb[RW*RH*3],again[RW*RH*3];
    reach_copier(1);
    g_slice.reduced_motion=1;
    slice_draw(0);ui_frame_rgb(rgb);
    slice_draw(7);ui_frame_rgb(again);
    CHECK(!memcmp(rgb,again,sizeof rgb),"reduced motion freezes presentation without advancing simulation");
    g_slice.reduced_motion=0;
    for(unsigned i=0;i<sizeof screens/sizeof screens[0];i++) {
        reach_screen(screens[i].screen);
        CHECK(g_slice.screen==screens[i].screen,"gallery state reached through gameplay inputs");
        if(!strcmp(screens[i].name,"pause"))press(SL_PAUSE);
        saved=g_combat;Slice before=g_slice;
        PlayerStats player_before=g_player;
        RNG rng_before=*g_rng;
        slice_draw(.25);ui_frame_rgb(rgb);
        slice_draw(.25);ui_frame_rgb(again);
        CHECK(memcmp(rgb,again,sizeof rgb)==0,"same state and time produce identical pixels");
        CHECK(memcmp(&saved,&g_combat,sizeof saved)==0&&memcmp(&before,&g_slice,sizeof before)==0&&
              memcmp(&player_before,&g_player,sizeof player_before)==0&&
              memcmp(&rng_before,g_rng,sizeof rng_before)==0,
              "drawing never mutates gameplay");
        char path[100];snprintf(path,sizeof path,"/tmp/clockout-slice-%s.ppm",screens[i].name);
        uia_present(path);
        FILE *f=fopen(path,"rb");
        if(f){char header[64];for(int h=0;h<3;h++)fgets(header,sizeof header,f);
            size_t n=fread(again,1,sizeof again,f);fclose(f);
            CHECK(n==sizeof again&&!memcmp(rgb,again,sizeof rgb),"host RGB equals screenshot compositor");
        }else CHECK(0,"capture opens");
    }
    reach_copier(1);
    g_combat.hand_n=MAX_HAND;
    for(int i=0;i<MAX_HAND;i++)g_combat.hand[i]=20;
    g_slice.selected=MAX_HAND-1;
    slice_draw(0);ui_frame_rgb(rgb);
    uia_present("/tmp/clockout-slice-full-hand.ppm");
    g_combat.hand_n=0;g_slice.selected=0;
    slice_draw(0);ui_frame_rgb(again);
    CHECK(memcmp(rgb,again,sizeof rgb)!=0,"full and empty hands both render safely");
    rndr_begin();ui_begin();
    ui_pixel(0,0,200,100,50,128);
    ui_pixel(1,0,7,8,9,255);
    ui_frame_rgb(rgb);
    CHECK(rgb[0]==104&&rgb[1]==58&&rgb[2]==39,"host RGB blends premultiplied alpha only once");
    CHECK(rgb[3]==7&&rgb[4]==8&&rgb[5]==9,"opaque overlay replaces the scene");
    CHECK(rgb[6]==10&&rgb[7]==18&&rgb[8]==30,"transparent overlay preserves the scene");
    printf("slice: %d failures\n",failures);
    return failures?1:0;
}

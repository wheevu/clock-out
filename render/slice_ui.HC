/* Fixed-camera night shift. The UI reads state; only slice_input changes it. */
#include "ui_app.H"
#include "../game/slice.H"
#include "../game/cards.H"
#include <string.h>

#define PAPER 221,218,198
#define MUTED 135,154,152
#define GOLD 199,171,108
#define INK 13,21,26
#define RED 191,81,64
#define TEAL 115,182,166

const char *card_name(uint32_t id);

static void panel(int x,int y,int w,int h) {
    ui_fill_rect(x+3,y+3,w,h,0,0,0,95);
    ui_fill_rect(x,y,w,h,INK,244);
    ui_draw_rect(x,y,w,h,63,79,78,255);
}

static void text(int x,int y,const char *s) { ui_text_scaled(x,y,s,2,PAPER); }

/* Crop transparent frame padding before scaling; feet share a ground anchor. */
static void actor(const char *key,int cx,int feet,int scale,double t) {
    UISprite *s = ui_sprite(key);
    if (!s || !s->rgba) return;
    int x0=s->w,y0=s->h,x1=-1,y1=-1;
    for(int y=0;y<s->h;y++) for(int x=0;x<s->w;x++)
        if(s->rgba[(y*s->w+x)*4+3]) {
            if(x<x0)x0=x; if(x>x1)x1=x;
            if(y<y0)y0=y; if(y>y1)y1=y;
        }
    if(x1<x0)return;
    int w=(x1-x0+1)*scale;
    int anchor_x=(x0+x1+1)/2,anchor_y=y1+1;
    char frame[48];
    snprintf(frame,sizeof frame,"idle_%s_%d",key+5,(int)(t*2)%4);
    UISprite *animated=ui_sprite(frame);
    if(animated&&animated->rgba)s=animated;
    ui_fill_rect(cx-w/2,feet-2,w,4,0,0,0,85);
    for(int y=0;y<s->h;y++) for(int x=0;x<s->w;x++) {
        const uint8_t *p=s->rgba+(y*s->w+x)*4;
        if(p[3]) ui_fill_rect(cx+(x-anchor_x)*scale,feet+(y-anchor_y)*scale,
                             scale,scale,p[0]*4/5,p[1]*4/5,p[2]*4/5,p[3]);
    }
}

static void arena_box(Vec3 p,Vec3 size,int hue,int step) {
    Mesh m=mesh_box(p,size,RNDR_COL(hue,step));rndr_draw(m);mesh_free(&m);
}

static void arena(int boss) {
    rndr_begin();
    rndr_set_camera((Vec3){0,2.4,7},(Vec3){0,1,-1});
    arena_box((Vec3){0,-.06,0},(Vec3){16,.1,16},HUE_SLATE,4);
    arena_box((Vec3){0,2,-3.2},(Vec3){16,4,.1},HUE_SLATE,3);
    arena_box((Vec3){0,3.4,0},(Vec3){16,.08,16},HUE_SLATE,2);
    for(int side=-1;side<=1;side+=2)
        arena_box((Vec3){side*2.2,3.3,-.5},(Vec3){1.4,.04,.18},HUE_WHITE,12);
    for(int z=-3;z<7;z++)
        arena_box((Vec3){0,0,z},(Vec3){16,.01,.012},HUE_SLATE,3);
    for(int x=-7;x<=7;x++)
        arena_box((Vec3){x,0,0},(Vec3){.012,.01,16},HUE_SLATE,3);
    for(int x=-4;x<=4;x+=2) {
        arena_box((Vec3){x,1.9,-3.1},(Vec3){1.4,1.3,.02},HUE_INK,2);
        arena_box((Vec3){x,1.9,-3.05},(Vec3){.025,1.3,.03},HUE_SLATE,8);
        arena_box((Vec3){x,1.9,-3.05},(Vec3){1.4,.025,.03},HUE_SLATE,8);
    }
    /* A meeting table stays behind the combatants, not across their feet. */
    arena_box((Vec3){0,.75,-2},(Vec3){4,.09,.7},HUE_TAN,8);
    for(int side=-1;side<=1;side+=2)
        arena_box((Vec3){side*1.8,.36,-2},(Vec3){.08,.72,.55},HUE_CHARCOAL,6);
    if(boss) {
        arena_box((Vec3){0,1.4,-3.04},(Vec3){.5,.7,.02},HUE_VERMILION,7);
    }
}

static void copier(int x,int y) {
    ui_fill_rect(x-30,y-3,68,5,0,0,0,100);
    ui_fill_rect(x-26,y-53,52,51,126,139,133,255);
    ui_fill_rect(x+18,y-48,12,46,65,82,82,255);
    ui_fill_rect(x-29,y-63,58,10,181,184,161,255);
    ui_fill_rect(x-21,y-60,39,3,INK,255);
    ui_fill_rect(x-20,y-43,25,9,INK,255);
    ui_fill_rect(x+10,y-45,8,4,TEAL,255);
    for(int i=0;i<3;i++) {
        ui_fill_rect(x-21,y-28+i*8,36,1,66,83,81,255);
        ui_fill_rect(x-5,y-25+i*8,8,2,66,83,81,255);
    }
    ui_fill_rect(x-17,y-41,18,6,PAPER,255);
}

static void footer(const char *s) {
    ui_fill_rect(0,336,RW,24,INK,255);
    ui_text(20,344,s,MUTED);
}

static void dialogue(const char *name,const char *a,const char *b,const char *c) {
    panel(24,226,592,104);
    ui_fill_rect(24,226,3,104,GOLD,255);
    ui_text(40,236,name,GOLD);
    text(40,253,a); text(40,275,b); text(40,297,c);
}

static const char *rule(uint32_t id) {
    switch(id) {
        case 1:return "턴 종료 시 의자 충돌 피해";
        case 3:return "의도 공개 / 적 공격 2턴 약화";
        case 9:return "기력 1 회복";
        case 10:return "피해 25";
        case 12:return "피해 6 / 방어 6";
        case 15:return "체력 6 회복";
        case 19:return "방어 8 / 다음 턴에 사라짐";
        case 20:return "피해 8 / 카드 1장 뽑기";
        default:return "";
    }
}

/* Small card illustrations: a broken terminal, a backup file, a release arrow. */
static void reward_art(int x,int y,uint32_t id) {
    ui_draw_rect(x,y,72,38,63,79,78,255);
    ui_fill_rect(x+1,y+1,70,7,63,79,78,255);
    if(id==10) {
        ui_fill_rect(x+10,y+17,26,2,RED,255);
        ui_fill_rect(x+10,y+23,42,2,RED,255);
        ui_fill_rect(x+42,y+14,6,13,INK,255);
        ui_text(x+10,y+29,"0x0317",MUTED);
    } else if(id==15) {
        ui_draw_rect(x+15,y+13,26,20,TEAL,255);
        ui_draw_rect(x+22,y+17,26,20,PAPER,255);
        ui_fill_rect(x+29,y+24,12,1,TEAL,255);
        ui_fill_rect(x+29,y+28,12,1,TEAL,255);
    } else {
        ui_fill_rect(x+14,y+24,34,3,GOLD,255);
        for(int i=0;i<9;i++)ui_fill_rect(x+48-i,y+17+i,1,17-2*i,GOLD,255);
        ui_fill_rect(x+12,y+18,2,15,MUTED,255);
    }
}

static void battle_ui(double t) {
    int boss=g_slice.screen==SL_BOSS;
    arena(boss);
    ui_begin();
    ui_fill_rect(0,0,RW,60,INK,238);
    ui_text(20,12,boss?"04F / PERFORMANCE REVIEW":"04F / PAPER JAM",GOLD);
    text(20,30,boss?"박과장":"복사기");
    char buf[100];
    snprintf(buf,sizeof buf,"%d / %d",g_combat.enemy.hp,g_combat.enemy.maxhp);
    ui_text(480,17,buf,PAPER);
    ui_bar(170,35,446,7,(double)g_combat.enemy.hp/g_combat.enemy.maxhp,RED,255);
    const char *intent="??? / 눈치 보기";
    char attack[48];
    if(uia_intent_revealed()) {
        switch(g_combat.enemy_intent_type) {
            case COMBAT_INTENT_ATTACK: {
                int damage=g_combat.enemy_intent_value;
                if(g_combat.enemy.statuses[ST_WEAK-1])damage=damage*75/100;
                if(g_combat.player.statuses[ST_VULN-1])damage=damage*150/100;
                snprintf(attack,sizeof attack,"공격 %d",damage);
                intent=attack;break;
            }
            case COMBAT_INTENT_BLOCK:intent="방어 8";break;
            case COMBAT_INTENT_PRESSURE:intent="압박 / 공격 약화";break;
            case COMBAT_INTENT_GLITCH:intent="오류 / 지속 피해 3";break;
        }
    }
    panel(360,70,256,48);
    ui_text(374,78,"NEXT / 다음 행동",GOLD);
    text(374,94,intent);
    if(g_combat.enemy.block) {
        snprintf(buf,sizeof buf,"방어 %d",g_combat.enemy.block);
        ui_text(374,124,buf,TEAL);
    }
    actor("char_player",158,224,2,t);
    if(boss)actor("char_boss",480,218,3,t);else copier(480,218);
    panel(20,70,246,50);
    snprintf(buf,sizeof buf,"HP %d   방어 %d",g_combat.player.hp,g_combat.player.block);
    text(32,79,buf);
    snprintf(buf,sizeof buf,"ENERGY %d   TURN %d",g_combat.player.energy,g_combat.turn);
    ui_text(32,103,buf,GOLD);
    if(g_combat.player.statuses[ST_WEAK-1])ui_text(32,130,"약화 / 내 공격 -25%",RED);
    if(g_combat.player.statuses[ST_HAZARD-1]) {
        snprintf(buf,sizeof buf,"오류 / 다음 턴 체력 -%d",g_combat.player.statuses[ST_HAZARD-1]);
        ui_text(32,145,buf,RED);
    }
    ui_fill_rect(0,231,RW,105,INK,250);
    int n=g_combat.hand_n;
    UiaHandLayout l=uia_hand_layout(n);
    for(int pass=0;pass<2;pass++)for(int i=0;i<n;i++) {
        int sel=i==g_slice.selected;
        if((pass==0&&sel)||(pass==1&&!sel))continue;
        uint32_t id=g_combat.hand[i];
        CardDef *card=card_by_id(id);
        int x=l.x0+i*l.stride,y=240-(sel?8:0);
        panel(x,y,l.card_w,58);
        if(sel)ui_draw_rect(x,y,l.card_w,58,GOLD,255);
        snprintf(buf,sizeof buf,"%d",card?card->cost:0);
        ui_text(x+8,y+7,buf,TEAL);
        if(l.card_w>=104)text(x+8,y+30,card_name(id));
        else ui_text(x+8,y+30,card_name(id),PAPER);
        ui_fill_rect(x+8,y+21,l.card_w-16,1,48,65,63,255);
        if(card&&card->cost>g_combat.player.energy)ui_text(x+l.card_w-15,y+7,"X",RED);
    }
    if(n>0) {
        uint32_t id=g_combat.hand[g_slice.selected];
        text(20,310,rule(id));
    } else text(20,310,"손에 카드가 없다. 턴을 마치자.");
    if(g_slice.notice)ui_text(284,139,g_slice.notice,GOLD);
    footer("A/D 선택  ENTER/A 사용  SPACE/Y 턴 종료  ESC/B 뒤로");
}

void slice_draw(double t) {
    if(g_slice.reduced_motion || g_slice.paused)t=0;
    if(g_slice.screen==SL_COPIER || g_slice.screen==SL_BOSS) battle_ui(t);
    else {
        uia_scene_office(t); ui_begin();
        if(g_slice.screen==SL_TITLE) {
            ui_fill_rect(0,0,310,RH,INK,210);
            ui_text(30,35,"SEONGWANG / AFTER HOURS",MUTED);
            ui_text_scaled(26,83,"퇴근",10,PAPER);
            ui_text(30,184,"C L O C K   O U T",GOLD);
            ui_fill_rect(30,211,220,1,GOLD,255);
            text(30,235,"03:17 AM");
            text(30,261,"아직 사무실이다.");
            text(30,302,"> ENTER  시작");
            footer("ENTER / A 시작    F11 전체 화면    F2 화면 효과 끄기");
        } else if(g_slice.screen==SL_EXIT || g_slice.screen==SL_DEFEAT) {
            ui_fill_rect(0,0,RW,RH,INK,235);
            ui_text(40,45,"ATTENDANCE / 04F",MUTED);
            ui_text_scaled(40,105,g_slice.screen==SL_EXIT?"퇴근":"미퇴근",6,PAPER);
            text(40,187,g_slice.screen==SL_EXIT?"03:18. 시계가 움직였다.":"03:17. 다시 같은 자리다.");
            text(40,219,g_slice.screen==SL_EXIT?"아무도 따라 나오지 않았다.":"이번에는 내일로 넘기지 말자.");
            footer("ENTER / A 처음부터    ESC 일시정지");
        } else if(g_slice.screen==SL_REWARD) {
            ui_fill_rect(0,0,RW,RH,INK,195);
            ui_text(24,24,"PAPER JAM / CLEARED",TEAL);
            text(24,49,"내 이름이 적힌 서류가 나왔다.");
            const uint32_t ids[]={10,15,20};
            for(int i=0;i<3;i++) {
                int x=24+i*204;
                panel(x,103,184,147);
                if(i==g_slice.selected)ui_draw_rect(x,103,184,147,GOLD,255);
                text(x+12,121,card_name(ids[i]));
                reward_art(x+55,156,ids[i]);
                ui_text(x+12,207,rule(ids[i]),MUTED);
                CardDef *c=card_by_id(ids[i]);char cost[32];
                snprintf(cost,sizeof cost,"ENERGY %d",c->cost);
                ui_text(x+12,223,cost,TEAL);
            }
            text(24,279,"한 장을 챙긴다. 문 쪽에서 발소리.");
            footer("A/D 선택    ENTER / A 덱에 추가");
        } else {
            ui_fill_rect(0,0,RW,43,INK,232);
            ui_text(20,12,"04F / 개발1팀",PAPER);
            ui_text(430,12,"03:17 / 야간 근무",GOLD);
            actor("char_player",315,277,2,t);
            actor("char_kim",292,220,1,t);
            copier(546,284);
            if(g_slice.screen==SL_NOTE) {
                dialogue("출퇴근 기록 / 눈치 +2","박과장  18:02 퇴근.","그런데 출입문 안쪽에 구두가 보인다.","문은 밖에서 잠긴 게 아니다.");
            } else if(g_slice.screen==SL_KIM) {
                dialogue("김대리","복사기 좀 봐줘. 계속 네 이름만 나와.","문은 내가 확인했어. 안 열려.","의자라도 써. 비품은 내일 생각하고.");
            } else if(g_slice.screen==SL_MANAGER) {
                dialogue("박과장","먼저 가면 나머지는 누가 합니까?","> 내 일은 끝났습니다.",g_slice.clue?"> 과장님은 여섯 시에 퇴근하셨네요.":"출퇴근 기록을 확인했어야 했다.");
                ui_draw_rect(34,272+g_slice.selected*22,565,20,GOLD,255);
            } else {
                static const char *names[]={"출퇴근 기록","김대리","복사기","출입문"};
                static const int anchors[4][2]={{179,228},{292,174},{546,210},{320,145}};
                int ax=anchors[g_slice.selected][0],ay=anchors[g_slice.selected][1];
                ui_draw_rect(ax-6,ay-6,12,12,GOLD,255);
                ui_fill_rect(ax-1,ay-1,2,2,PAPER,255);
                for(int i=0;i<4;i++) {
                    int x=20+i*153;
                    panel(x,292,141,33);
                    if(i==g_slice.selected)ui_draw_rect(x,292,141,33,GOLD,255);
                    text(x+7,301,names[i]);
                }
                if(g_slice.notice) {
                    panel(20,246,600,33);text(30,254,g_slice.notice);
                } else {
                    ui_text(20,54,g_slice.cleared?"목표 / 출입문으로":
                        g_slice.talked?"목표 / 복사기 조사":"목표 / 김대리와 이야기하기",GOLD);
                }
            }
            footer("방향키 / D-PAD 선택    ENTER / A 조사    ESC / B 뒤로");
        }
    }
    if(g_slice.paused) {
        ui_fill_rect(0,0,RW,RH,0,0,0,165);
        panel(128,94,384,172);
        text(154,117,"잠깐 쉬자.");
        text(154,157,"ESC / B 계속");
        ui_text(154,193,"F2 화면 효과 켜기/끄기",MUTED);
        ui_text(154,217,"F11 전체 화면  /  창 닫기 종료",MUTED);
    }
}

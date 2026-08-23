/* content/cards.c -- registers the 성광정보기술 card set via card_register().
 *
 * EffectOpT param conventions used throughout this file:
 *   OP_DAMAGE       a = damage amount
 *   OP_BLOCK        a = block amount
 *   OP_DRAW         a = draw count
 *   OP_ENERGY       a = energy gain (can be negative)
 *   OP_HEAL         a = heal amount
 *   OP_STATUS       a = status id (ST_*), b = stacks, ref = target (0 self, 1 foe)
 *   OP_SPAWN        a = body type (BODY_*), b = count
 *   OP_FORCE        a = magnitude, b = dir (0 forward, 1 random, 2 up)
 *   OP_GRAVITY      a = gravity vector code (1 = flip down)
 *   OP_STAT         a = stat id (STAT_*), b = delta
 *   OP_STATUS ST_REVEAL  is used to reveal intent (no OP_REVEAL_INTENT opcode
 *                        exists in contracts.h)
 *   OP_END_CAMPAIGN a = 0
 *
 * card_register / card_by_id are implemented by the narrative/registry
 * module and declared in contracts.h. They are NOT defined here. */

#include "../include/contracts.HC"
#include "strings.HC"
#include <string.h>

/* ---- local encoding enums (see conventions above) ---- */
/* body shapes MUST match physics/phys.h: PHYS_SHAPE_SPHERE=0, PHYS_SHAPE_AABB=1 */
enum { BODY_SPHERE = 0, BODY_BOX = 1, BODY_CUP = 0, BODY_CHAIR = 0 };
enum { STAT_HP = 1, STAT_NUNCHI = 2, STAT_STRESS = 3 };

/* ---- string tables, indexed by card id (1..N) ---- */
#define MAX_CARDS 64
static const char *g_name[MAX_CARDS];
static const char *g_text[MAX_CARDS];
static const char *g_flavor[MAX_CARDS];

/* ---- single-shot registration helper ---- */
static void reg(uint32_t id, uint8_t type, uint8_t rarity, uint8_t cost,
                uint8_t arch, uint8_t exh, uint8_t retain, uint8_t nfx,
                EffectOpT fx[4], const char *name, const char *text,
                const char *flavor) {
  CardDef d;
  d.id = id;
  d.type = type;
  d.rarity = rarity;
  d.cost = cost;
  d.archetype = arch;
  d.name_id = (uint16_t)id;
  d.text_id = (uint16_t)id;
  d.flavor_id = (uint16_t)id;
  d.upgrade_of = 0;
  d.exhaust = exh;
  d.retain = retain;
  d.nfx = nfx;
  for (int i = 0; i < 4; i++) d.fx[i] = fx[i];
  g_name[id] = name;
  g_text[id] = text;
  g_flavor[id] = flavor;
  card_register(d);
}

void content_register_all(void) {
  EffectOpT z = {0, 0, 0, 0};

  /* 1 의자 투척 -- throw a chair (sphere) forward */
  {
    EffectOpT fx[4] = {{OP_SPAWN, BODY_SPHERE, 1, 0},
                       {OP_FORCE, 20, 0, 0}, z, z};
    reg(1, C_ATTACK, 1, 1, A_PHYS, 0, 0, 2, fx,
        "의자 투척",
        "구형 물체를 전방으로 힘껏投掷한다. 피해 대신 충돌 물리에 의존.",
        "회의실 의자는 생각보다 단단하다.");
  }

  /* 2 야근 -- overtime: lose hp, gain energy, spawn a cup */
  {
    EffectOpT fx[4] = {{OP_STAT, STAT_HP, -3, 0},
                       {OP_ENERGY, 2, 0, 0},
                       {OP_SPAWN, BODY_CUP, 1, 0}, z};
    reg(2, C_SYSTEM, 1, 1, A_OVERWORK, 0, 0, 3, fx,
        "야근",
        "체력 3 감소. 에너지 2 증가. 빈 커피컵 하나가 생성된다.",
        "퇴근은 언제쯤일까.");
  }

  /* 3 코드 리뷰 -- reveal + weaken the enemy's next intent */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_REVEAL, 1, 1},
                       {OP_STATUS, ST_WEAK, 1, 1}, z, z};
    reg(3, C_TECH, 1, 1, A_SYSTEM, 0, 0, 2, fx,
        "코드 리뷰",
        "적의 다음 의도를 드러내고(ST_REVEAL), 그 의도를 약화시킨다(ST_WEAK).",
        "한 줄 한 줄, 눈길이 머문다.");
  }

  /* 4 눈치 보기 -- read the room: reveal intent (gated on nunchi at runtime)
   * NOTE: contracts.h has no OP_REVEAL_INTENT opcode; the available primitive
   * that reveals the enemy's intent is OP_STATUS ST_REVEAL. The nunchi>=6 gate
   * is a runtime guard the combat layer applies (encoded here as intent, not
   * in EffectOpT which has no condition slot). */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_REVEAL, 1, 1}, z, z, z};
    reg(4, C_SOCIAL, 1, 0, A_SOCIAL, 0, 0, 1, fx,
        "눈치 보기",
        "상대의 의도를 엿본다(ST_REVEAL). 눈치(nunchi)가 6 이상이면 확실히 읽힌다.",
        "분위기, 그 건조한 공기.");
  }

  /* 5 책임 전가 -- shift the blame onto the foe */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_BLAME, 1, 1}, z, z, z};
    reg(5, C_SOCIAL, 1, 1, A_SOCIAL, 0, 0, 1, fx,
        "책임 전가",
        "적에게 비난(ST_BLAME)을 전가한다. 다음 피해 판정이 비뀐다.",
        "\"그건 제가 한 게 아닙니다.\"");
  }

  /* 6 퇴근 -- clock out: end the campaign */
  {
    EffectOpT fx[4] = {{OP_END_CAMPAIGN, 0, 0, 0}, z, z, z};
    reg(6, C_SPECIAL, 2, 2, A_SYSTEM, 1, 0, 1, fx,
        "퇴근",
        "조건이 맞으면 캠페인을 종료한다(퇴근 성공). 소모.",
        "마침내 문을 연다.");
  }

  /* 7 메모리 누수 -- self DoT + energy cap */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_LEAK, 1, 0},
                       {OP_STATUS, ST_ENERGYCAP, 1, 0}, z, z};
    reg(7, C_SYSTEM, 1, 1, A_SYSTEM, 0, 0, 2, fx,
        "메모리 누수",
        "자신에게 메모리 누수(ST_LEAK, 매 턴 피해)와 에너지 상한(ST_ENERGYCAP)을 건다.",
        "free()를 잊었다.");
  }

  /* 8 사직서 -- resignation: end the campaign */
  {
    EffectOpT fx[4] = {{OP_END_CAMPAIGN, 0, 0, 0}, z, z, z};
    reg(8, C_SPECIAL, 2, 1, A_SYSTEM, 1, 0, 1, fx,
        "사직서",
        "캠페인을 종료한다(사직). 소모.",
        "더 이상 this company는 아니다.");
  }

  /* 9 커피 -- energy */
  {
    EffectOpT fx[4] = {{OP_ENERGY, 1, 0, 0}, z, z, z};
    reg(9, C_SYSTEM, 1, 0, A_OVERWORK, 0, 0, 1, fx,
        "커피",
        "에너지 1 증가.",
        "각성제, 혹은 마약.");
  }

  /* 10 세그폴트 -- big damage */
  {
    EffectOpT fx[4] = {{OP_DAMAGE, 25, 0, 0}, z, z, z};
    reg(10, C_ATTACK, 2, 2, A_SYSTEM, 0, 0, 1, fx,
        "세그폴트",
        "거대한 피해 25를 입힌다.",
        "Segmentation fault (core dumped).");
  }

  /* 11 회의 -- weaken the enemy */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_WEAK, 1, 1}, z, z, z};
    reg(11, C_SOCIAL, 1, 1, A_SOCIAL, 0, 0, 1, fx,
        "회의",
        "적에게 약화(ST_WEAK)를 건다. 적의 공격이 줄어든다.",
        "회의는 또 회의를 낳는다.");
  }

  /* 12 월요일 -- damage + block */
  {
    EffectOpT fx[4] = {{OP_DAMAGE, 6, 0, 0},
                       {OP_BLOCK, 6, 0, 0}, z, z};
    reg(12, C_ATTACK, 1, 1, A_DEFENSE, 0, 0, 2, fx,
        "월요일",
        "피해 6, 방어 6. 시작부터 긴 하루.",
        "그 누구도 원하지 않는 아침.");
  }

  /* 13 리팩터링 -- draw */
  {
    EffectOpT fx[4] = {{OP_DRAW, 2, 0, 0}, z, z, z};
    reg(13, C_TECH, 1, 1, A_SYSTEM, 0, 0, 1, fx,
        "리팩터링",
        "카드 2장을 뽑는다.",
        "동작은 같고, 마음은 가볍다.");
  }

  /* 14 디버그 -- reveal intent (ST_REVEAL; contracts.h has no OP_REVEAL_INTENT) */
  {
    EffectOpT fx[4] = {{OP_STATUS, ST_REVEAL, 1, 1}, z, z, z};
    reg(14, C_TECH, 1, 0, A_SYSTEM, 0, 0, 1, fx,
        "디버그",
        "적의 의도를 드러낸다(ST_REVEAL).",
        "breakpoint hit.");
  }

  /* 15 백업 -- heal */
  {
    EffectOpT fx[4] = {{OP_HEAL, 6, 0, 0}, z, z, z};
    reg(15, C_DEFEND, 1, 1, A_SYSTEM, 0, 0, 1, fx,
        "백업",
        "체력 6 회복.",
        "모두 안전한 곳에 복사해 두었다.");
  }

  /* 16 책상 뒤집기 -- spawn AABB + force forward */
  {
    EffectOpT fx[4] = {{OP_SPAWN, BODY_BOX, 1, 0},
                       {OP_FORCE, 10, 0, 0}, z, z};
    reg(16, C_ATTACK, 2, 2, A_PHYS, 0, 0, 2, fx,
        "책상 뒤집기",
        "상자(AABB)를 생성하고 전방으로 밀어낸다.",
        "책상 하나가 하늘로 갔다.");
  }

  /* 17 중력 오류 -- gravity flip */
  {
    EffectOpT fx[4] = {{OP_GRAVITY, 1, 0, 0}, z, z, z};
    reg(17, C_SPECIAL, 1, 1, A_SYSTEM, 0, 0, 1, fx,
        "중력 오류",
        "중력 벡터를 뒤집는다. 모든 물리가 뒤집힌다.",
        "위는 아래고, 아래는 위다.");
  }

  /* 18 커널 패닉 -- spawn several + random force */
  {
    EffectOpT fx[4] = {{OP_SPAWN, BODY_SPHERE, 4, 0},
                       {OP_FORCE, 6, 1, 0}, z, z};
    reg(18, C_ATTACK, 2, 3, A_SYSTEM, 0, 0, 2, fx,
        "커널 패닉",
        "구형 물체 4개를 생성하고 무작위 방향으로 힘을 가한다.",
        "not syncing.");
  }

  /* 19 정리정돈 -- block (modeled from kinetic energy) */
  {
    EffectOpT fx[4] = {{OP_BLOCK, 8, 0, 0}, z, z, z};
    reg(19, C_DEFEND, 1, 1, A_DEFENSE, 0, 0, 1, fx,
        "정리정돈",
        "운동에너지를 방어로 전환한다(방어 8).",
        "책상 위는 언제나 깔끔하게.");
  }

  /* 20 긴급 배포 -- damage + draw */
  {
    EffectOpT fx[4] = {{OP_DAMAGE, 8, 0, 0},
                       {OP_DRAW, 1, 0, 0}, z, z};
    reg(20, C_ATTACK, 1, 1, A_SYSTEM, 0, 0, 2, fx,
        "긴급 배포",
        "피해 8, 카드 1장 뽑기. 검증은 나중에.",
        "deploy --force.");
  }
}

/* ---- name -> id map ---- */
uint32_t card_id_by_name(const char *name) {
  for (uint32_t id = 1; id < MAX_CARDS; id++) {
    if (g_name[id] && strcmp(g_name[id], name) == 0) return id;
  }
  return 0;
}

const char *card_name(uint32_t id) {
  return (id < MAX_CARDS) ? g_name[id] : NULL;
}
const char *card_text(uint32_t id) {
  return (id < MAX_CARDS) ? g_text[id] : NULL;
}
const char *card_flavor(uint32_t id) {
  return (id < MAX_CARDS) ? g_flavor[id] : NULL;
}

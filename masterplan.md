# 성광정보기술 (Sungwang Information Technology)
## A Korean 3D Deckbuilding Office RPG, built from scratch in HolyC for TempleOS

### Master Plan / Technical & Game-Design Document

> Audience: one experienced systems programmer who will build this incrementally.
> Goal: a coherent, debuggable, finishable game, not a pile of engine experiments.
> Status: historical pre-implementation design record.
> For current behavior and resolution, use `GUIDE.md` and the source.
> The 320×240 targets below describe the original plan.

---

## 1. Executive summary

성광정보기술 is a turn-based deckbuilding RPG with a custom software 3D renderer, a
minimal rigid-body physics engine, a custom Hangul text + IME stack, deterministic
replay, a dialogue/campaign DSL, an office-politics simulation, and a narrative
campaign about a junior engineer who cannot leave work.

The fantasy: you are a 사원 (junior) at 성광정보기술. You wake at 3:17 AM. Everyone is
gone. The building is now spatially impossible. Workplace structures become literal
RPG systems and monsters. The joke is recognizable Korean office life; the dread is
that the company may be the operating environment itself.

Every "technology" on the list is load-bearing:

- The **software renderer** is the world the player walks through, and its glitches
  become supernatural events and a late-game mystery.
- **Physics** is not a sandbox; it is the delivery mechanism for physical card
  combat (throw a chair, flip a desk, rewrite gravity).
- **Hangul rendering** has a deliberate flaw that becomes a character whose name
  cannot be rendered — a real plot clue.
- **Deterministic replay** is, in-world, the employee-surveillance / 업무 기록 system.
- The **DSL** keeps 90% of content out of engine code so one person can write a whole
  campaign without recompiling.
- **Office politics** (blame, credit, 눈치, 직급) are the social-combat layer that
  runs parallel to HP combat.

The plan is scoped so a single developer can reach a vertical slice in a sane number
of phases, then expand content without rewriting systems.

---

## 2. Design pillars

1. **Systems serve the joke, the joke serves the dread.** Absurd corporate mechanics
   are real mechanics. The absurdity is the surface; the loneliness/burnout is the
   core.
2. **Determinism everywhere.** Every random number, physics step, AI choice, and
   event is reproducible. This makes debugging possible in TempleOS and becomes a
   story beat.
3. **Small, dense, readable.** Tiny internal resolution, tiny levels, tiny fonts,
   tiny textures. Crunch is aesthetic and pragmatic.
4. **Content is data, not code.** The campaign is written in a DSL interpreted by the
   engine. Adding a scene never requires recompiling the renderer.
5. **One coherent loop.** Explore → talk → schedule → fight (cards+physics) →
   change the world → save. Every system feeds this loop.
6. **Korean-first.** Text, input, culture, and comedy are native, not translated.
   Satire targets structures, not people.

---

## 3. What makes the project unique

- A from-scratch HolyC engine (renderer + physics + Hangul + IME + DSL + replay) that
  is genuinely a single playable game, not a tech demo collection.
- Combat where the *physical set pieces* are weapons: chairs, desks, coffee, gravity
  errors, kernel panics. Physics is deterministic and turn-quantized so it stays
  replayable.
- A "social combat" layer (눈치, 직급, 압박, blame/credit) that coexists with HP
  combat and occasionally replaces it (회식).
- Metafiction delivered through mechanics: replay = surveillance, Hangul corruption =
  a missing person, rendering artifacts = the boundary of the "company OS."
- Cultural specificity: the comedy is about 건물, not about Koreans. 눈치 is a real
  readable mechanic.

---

## 4. Scope boundaries

In scope:
- Single-player, offline, single-threaded.
- One building, ~10–14 floors, most small and dense.
- ~15–20 cards for vertical slice; ~120–180 cards for full game.
- 4 acts, multiple endings, ~12 named NPCs with relationship graphs.
- CPU software renderer at 320×240 internal (scaled to 640×480 or 1280×720).
- Rigid bodies capped at ~64 active in any scene.
- DSL-driven campaign content.
- Save/load, replay, debug tooling.

Out of scope (explicitly, see §52):
- Networking, multiplayer, cloud saves.
- Modern PBR, skeletal animation, GI, post-processing stacks.
- General Unicode; we implement only Hangul + ASCII + a handful of punctuation.
- Convex-hull / arbitrary-mesh physics; only plane/sphere/AABB at first.
- Audio synthesis beyond simple square/noise blips and short PCM samples.
- Multithreading, ECS frameworks, scripting languages beyond the tiny DSL.

---

## 5. Player fantasy

"I am trapped in my office and the office is becoming a dungeon. I will survive by
being technically competent, socially aware, and occasionally throwing a chair at my
manager. I will decide whether to escape, defeat, own, or resign from the company
that is also my operating system."

Two simultaneous power fantasies:
- **Competence:** build a clever deck, exploit physics, out-think enemies.
- **Agency over anxiety:** the game lets you finally say 사직서, or finally go home.

---

## 6. Core gameplay loop

Per "session" (one sit-down at the machine):

1. **Load / boot** → restore campaign state or start new (seeded).
2. **Explore** a floor: walk 3D rooms, read posters/monitors, inspect desks.
3. **Encounter**: dialogue, messenger ping, or combat trigger.
4. **Resolve**: talk (choices affect world), fight (cards + physics), or flee.
5. **Loot/change**: card reward, stat gain, relationship shift, flag set.
6. **Schedule**: advance time; choose evening activity; queue future events.
7. **Save** (automatic at safe points + manual).
8. Repeat; occasional **boss** and **act transition**.

The loop is always: *perceive (눈치) → decide → act (cards/physics/social) →
consequence → record (replay)*.

---

## 7. Campaign loop

Macro layer is the **calendar** (§16). The campaign is a sequence of days. Each day:

- Morning: check messenger, read schedule, see deadlines.
- Work block: explore current floor / do "tasks" that are really encounters.
- Evening choice: sleep / side project / 알고리즘 공부 / networking / help coworker /
  simply go home. Each costs time, affects stats, may queue events.
- Night: unavoidable or scripted encounter (the building shifts).
- Save point at day end (or at elevator).

Strategic tension: you cannot max every stat, finish every side quest, and keep every
relationship. The scheduler makes that explicit and visible.

---

## 8. Character stats

Stats are integers, typically 1–10 at start, can grow to ~20. They are *not* generic
+% modifiers. Each has a distinct mechanical role:

- **체력 (HP):** physical health. Reaches 0 → "퇴각" (retreat / game-over variant).
  Lost by physical damage and certain social failures.
- **기력 (Energy):** card/action currency per combat turn (like mana). Refilled each
  turn to a max modified by 워라밸 and 광기.
- **집중력 (Focus):** determines draw count, card-sequencing power, and "technical"
  card accuracy. Low focus → cards fizzle or misfire (random valid target). Also gates
  debugging/디버그 effects.
- **눈치 (Nunchi):** perception of hidden meaning. Reveals hidden dialogue options,
  exposes NPC intent, reduces "사회" (social) card miss chance, and lets you read
  enemy intent icons. Pure perception stat.
- **배짱 (Balls/Guts):** resistance to 압박 (pressure). High 배짱 ignores intimidation
  debuffs, can take "risky" options, and reduces authority-based card cost inflation.
- **성과 (Performance):** measurable career output. Drives rank-related dialogue,
  unlock thresholds, and "career" card power. Also a resource spent in politics.
- **인맥 (Network):** access to people/favors. Lets you draw "social" cards from an
  outsider pool, call in favors (skip an encounter, get info), and improves relationship
  gain rates.
- **스펙 (Spec):** credentials capital. Unlocks rare cards, interview/이직 options, and
  certain "systems" cards. Slowly accumulated via study actions.
- **광기 (Madness):** overwork/unstable power. Powers high-risk archetypes (폭주,
  과로). High 광기 boosts damage but increases misfire chance and 워라밸 drain; very
  high 광기 unlocks forbidden cards but risks 자기붕괴 (self-collapse) status.
- **워라밸 (Work-life balance):** long-term sustainability. Slowly decays with 야근/
  회식; when 0, you gain a permanent "번아웃" debuff and cannot recover 기력 fully.
  Raised only by going home / resting (which costs progress time).

Distinct roles summary: HP=lose condition, Energy=turn currency, Focus=execution
quality, Nunchi=information, Balls=pressure resistance, Performance=political capital
+ unlocks, Network=favors/access, Spec=long-term unlocks, Madness=risk power,
Worklife=decay gate.

---

## 9. Card-system design

### Data model

A card is **data**, not a class with behavior. Behavior lives in the **effect system**
(§27, §33). A card definition:

```
CardDef {
  U32 id;
  U8  type;        // 공격/방어/기술/사회/시스템/저주/특별
  U8  rarity;      // 일반/희귀/영웅/전설
  U8  cost;        // 기력 cost
  U8  archetype;   // 연계/과로/물리/사회/시스템...
  U16 name_id;     // -> Hangul string table
  U16 text_id;     // rules text
  U16 flavor_id;
  U8  upgrade_of;  // 0 if base
  U8  exhaust;     // 소모: removed from deck this combat
  U8  retain;      // 보존: stays in hand across turns
  U16 effect_count;
  EffectOp effects[4]; // up to 4 effect ops
}
```

`EffectOp` is a tagged op consumed by the effect interpreter:
`{U8 op; I16 a; I16 b; U16 ref;}`. Ops: DAMAGE, BLOCK, DRAW, ENERGY, STATUS_ADD,
FORCE, GRAVITY, SPAWN_BODY, HEAL, STAT, RELATIONSHIP, FLAG, etc. This keeps cards as
pure data and makes the DSL able to define new cards too.

### Piles
- `draw_pile` (shuffled with seeded RNG at combat start)
- `hand` (max 10)
- `discard`
- `exhaust` (소모)
- `retain` flagged cards skip discard.

### Keywords
- **연계 (Combo):** +effect if you played a card of the same archetype last turn.
- **소모 (Exhaust):** leaves combat after use.
- **보존 (Retain):** not discarded at end of turn.
- **반격 (Retaliate):** when hit, auto-trigger a small effect.
- **폭주 (Overdrive):** scales with 광기; can backfire.
- **과로 (Overwork):** costs HP now, pays off later (energy/stat).

### Upgrades
Each base card has an `upgrade_of` target; upgrade swaps the def for a stronger one
(kept in the collection as a separate def id). Simple, data-only.

### Archetypes / synergies
- **물리 (Physics):** interacts with bodies (의자 투척, 책상 뒤집기).
- **사회 (Social):** requires/uses 눈치, 인맥, relationships.
- **시스템 (System):** debug, gravity, memory, rendering hacks.
- **과로/광기:** high-risk power.
- **방어/생존:** block, retain, heal.

Design rule: a card may belong to multiple archetypes via bitflags; synergy checks are
bitwise, not string compares.

---

## 10. Combat rules

### Turn structure (deterministic order)

1. **Start-of-turn (player):** refill 기력 to max; apply start-of-turn statuses;
   tick delayed effects; run scheduled events whose time==now.
2. **Card-selection phase:** player draws to hand size (Focus-dependent), plays cards
   in any order, each emits **events** (not direct mutations). Playing a card may
   trigger enemy intent or dialogue.
3. **Physics-resolution phase:** all queued `APPLY_FORCE`/`SPAWN_BODY` events are
   applied; the fixed-timestep physics sim advances N steps (see §23, §35). Damage from
   collisions is computed and emitted as `DEAL_DAMAGE` events resolved immediately
   after the sim settles (deterministic: fixed step count, fixed seed).
4. **Status resolution:** apply DoT, decay buffs, resolve `검토 후 회신` delayed cards.
5. **Enemy intent phase:** each enemy executes its pre-declared intent (telegraphed
   last turn), emitting events; light physics for enemy-spawned bodies.
6. **Dialogue triggers:** any queued combat dialogue fires (can pause for choice).
7. **Cleanup:** discard non-retained hand, tick turn counter, check win/lose.

**Replayability guarantee:** physics runs in *fixed-step bursts* (e.g., 8 steps of
1/60s) triggered only by explicit events, never continuously during player thinking.
Thus combat is a discrete sequence of (input → event list → deterministic sim burst →
result). No continuous real-time entropy.

### Win/lose
- Enemy HP 0 → victory (card reward).
- Player HP 0 → 퇴각 (retry from last save, or bad ending variant).
- 회식/사회 encounters: win = survive until timer or meet social goal; lose = shame/
  stat penalties, not death (usually).

---

## 11. Physics-combat integration

The bridge is **the event system only**. Cards never call the physics solver directly.
A card emits `SPAWN_BODY` (chair at player anchor) and `APPLY_FORCE` (impulse vector).
The physics-resolution phase consumes these in deterministic order.

Damage from physics = function of collision impulse magnitude ≥ threshold, mapped via
a small table (e.g., impulse 5→6 dmg, 10→12, etc.), computed by the solver and emitted
as `DEAL_DAMAGE` events. This keeps physics "funny but fair": a chair thrown at a wall
does nothing; thrown at a copier does damage scaled by speed.

`중력 오류` = enqueue a `SET_GRAVITY` event affecting the physics world for K turns.
`커널 패닉` = enqueue N random `APPLY_FORCE` events on all bodies (RNG-seeded).
`정리정돈` = set bodies to sleep + convert summed kinetic energy → player Block.

Physics is capped (≤64 bodies), sleeps when below threshold velocity, and the sim
burst length is fixed so replays match bit-for-bit.

---

## 12. Enemy and boss framework

### Enemy archetype (data)
```
EnemyDef {
  U32 id; U16 name_id; U16 sprite_id;
  I32 hp; I32 block;
  U8  ai_profile;     // utility profile id
  U8  rank;           // 직급 for social pressure
  U16 intent_table[8];
  U8  behavior_flags; // uses_meetings, delayed_resolve, social_only...
}
```

### Boss-design framework
A boss = layered state machine + utility AI + scripted phase triggers driven by the
DSL/scheduler:
- **Phase thresholds:** at HP% or turn count, enqueue `LOAD_SCENE`/`SET_FLAG`/
  `SPAWN_BODY`/new intent table.
- **Intent telegraph:** bosses show 1–2 turns of intent; some intents are
  "delayed" (resolve next turn) or "conditional" (only if flag set).
- **Environment hooks:** bosses manipulate the physics world (spawn paper bodies,
  flip gravity) via events, never by poking the world directly.
- **Social bosses** (회식, 인사팀장) may have 0 HP and instead track a "Face/이미지"
  or "Patience" meter.

### Example enemies
- **복사기 악령 (Copier Wraith):** spawns paper AABBs each turn (bodies), jams
  movement; weak to 물리 cards that clear bodies.
- **인사팀장 (HR Team Lead):** passive `검토 후 회신드리겠습니다` — your targeted card
  effects resolve one turn later (delays the event, flagged).
- **팀장/과장:** meeting mechanics (locks a card slot), blame transfer (moves a debuff
  to you), 압박 (intimidation reduces your effective 배짱).

### CEO (near-final)
Apparent "HP" = 회사 가치 / institutional power, not health. Phases:
1. Procedure (bureaucracy intents).
2. Surveillance (reveals your replay log as a weapon against you).
3. Administrator convergence (`관리자` reveals dual meaning).
Defeating ≠ killing; ending depends on choice cards played.

---

## 13. Dialogue design

Dialogue is a first-class system, not flavor text. A conversation is a **graph** of
nodes (mostly authored in the DSL, §26). Node types:

- `say(speaker, text_id)` — plain line; may carry hidden `intent` text revealed by
  눈치.
- `choice(options[])` — each option: `label_id`, `cond` (stat/flag/relationship expr),
  `reveal_cond` (눈치-gated), `target`, `effects[]`.
- `branch(expr, a, b)` — conditional jump.
- `combat_start(enemy_id)` — transition directly into battle; combat can later
  `dialogue_resume(node)`.
- `message(to, text)` — send a messenger message.
- `wait(ms)` / `camera_move(...)` / `sound(...)` — presentation.

**Hidden meaning pattern:** a `say` node stores both `public_text` and `hidden_text`.
If `nunchi >= threshold`, the UI overlays the hidden line, e.g.:

> 과장: "시간 되실 때 한번 봐주세요."
> [숨은 의미: 지금 당장 해주세요.]

Options can be `hidden` (only shown if cond true) or `revealed_by_nunchi` (shown only
with enough 눈치). Consequences are recorded as events (stat/rel/flag/schedule), so
they replay and persist.

**Consequences supported:** stat change, relationship change, flag set, card
add/remove, schedule future event, start combat, spawn entity, change scene, set
delayed consequence (a scheduled event referencing this dialogue).

**NPC memory:** NPCs store `heard[]` and `reacted_to[]` flags; later scenes branch on
them (`[npc:kim.resentment >= 3]`).

---

## 14. 눈치 and hierarchy systems

### Hierarchy (직급)
Ranks: 인턴 < 사원 < 주임 < 대리 < 과장 < 차장 < 부장 < 임원. Stored as enum `U8`.
A helper `RankDiff(a,b)` = a.rank - b.rank.

Mechanical effects of rank difference (always clamped, never absolute):
- **Dialogue:** options with `[rank <= player+S]` are locked unless 배짱 high.
- **압박 (Pressure):** higher-rank NPC may apply an `INTIMIDATE` status reducing your
  effective 배짱 by `min(3, diff)` unless your raw 배짱 ≥ threshold.
- **Card cost:** "social/compliance" cards cost +1 기력 per rank diff when used
  *against* a superior; "authority" cards you hold cost less if you outrank.
- **Blame transfer:** a superior can move a `BLAME` debuff onto you more easily in
  social combat.
- **Meeting behavior:** superiors set agenda (which cards you may play this turn).
- **Relationship risk:** offending a superior costs more 호감 than offending a peer.

This is non-deterministic in feel because it interacts with *your* stats (배짱,
눈치, 성과, 인맥) and *their* personality flags. A high-배짱 low-성과 player resists
압박 but risks 블래밋; a high-눈치 player reads the trap and avoids it.

### 눈치 concretely
- Reveals hidden dialogue + hidden options.
- Lowers 사회 card miss chance: `miss = clamp(0.25 - 0.03*nunchi, 0, 0.25)`.
- Shows enemy intent with more detail at higher values.
- Some encounters are *only* winnable via 눈치 (read the room, say the right thing).

---

## 15. Relationship and office-politics model

### Per-NPC relationship state (not one bar)
```
RelState {
  I8  favor;       // 호감 (affection)
  I8  trust;       // 신뢰
  I8  debt;        // 부채 (they owe you / you owe them)
  I8  suspicion;   // 경계
  I8  influence;   // 권력
  I8  respect;     // professional respect
  I8  resentment;  // 원한
  I8  loyalty;     // 충성
}
```
Asymmetric: `RelState` is stored from *player's perspective toward NPC* and a separate
one for *NPC toward player* (mirror fields). A coworker may `favor=+3` but `trust=-1`.

### Office-politics system
- **Blame (블래밋):** a resource that can be on player or NPC. `책임 전가` (blame
  transfer) moves it; if you hold blame at performance review, 성과 penalty.
- **Credit (공로):** opposite; spendable to unlock promotions/options.
- **Favors:** `debt` lets you `call_in_favor` (skip encounter, get info, reduce cost).
- **NPC behaviors driven by RelState + utility AI (§18):** defend you, redirect blame,
  sabotage, recommend, leak. Example: if `kim.loyalty>=4 && kim.influence>=3`, Kim
  auto-redirects one blame away from you per act.

### Graph
A fixed array of ~16 NPCs; edges are implicit via pairwise `RelState`. No need for a
general graph lib.

---

## 16. Calendar and time-management model

### Time representation
`GameTime { U16 year; U8 month; U8 day; U8 weekday; U16 minute; }` (minute 0..1439).
Helpers: `AddMinutes`, `AddDays`, `IsWeekend`, `NextWeekday`.

### Scheduler
A **priority queue of `ScheduledEvent`** sorted by `GameTime`:
```
ScheduledEvent {
  U32 id; GameTime when; U16 script_node; U8 fired; U8 recurring; U16 payload;
}
```
Determinism: sorted by time, ties broken by `id` (stable). The campaign advances time
via explicit `TIME_ADVANCE` events (never wall-clock). When `now` passes a queued
event's `when`, it fires (runs a DSL node / spawns encounter / sends message).

### Player evening choice
At day-end, present options (sleep/side-project/study/network/help/home). Each calls
`TIME_ADVANCE` by a block and applies stat deltas + may enqueue future events (e.g.,
"interview in 3 days"). The scheduler viewer (§31) shows queued events so choices are
informed.

Strategic tension is explicit: each evening you pick one or two blocks; the calendar
shows conflicting deadlines. You literally cannot do everything.

---

## 17. Messenger system

A fake Korean messenger ("성광톡" / 성광메신저). Model:
```
ChatMsg { U32 id; U16 from; U8 channel; GameTime sent; U8 read; U8 replied;
          U16 text_id; U16 on_read_script; U16 on_reply_script; }
```
Channels: DM, group, system, family, recruiter. Inbox is a ring buffer.

Integration:
- Messages can arrive during battles (queued, shown post-turn or as a popup that
  pauses for a choice).
- `read`/`replied` flags drive consequences via DSL scripts.
- Tied to scheduler: a message may itself be a `ScheduledEvent` (e.g., 김부장 pings at
  23:48).
- Ignoring vs replying → different `RelState`/`flag` outcomes.

Example:
```
오후 11:48
김부장
파일 하나만 확인 부탁드릴게요^^
```
Replying "네, 확인했습니다" → +성과 small, -워라밸, +김부장 debt(you owe). Ignoring →
+김부장 suspicion, but +워라밸. Both recorded.

---

## 18. NPC AI

Lightweight **utility AI** (feasible in HolyC, deterministic). No ML.

### State
`AIState { U8 profile; I8 needs[6]; U8 goal; U32 blackboard_flags; }`
Needs examples: authority, project_progress, blame_avoidance, promotion, leave_work,
reputation.

### Action selection
Each tick (social encounter or enemy turn), build candidate `Action`s:
`{U16 op; I16 score; U32 tiebreak_id;}`. Score = Σ weights[need] * consideration(action,
state). Pick max; deterministic tie-break by `tiebreak_id` (stable). Actions are just
event emissions (same op set as cards). This unifies combat AI and social AI: an enemy
"meeting" and a manager "pressuring you in dialogue" are both utility-scored action
emissions.

### Determinism
RNG only used for *noise* added to scores, seeded per (npc_id, turn). Tie-break by
`tiebreak_id` ensures identical replays. AI state is part of saved/game state and is
hashed for desync detection.

### Profiles
- Manager: weights authority + blame_avoidance high.
- Intern: weights leave_work + reputation.
- HR: weights procedure + surveillance.
- Sympathetic senior: weights protect_subordinate + reputation.

---

## 19. Campaign plot and acts

Four acts. The building *is* the company OS; realization is gradual.

### Act I — 야근 (Overtime)
- Wake 3:17 AM. Tutorial: move, read poster, first messenger ping (`[알 수 없음]
  퇴근하지 마세요.`).
- Explore 4F 개발1팀. Combat: 복사기 악령 (intro to physics chairs). Dialogue coworker
  (눈치 tutorial). First boss: **주임 악령** (a possessed team lead) teaching meeting/
  blame mechanics.
- Tone: funny + uncanny. Foreshadow: monitors show impossible floors; a name renders
  wrong.

### Act II — 조직 (Organization)
- Impossible departments appear (13F ???). Politics matter: performance review
  encounter, blame/credit economy, recruiter contact (이직 thread).
- NPC memories conflict (the old employee says the 13F always existed; HR denies).
- Mid-boss: **인사팀장** (delayed-resolve). Relationship arcs activate.

### Act III — 시스템 (System)
- Rendering/limitation anomalies become clues: Z-buffer deletions, Hangul corruption
  point to a missing person (`???` whose name can't compose). Replay log shown as
  surveillance. Memory/debug cards reveal "world rules."
- Boss: **전략기획실 장** guarding the renderer core. Choice: expose or preserve.

### Act IV — 관리자 (Administrator)
- Highest layers. `관리자` double meaning converges: corporate manager == sysadmin.
- CEO boss (institutional HP). Ending choice cards:
  - **퇴근** (escape)
  - **사직서** (resign — may end or redirect)
  - **관리자 되기** (become administrator — own it)
  - **시스템 폭로** (expose)
  - **일반인의 삶** (choose ordinary life)
- Endings branch on relationships, flags, stats.

Side stories: intern's startup offer, senior's burnout, HR's secret, recruiter's
truth, the old employee = a previous player/administrator.

---

## 20. Important NPC cast

- **윤사원 (You):** junior dev. Rank 사원. The player.
- **김대리 (sympathetic senior):** public: helpful, tired. Private: protecting you
  because he was once like you. Arc: burnout vs mentoring. Function: tutorial guide,
  favor source.
- **박과장 (ambiguous manager):** public: reasonable. Private: terrified of 차장,
  offloads blame. Arc: ally or saboteur by your choices. Function: 압박 teacher,
  blame vector.
- **이인사 (HR):** public: warm. Private: procedure is survival. Arc: reveals
  system-lore. Function: delayed-resolve boss, lore.
- **정인턴 (intern):** eager, hustle-culture. Arc: learns or burns. Function: comic,
  side-quest giver.
- **최부장 (old employee who knows too much):** seems senile; actually a former
  administrator. Arc: reveals truth. Function: mystery anchor.
- **한대리 (recruiter/startup contact):** offers 이직. Arc: truth about outside.
  Function: escape-route giver.
- **성과맨 (hustle obsessive):** "스펙 쌓으세요." Function: spec/card rewards, satire.
- **고요한 사원 (quiet rejector):** quietly rejects hustle. Function: emotional
  counterweight, ending variation.
- **CEO / 임원:** institutional power. Function: final boss.
- **관리자 (Administrator):** the convergence entity. Function: meta final choice.

Each has `role, rank, public, private, arc, gameplay_fn, secret`.

---

## 21. World/floor structure

Elevator = world map abstraction. Floors (small, dense rooms):

- **B2 주차장:** intro, cars as physics props.
- **1F 로비:** hub, messenger, save point.
- **4F 개발1팀:** Act I hub; desks, monitors, meeting room.
- **7F 영업본부:** social-combat intro.
- **9F 인사팀:** HR, reviews.
- **13F ???:** appears despite not normally existing; corrupted space, mystery.
- **17F 전략기획실:** renderer core.
- **20F 임원층:** CEO.
- **옥상 (rooftop):** escape/ending space.
- **서버실:** physics/debug clue space.
- **계단 / 비상계단:** backroute, hidden areas.

Maps are hand-authored grids of rooms (≤ ~40×40 tiles internal) with entity anchors.
No open world.

---

## 22. Renderer architecture

CPU software renderer. Internal buffer 320×240 (or 360×240), scaled nearest-neighbor
to screen. 16/32-bit color acceptable.

### Staged implementation
1. **Math types:** `Vec3`, `Mat4`, `Quat` (or Euler). F64.
2. **Transforms:** world→view→clip.
3. **Camera:** position + look; perspective `Mat4`.
4. **Triangle projection:** clip-space → screen; perspective divide.
5. **Clipping:** Sutherland–Hodgman against near plane + screen bounds.
6. **Rasterizer:** triangle fill, flat or Gouraud-lite.
7. **Z-buffer:** `F64 depth[W*H]` (or fixed-point). Clear per frame.
8. **Lighting:** one directional + ambient; flat shading. Optional vertex lerp.
9. **Textures:** tiny (≤32×32) nearest sampled; optional (skip first).
10. **Scene graph:** flat array of `RenderObj { mesh; transform; flags }`.
11. **Animation:** swap frames / lerp transforms; no skeletal (sprites OK).
12. **Optimization:** backface cull, only draw visible set, fixed-point where safe.

### Optional
- Billboards for characters (draw textured quads facing camera).
- Fog (depth-based color blend).
- Dithering for "crunch."
- Intentional PS1 vertex jitter (off by default; can be a "glitch event" effect).

Aesthetic: PS1/early-Polygonal crunch; readable over realistic.

---

## 23. Physics architecture

Minimal rigid-body engine, deterministic, capped.

### Types
- `Vec3` (F64).
- `RigidBody { Vec3 pos, vel, angVel; F64 mass, invMass; U8 shape; U16 collider;
  U8 sleep; U32 id; U16 owner_card; }`
- Shapes v1: **plane, sphere, AABB**. (OBB/capsule/convex = deferred, §52.)
- `Collider { U8 type; Vec3 extent/normal; F64 restitution; F64 friction; }`

### Loop
- **Fixed timestep** `dt = 1/60`. Sim advances in *bursts* of fixed steps (combat: 8
  steps per resolution phase; explore: only when a body is active).
- **Gravity** global `Vec3`, overridable by `SET_GRAVITY` event.
- **Damping** linear+angular per step.
- **Broad phase:** sweep-and-prune on AABB of colliders (≤64 bodies → simple).
- **Narrow phase:** plane/sphere/AABB analytic; produce contact manifold (point,
  normal, penetration).
- **Solver:** sequential impulses; positional correction (Baumgarte). Restitution +
  friction (Coulomb clamp).
- **Sleeping:** velocity below epsilon for K steps → sleep (no integration) until
  force applied.

### Collision response (planning level)
For contact with normal `n`, relative velocity `vrel`, compute normal impulse
`j = -(1+e)·vrel·n / (invM_a+invM_b)`. Apply `vel += j·invM·n` to each. Friction
impulse clamped to `μ·j`. Positional correction `pos += n·(penetration·β/(invM_sum))`.

### Why bursts, not continuous
Combat must be replayable: a burst of N fixed steps with seeded RNG for
`커널 패닉` is bit-deterministic. Continuous real-time physics during player thinking
would make replays impossible. Explore mode uses continuous-ish stepping only when
bodies are awake (cosmetic), and never affects combat outcome.

---

## 24. Hangul renderer architecture

TempleOS has no Korean stack. We build one.

### Internal string representation
Store text as **UTF-8-ish byte stream but we only decode Hangul + ASCII + punctuation
explicitly**. Actually simpler: store game strings as **arrays of "glyph codes"**:
- Code space: `0x0000–0x1FFF` = Latin/digits/punct (1:1 to a small bitmap font).
- `0x2000–0x2xxx` = precomputed **syllable index** OR **jamo composite token**.

Design decision: **composite at render time, not precomposed glyphs.** We store
syllables as a 3-tuple (초성, 중성, 종성) in a packed 16-bit: `cho(5)|jung(5)|jong(5)`
(19×21×28 ≈ 11k combos; pack into 15 bits). A font provides **jamo bitmaps** (ㄱㄴㄷ…
ㅏㅑ… ㄱㅄ) at a small cell (e.g., 8×8 or 10×10). At layout time we compose a syllable
block from its jamo using Hangul composition rules (소리꿍/아래아 placement, 종성 bottom).

### Pipeline
1. **Decode** string → token list (jamo-triple or latin/punct).
2. **Decompose** any precomposed input (we may accept Unicode syllables from the DSL
   authoring tool and decompose at build time) into jamo triples.
3. **Layout:** place tokens left-to-right; a syllable block is one cell width; apply
   line-breaking on spaces and explicit `\n`; Korean doesn't break inside a syllable.
4. **Compose glyph:** render 초성 top-left, 중성 right (or bottom for ㅏ계열/ㅗ계열
   per rule), 종성 bottom; combine into the cell bitmap.
5. **Blit** to framebuffer (renderer or 2D overlay).

### Metrics
`cellW`, `cellH`, `lineH`, `advance`. Dialogue box = word-wrapped composed bitmaps.

### The deliberate flaw (plot)
One specific jamo combination (e.g., a rare 종성 cluster representing **최부장's
daughter's name**) is *intentionally not in the font* — it "cannot be represented."
Encountering it yields a corrupted block and a hidden flag `NAME_CORRUPT`. This is a
real mystery clue discoverable by the player, not a bug.

---

## 25. Korean IME architecture

Two-beol (두벌식) composition state machine. Input is scancode/keychar from TempleOS;
we map to jamo.

### State
`IMEState { U8 mode; // 0=Latin,1=Korean
  U8 cho; U8 jung; U8 jong; // current syllable jamo indices, 0=none
  U8 jung_compound; // building ㅘ etc.
  U8 jong_compound; }`

### Two-beol mapping (abridged)
- Consonants initial: ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ (key: r,k,s,e,E,f,a,q,t,T,d,w,c,z,x,v,g,b,y,n,m,...).
- Vowels: ㅏㅑㅓㅕㅗㅛㅜㅠㅡㅣㅐㅒㅔㅖㅘㅙㅚㅝㅞㅟㅢ (key: f,d,s,e,w, etc. — standard two-beol).

### State machine
1. First consonant → `cho`.
2. Vowel → `jung`; if next key is compound vowel part (e.g., after ㅗ press ㅏ → ㅘ),
   combine into compound jung.
3. Consonant after vowel → `jong`; if next is compound-final part → combine (e.g.,
   ㄺ). 
4. Another consonant after a filled jong → **commit** current syllable, start new with
   that consonant as `cho` (or as `cho` of next if it's a double-initial).
5. Space/Enter → commit.
6. **Backspace:** if jong set → clear jong; elif jung → clear jung (back to cho only);
   elif cho → clear cho. Never merges across committed syllables (simple).
7. **Mode switch** (e.g., Han/Eng key or a hotkey) toggles `mode`; Latin passes
   through.

Output is a composed syllable token (§24) committed into the active text buffer
(dialogue input, naming, search). No full modern IME parity; enough for in-game Korean
typing and a "name the missing person" puzzle.

---

## 26. Dialogue DSL design

Tiny, limited, line-oriented. Authoring tool (offline) may accept Unicode and
decompose to our token stream; the runtime parser is minimal.

### Syntax (subset)
```
scene late_office
bg office_night
music hum_01

park:
  say park "아직 안 가요?"
  choice:
    "네, 조금만 더 하려고요." -> stay
    "저 이제 가려고요." -> leave
    [nunchi >= 6] "과장님도 이제 가시죠?" -> reverse_pressure

stay:
  stat hp -2
  stat performance +1
  card add "야근"
  goto end

leave:
  flag set LEFT_EARLY
  goto end

reverse_pressure:
  rel park trust +1
  msg park "고생하세요." on_read end
  goto end

end:
  return
```

### Supported directives
`scene`, `bg`, `music`, `sound`, `say`, `choice` (with `[expr]` guards and
`reveal_by_nunchi` flag), `stat`, `rel`, `flag`, `card add/remove`, `msg`, `goto`,
`return`, `combat_start`, `spawn`, `camera`, `wait`, `schedule`, `set_gravity`,
`sound`, `flag`, `load_scene`.

### Parser/interpreter
- Tokenize line → (directive, args).
- Build node table (label → instruction list). `goto`/choice targets resolved
  post-parse.
- Interpreter runs a node, executing effects by **emitting events** (§27), then jumps.
- Expressions `[stat >= n]`, `[flag X]`, `[rel npc >= n]`, `[rank ...]` evaluated by a
  tiny safe evaluator (no loops, no functions). 

Keep it non-Turing-complete: no variables, no recursion beyond goto-graph (guarded by
visited set to prevent infinite loops).

---

## 27. Event system

The backbone. All systems communicate via events.

### Event representation
```
Event {
  U16 type;        // PLAY_CARD, DRAW_CARD, DEAL_DAMAGE, APPLY_FORCE,
                   // DIALOGUE, CHOICE, STAT_CHANGE, RELATIONSHIP_CHANGE,
                   // SET_FLAG, START_BATTLE, END_BATTLE, LOAD_SCENE,
                   // CAMERA_MOVE, SCHEDULE_EVENT, MESSAGE_RECEIVED,
                   // TIME_ADVANCE, SAVE_GAME, SOUND, CAMERA_SHAKE,
                   // SPAWN_BODY, DESTROY_BODY, COLLISION, HEAL, APPLY_STATUS...
  U32 src_id;      // emitter (entity/card/npc)
  U32 dst_id;      // target
  I32 a, b;        // params (damage, force x, etc.)
  U16 ref;         // string/def id
  U8  deferred;    // 0=immediate, 1=next phase
  U32 turn_seq;    // ordering key for determinism
}
```

### Queue & ordering
- One global `EventQueue` (ring buffer, fixed cap ~1024).
- **Immediate** events processed this phase in FIFO; **deferred** pushed to a
  `next_phase` list sorted by `turn_seq` then type then src_id (stable).
- Each event has a handler per system (a `switch(type)` dispatch). Handlers emit more
  events (capped; see below).

### Anti-explosion
- Max events per phase (e.g., 256). If exceeded → log + assert in debug. Prevents
  recursive storms.
- `COLLISION` events do not re-emit `COLLISION`; damage is computed once per contact
  per burst.
- Deterministic: processing order is fully defined; same seed + same inputs → same
  result.

### Logging / replay
Every event appended to the current **replay log** with its `turn_seq`. Debug console
can dump the queue and replay it.

---

## 28. Deterministic RNG and replay

### RNG
`RNGState { U64 s; }` — xorshift64 or splitmix64. `RandU32()`, `RandRange(a,b)`,
`RandF64()`. **All** randomness (shuffle, AI noise, 커널 패닉 forces, misfires) draws
from this single seeded stream. No `rand()`, no time-based seeds in sim.

### Replay record
```
Replay {
  U64 seed;
  U32 initial_state_hash;
  U16 version;
  Input[] inputs;   // {turn_seq, type: CARD_PLAY/CHOICE/SCHEDULE/MOVE, payload}
  U32 final_state_hash;
}
```
- The **only** non-deterministic player inputs are recorded: card plays (which card,
  which target), choices (option index), scheduler picks, movement seeds (if any).
- Physics bursts and AI are *derived*, not recorded, so the replay is small.
- To replay: load initial state by seed, feed inputs in order, re-run sim. Compare
  `final_state_hash` to detect desync.

### Desync detection
After each act/phase, compute `hash(game_state)` (stats, rel, flags, bodies'
positions+velocities, RNG state). If during replay it diverges → log diff, break.
In-world: this exact log is presented as **업무 기록 / 감사 로그** — a surveillance
system the company uses; the player can later *read* their own replay to find clues
(who moved what, when the name corrupted).

---

## 29. Save/load design

### Format
Plain text or a simple binary block. For HolyC pragmatism: a **single flat file**
`saveNNN.ssg` with tagged sections, written via `FileWrite`/`CFileWrite`:

```
VER 1
TIME 2026 3 17 1 197
STATS hp 12 energy 3 focus 5 nunchi 4 balls 3 perf 6 net 4 spec 2 mad 1 wlb 5
DECK 12 3 7 9 ...        # card def ids in active deck
COLL 30 3 7 9 ...        # owned collection
UPG 3 21 14 ...          # upgraded card ids
REL kim favor 3 trust 1 ...
FLAGS LEFT_EARLY NAME_CORRUPT
SCHED 3 <events>
SCENE 4F_dev
NPC <npc states>
REPLAY_META seed initial_hash
ENCY 5 12 30 ...         # discovered card/codex ids
```

### Versioning/migration
`VER` field; loader switches on it; unknown future fields skipped with a warning. Keep
migration functions `MigrateFromV0`, etc. Because content is data, adding cards/NPCs
doesn't break saves (ids stable).

### What persists
date/time, stats, collection, deck, upgrades, inventory, relationships, scheduled
events, flags, encyclopedia, current scene, NPC states, optional replay meta.

Autosave at safe points (elevator, day end); manual save anywhere via debug/pause.

---

## 30. Audio

Tiny, optional, non-blocking.

- **Output:** TempleOS `Sound`/`扬声器` simple beep, or pre-baked 8-bit PCM samples
  blitted to the audio buffer if available. Keep it minimal: square blips + noise.
- **UI:** card play, selection, error.
- **Combat:** impact (noise burst scaled by collision impulse), whoosh (force).
- **Ambience:** fluorescent hum (low square), printer (noise bursts), messenger ping
  (two-tone).
- **Music:** loop a short procedural arpeggio per zone; not a requirement, can be a
  single hum track. 
- **No synthesis requirement:** samples are fine; keep total audio < few hundred KB.

Audio is explicitly **non-blocking to core delivery**: if audio is hard, ship silent
+ hooks.

---

## 31. Debugging and developer tooling

Built because TempleOS lacks a debugger. Toggle overlay (e.g., F1).

- **Debug console:** scrollback of recent events + commands (`/phys`, `/rels`,
  `/seed`, `/warp 13F`, `/spawn chair`, `/replay`).
- **Frame timing:** ms/frame, physics steps, event count.
- **Object inspector:** click entity → id, pos, vel, stats, owner.
- **Event log:** live tail of `Event.type` with src/dst.
- **Card-state inspector:** piles, statuses, cost, exhaust/retain.
- **Physics viz:** draw colliders (wire), velocities, contacts, sleeping state.
- **Scene graph viewer:** list render objects + transforms.
- **AI trace:** last scored actions per NPC with scores.
- **Relationship inspector:** matrix of RelState.
- **Scheduler viewer:** upcoming ScheduledEvents with times.
- **RNG seed display** + step button.
- **Replay controls:** play/pause/step/seek; diff against live.
- **Script trace:** current DSL node + last jumps.
- **Save-state dump:** hex/text of current state hash inputs.
- **Crash repro:** command to reload from a replay seed+inputs.
- **Renderer wireframe mode:** disable fill, draw edges.

These are normal game systems reading the same state; they make the weird environment
survivable for the dev.

---

## 32. HolyC project/module organization

TempleOS uses a flat-ish file tree; we mirror the requested structure as directories
of `.HC` files. `::` namespaces via prefixes (`Core`, `Kr`, `Rndr`, `Phys`, `Game`,
`Narr`, `Tool`, `Cnt`).

```
Sungwang/
  Core/
    Mem.HC        # MAlloc wrappers, pools
    Containers.HC # ring buf, dyn array, fixed pool, queue
    Math.HC       # Vec3, Mat4, quat, lerp, clamp
    Str.HC        # our glyph-string type, decode
    RNG.HC        # seeded xorshift
    Serial.HC     # save/load, tag writer/reader
  Platform/
    Input.HC      # keyboard scancode -> jamo/keys, mouse
    Files.HC      # FileRead/Write helpers
    Timing.HC     # TSC frame clock, fixed-step accumulator
    Audio.HC      # blips/samples
  Korean/
    Hangul.HC     # decompose/compose jamo triples
    Font.HC       # jamo bitmaps, latin glyphs
    Layout.HC     # text layout, wrap, dialogue box
    IME.HC        # two-beol state machine
  Render/
    Raster.HC     # triangle fill, z-buffer
    Camera.HC
    Mesh.HC       # tiny primitives
    Texture.HC    # optional tiny tex
    Scene.HC      # render obj array
    DebugDraw.HC  # wireframe, collider viz
  Physics/
    Bodies.HC
    Colliders.HC
    Broad.HC      # sweep-and-prune
    Narrow.HC     # plane/sphere/AABB
    Solver.HC     # impulses
  Game/
    Entities.HC
    Events.HC     # Event def + dispatch
    Cards.HC      # defs, piles, effect interp
    Combat.HC     # turn loop
    Statuses.HC
    AI.HC         # utility scoring
    Items.HC
  Narrative/
    Dialogue.HC
    DSL.HC        # parser/interp
    Scheduler.HC
    Relationships.HC
    Messenger.HC
    Campaign.HC   # act progression, flags
  Tools/
    Console.HC
    Profiler.HC
    Inspector.HC
    Replay.HC
  Content/
    cards.ssg     # card defs (data)
    scenes/*.ssc  # DSL scripts
    font_*.HC     # generated glyph data
    strings.ssg   # string table (ids -> token streams)
  Main.HC         # boot, game loop
```

HolyC specifics: classes OK for `RigidBody`, `CardDef` as `class`; but prefer
**structs + function pointers / tagged unions** for polymorphic entities. Avoid deep
inheritance. Use `U0` functions taking pointers. Memory via `MAlloc`/`Free`; use pools
to avoid fragmentation.

---

## 33. Important core structs and data models

(Condensed; full in code later.)

- `Vec3 {F64 x,y,z;}`
- `Mat4 {F64 m[16];}`
- `RigidBody` (§23).
- `CardDef`, `EffectOp` (§9).
- `CombatState { piles; U8 turn; Entity player; Entity enemies[8]; StatusList; }`
- `Entity { U32 id; I32 hp; I32 block; U8 team; RelState*; AIState*; RenderObj*; }`
- `RelState` (§15).
- `ScheduledEvent` (§16).
- `ChatMsg` (§17).
- `AIState` (§18).
- `GameTime` (§16).
- `Event` (§27).
- `RNGState` (§28).
- `DSLNode { U16 type; U16 args[6]; }`
- `RenderObj { mesh*; Mat4 xform; U8 flags; }`
- `SaveFile` header (§29).

Use **stable U32 ids** for all entities/bodies/cards; reference by id, not pointer, in
saved/replay state.

---

## 34. Suggested APIs

```
// Core
U0  CoreInit();
RNGState* RNGGet();
U32 RandU32(); I32 RandRange(I32 a,I32 b);

// Strings/Hangul
Str* StrDecode(U8* utf8);          // -> token stream
U0  HangulCompose(U16 jamo_triple, U8* out_cell);
U0  LayoutDraw(Str* s, I32 x, I32 y, U32 color);

// IME
U0  IMEFeedKey(U8 key);            // two-beol state machine
Str* IMECommitBuffer();

// Render
U0  RndrFrameBegin();
U0  RndrDrawMesh(Mesh* m, Mat4* xf, U32 color);
U0  RndrPresent();                 // scale to screen

// Physics
U0  PhysWorldStep(F64 dt);         // one fixed step
U32 PhysSpawnBody(U8 shape, Vec3 pos, F64 mass);
U0  PhysApplyForce(U32 id, Vec3 f);
U0  PhysSetGravity(Vec3 g);

// Events
U0  EventEmit(Event e);
U0  EventProcessPhase();           // immediate + deferred

// Cards
CardDef* CardById(U32 id);
U0  CardPlay(U32 hand_index, U32 target);
U0  EffectRun(EffectOp* ops, U8 n, Ctx* c);

// Combat
U0  CombatStart(U32 enemy_id);
U0  CombatPlayerPhase();
U0  CombatPhysicsPhase();

// Narrative
U0  DSLRunScene(U16 scene_id);
U0  DlgChoice(U8 option_index);
U0  SchedAdvance(GameTime t);
U0  MsgDeliver(U32 msg_id);

// Save
U0  SaveWrite(U8 slot);
U0  SaveRead(U8 slot);

// Tools
U0  ToolToggle();
U0  ReplayStart();
```

All APIs are explicit, no hidden globals except the single RNG and the single event
queue (documented).

---

## 35. Update/game-loop architecture

```
Main:
  CoreInit(); LoadStrings(); BuildFont();
  if save exists: SaveRead(slot) else NewGame(seed);
  while running:
    dt = TimingAccumulate();           // TSC-based
    InputPoll(); IMEFeedKey if typing;
    switch (mode):
      MODE_EXPLORE:  PlayerMove(dt); PhysStepIfAwake(); RenderWorld();
      MODE_DIALOGUE: DSLRunStep(); RenderDialogue();
      MODE_COMBAT:  CombatTick();     // turn-based; physics in bursts
      MODE_MENU:    ...
    ToolOverlayIfOn();
    RndrPresent();
    ReplayRecordTick();                // append inputs/events
```

Combat is **turn-based**, not real-time: player input → `EventProcessPhase` →
`CombatPhysicsPhase` (fixed bursts) → enemy phase → cleanup. The outer `while` still
runs for rendering/input; simulation only advances on player action or explicit step,
keeping determinism.

---

## 36. Memory-management strategy

- **Pools, not malloc churn.** `FixedPool<T>` for bodies (64), entities (64), events
  (1024), particles. Pre-allocated at boot. `id` indexes the pool slot; `alive` flag.
- **Strings:** our token strings are fixed/known at build; store in a read-only table.
  Dynamic text (IME buffer, debug) uses small ring buffers.
- **No GC.** Manual `Free` for the few dynamic allocs (DSL parse trees, loaded scene).
  Free on scene unload.
- **Save/load** writes flat structs; no pointers cross the boundary (ids only).
- **Fragmentation:** avoid by fixed pools + arena for per-frame temp.

---

## 37. Performance budgets

Target: 320×240 internal, ~20–30 FPS on TempleOS (it's a toy OS; be realistic).
- Render: ≤ ~10k triangles/frame (tiny rooms). Z-buffer 320×240×8B ≈ 614KB OK.
- Physics: ≤ 64 bodies, ≤ 8 steps/burst, ≤ 1 burst/turn in combat; negligible.
- Events: ≤ 256/phase.
- Strings: ≤ a few hundred tokens per screen.
- Save file: ≤ ~32 KB.
- Audio: ≤ 256 KB total samples.
If FPS too low: drop to 240×160, disable textures, disable fog.

---

## 38. Content pipeline

- **Authoring (host):** write DSL scenes in a normal editor; write Korean in Unicode.
  A small Python/Perl build step decomposes Unicode Hangul → our jamo-triple token
  stream and packs strings into `strings.ssg`. Cards defined as DSL/data → `cards.ssg`.
- **Glyphs:** hand-author jamo bitmaps (small) in a tool, emit `Font.HC` data.
- **Meshes:** tiny primitives generated in code (box, plane, sphere, simple characters
  as billboards). No external model format needed v1.
- **Build:** concatenates data files; HolyC compiles `Main.HC` which `#include`s
  modules. No Make needed beyond TempleOS `Compile`/`MkDir`.
- **Iteration:** change a `.ssc` scene → reload in-game via debug command, no recompile
  of engine.

---

## 39. Testing strategy

No unit-test framework in TempleOS; instead:
- **Host-side tests (Python/C):** test pure logic ported 1:1 — RNG determinism,
  Hangul decompose/compose round-trip, effect interpreter on sample cards, scheduler
  ordering, utility AI tie-break. Keep these algorithms identical to HolyC.
- **In-game self-tests:** a debug command `/selftest` runs scripted battles with fixed
  seed and asserts final state hash equals expected. 
- **Replay diff:** record a session, replay, assert hash equality (catches
  nondeterminism).
- **DSL fuzz:** parse random valid-ish scripts, ensure no crash / infinite loop.
- **Physics sanity:** drop a sphere, assert it rests at expected y within epsilon.
- **Content lint:** every DSL `goto` target exists; every card id referenced exists.

---

## 40. Example card definitions

(Format: type / cost / Korean rules / implementation / physics / upgrade / flavor.)

**의자 투척 (Chair Throw)** — type 공격/물리; cost 1.
- 규칙: "의자를 소환하고 전방으로 던진다. 충돌 속도에 비례해 피해."
- 구현: emit `SPAWN_BODY(sphere, player_anchor)` + `APPLY_FORCE(forward * 12)`.
  Physics phase computes collision impulse → `DEAL_DAMAGE` scaled.
- 물리: yes (sphere body, impulse).
- 강화: force 12→18, cost 1→0 if 던진 의자 hits. flavor: "회의실 의자, 최고의 무기."
- flavor: "퇴근은 언제쯤일까."

**야근 (Overtime)** — type 기술/과로; cost 0.
- 규칙: "체력 3 소모. 기력 2 얻음. 커피컵 하나 소환."
- 구현: `STAT hp -3`, `ENERGY +2`, `SPAWN_BODY(small cup)`.
- 강화: 체력 -2, 기력 +3. flavor: "시간은 돈, 잠은 나중."

**코드 리뷰 (Code Review)** — type 기술; cost 1.
- 규칙: "적의 다음 카드 의도를 드러내고, 그 카드 피해를 50% 감소."
- 구현: set flag `REVEAL_INTENT` + `STATUS(enemy, WEAKEN_INTENT,1)`.
- 강화: 70% 감소 + draw 1. flavor: "주석 하나도 놓치지 않는다."

**눈치 보기 (Reading the Room)** — type 사회; cost 1.
- 규칙: "눈치만큼 적의 숨은 의도를 드러냄. [눈치≥6] 추가로 선택지 해금."
- 구현: `REVEAL_INTENT`, if nunchi≥6 emit `UNLOCK_CHOICE`.
- 강화: also +1 인맥. flavor: "과장님 표정이 심상치 않다."

**책임 전가 (Blame Shift)** — type 사회/저주; cost 2.
- 규칙: "내게 걸린 BLAME를 적에게 전가. 적이 상급자면 비용 +1."
- 구현: move `BLAME` status from player to target (scaled by rank diff).
- 강화: also -적 신뢰. flavor: "제가 받은 메일에는 그렇게 적혀 있었는데요."

**퇴근 (Clock Out)** — type 특별; cost 3, 소모.
- 규칙: "탈출 가능한 출구가 있으면 이 전투를 즉시 종료하고 도망."
- 구현: if scene has `exit` anchor → `END_BATTLE(escape)`.
- 강화: cost 2. flavor: "드디어."

**메모리 누수 (Memory Leak)** — type 저주/시스템; cost 1, 소모.
- 규칙: "적에게 매 턴 고정 피해를 주지만, 나도 기력 최대 -1 (전투 끝까지)."
- 구현: `STATUS(enemy, LEAK_DOT, 2)` + `STATUS(self, ENERGY_CAP_-1, combat)`.
- 강화: 피해 2→3. flavor: "free()는 언제 하나."

**사직서 (Letter of Resignation)** — type 전설/특별; cost 0, 소모.
- 규칙: "제출한다. 캠페인 종료 분기로 직행. 관계/플래그에 따라 엔딩 결정."
- 구현: `END_CAMPAIGN(resign)` → DSL ending router.
- 강화: 없음 (전설). flavor: "더 이상은 못 하겠습니다."

---

## 41. Example combat encounter

**복사기 악령 (Copier Wraith), 4F.**
- HP 28, block 0, rank 인턴(low).
- Intent turn 1: `SPAWN_BODY(paper AABB x2)` near player path.
- Intent turn 2: `APPLY_FORCE` shove papers at player (small dmg if collide).
- Intent turn 3: `DEAL_DAMAGE 6` (paper cut) unless player cleared bodies.
- Player counter: throw 의자 (의자 투척) to destroy paper bodies (collision →
  destroy + dmg to wraith). Use 코드 리뷰 to weaken its turn-3 hit.
- Win: reward card (e.g., 메모리 누수) + flag `BEAT_COPIER`.
Physics note: paper AABBs are light; chair sphere impulse destroys them (collision
handler: if impulse > threshold and body.tag==paper → `DESTROY_BODY` + splash dmg).

---

## 42. Example dialogue scene in Korean

```
scene break_room
bg break_night
music hum_01

kim:
  say kim "야, 아직 안 갔어?"
  choice:
    "네, 조금만 더 하려고요." -> stay
    "저 이제 가려고요." -> leave
    [nunchi >= 6] "과장님, 왜 아직 여기 계세요?" -> reverse

stay:
  stat hp -2
  stat performance +1
  card add "야근"
  msg kim "수고해ㅋ" on_read end
  goto end

leave:
  flag set LEFT_EARLY
  rel kim favor -1
  goto end

reverse:
  say kim "[숨은 의미: 나도 못 가, 박과장이 붙잡았어]"
  rel kim trust +1
  flag set KIM_TRAPPED
  goto end

end:
  return
```

---

## 43. Example scheduler sequence

Day 3, 23:48: 김부장 message scheduled (`MSG`). Day 4, 09:00: 인사평가 안내
(`FLAG REVIEW_SOON`). Day 4 evening: player picks "알고리즘 공부" →
`TIME_ADVANCE +180`, `STAT spec +1`, `STAT wlb -1`, enqueue `INTERVIEW_OFFER` on day 7.
Day 5: if `REVIEW_SOON` and performance low → blame event auto-added. The scheduler
viewer shows all three; the player sees the conflict (study vs rest vs review prep).

---

## 44. Example relationship consequence

Player helps 정인턴 with a side task (dialogue option). Effects: `rel jung favor +2`,
`rel jung debt -1` (they owe you), `flag HELPED_INTERN`, schedule `jung_leak_info` on
day 6 if `favor>=2`. Later, during blame event, if `jung.debt<=-1` and `jung.favor>=2`,
정인턴 auto-redirects one BLAME away from player (AI utility picks "protect" because
need `protect_subordinate` high + debt). This is emergent from the model, not
hardcoded per scene.

---

## 45. Example physics-card interaction

Player plays **책상 뒤집기 (Flip Desk)** (type 물리, cost 2):
- Emit `SPAWN_BODY(AABB desk, player_anchor)`.
- Emit `APPLY_FORCE(torque/impulse upward+forward 20)`.
- Physics burst: desk tumbles, collides with enemy body → impulse 18 →
  `DEAL_DAMAGE` 14 (table in §11). Loose papers (from earlier 복사기) become hazards
  (status `HAZARD` on tiles). 
- Next turn, `정리정돈` could freeze these (sleep bodies) and convert their summed KE
  into Block. All via events; fully replayable.

---

## 46. Example DSL script

(See §42 for dialogue; here a combat+world script.)

```
scene boss_juin
bg dev_night
spawn enemy "주임_악령" at 4F_center
load_scene 4F_dev
music boss_01

start:
  combat_start "주임_악령"
  wait 500
  say juin "자료, 언제 나와요?"
  choice:
    "지금 마무리합니다." -> promise
    [balls >= 5] "그건 과장님 몫 아닌가요?" -> push

promise:
  stat performance +1
  rel juin trust -1
  flag set PROMISED
  goto end

push:
  stat balls_check
  rel juin suspicion +2
  card add "책임 전가"
  goto end

end:
  return
```

---

## 47. Example replay log

```
REPLAY v1
SEED 0x9e3779b97f4a7c15
INIT_HASH 0x1a2b3c4d
INPUT t=1 CARD_PLAY hand=3 target=enemy0      # 의자 투척
INPUT t=1 PHYS_BURST steps=8
INPUT t=1 CHOICE idx=0
INPUT t=2 CARD_PLAY hand=1 target=self        # 야근
INPUT t=2 SCHEDULE evening=study
...
FINAL_HASH 0x77de
```
Replay re-runs: same seed + inputs → same FINAL_HASH. Divergence → desync log:
`DESYNC at t=2: expected hp 18 got 20 (phys impulse mismatch)`.

---

## 48. Milestone roadmap

Improved from the prompt's phased plan. Each phase has **entry criteria**, **work**,
and **exit/done criteria**.

### Phase 0 — HolyC reconnaissance
- Entry: empty TempleOS env.
- Work: files R/W, TSC timing, keyboard scancode read, draw pixels/rects, string
  print, MAlloc sanity.
- Done: a program that draws text, reads keys, times a loop, writes/reads a file.

### Phase 1 — Korean text
- Work: Hangul decompose/compose, jamo font, layout, dialogue-box render, basic IME.
- Done: type "한글" via two-beol; render a paragraph; name-corruption flaw works.

### Phase 2 — 2D card prototype
- Work: CardDef data, piles, effect interpreter, turn loop (text-only), statuses,
  simple enemy, win/lose. No 3D.
- Done: a full card battle in text/2D proving the data model + effect system.

### Phase 3 — 3D renderer
- Work: math, camera, triangle clip/raster, z-buffer, flat shading, one office room,
  billboard characters.
- Done: walk a 3D room at 320×240; looks crunchy but correct.

### Phase 4 — physics
- Work: RigidBody, plane/sphere/AABB, broad+narrow, impulse solver, sleeping, gravity.
- Done: drop/spawn chairs; they collide and rest deterministically; debug collider viz.

### Phase 5 — physical card combat
- Work: wire cards→events→physics bursts; collision→damage; gravity/panic cards.
- Done: 의자 투척 and 책상 뒤집기 visibly affect a battle deterministically.

### Phase 6 — dialogue
- Work: DSL parser/interp, dialogue boxes, choices, 눈치 reveals, stat/rel effects,
  combat transition.
- Done: the §42 scene plays; choices change state and can start combat.

### Phase 7 — campaign state
- Work: calendar/time, scheduler queue, relationships graph, messenger, save/load.
- Done: time advances; scheduled event fires; save round-trips; messenger arrives.

### Phase 8 — DSL
- Work: move all Phase 6/7 content into `.ssc` scripts; campaign progression by flags;
  hot-reload in debug.
- Done: zero campaign logic hardcoded in engine; everything data-driven.

### Phase 9 — vertical slice
- Work: integrate all into one floor (§49). 
- Done: full loop end-to-end with save+replay.

### Phase 10 — content expansion
- Work: build Acts II–IV, NPCs, bosses, endings, music, tools polish.
- Done: a completable campaign with multiple endings.

---

## 49. Vertical-slice definition

One floor: **4F 개발1팀** (small: 1 open room + 1 meeting room + hallway).

Must work:
- 3D walkable room + camera.
- Korean rendering of all text + simple IME for naming/one input.
- ~15–20 cards implemented (the §40 set + a few more).
- Deck editing screen (add/remove from collection).
- One dialogue-heavy coworker (김대리) with 눈치 options.
- One messenger event (김부장 23:48 ping).
- One ordinary enemy (복사기 악령) — physics-light.
- One physics-heavy enemy (의자/책상 encounter).
- One boss (주임 악령) with meeting/blame mechanics.
- One scheduled evening choice with consequence.
- One relationship consequence (help intern → later favor).
- One save file (round-trip).
- One replayable combat (seed+inputs → same result).
- One mystery clue (a name that can't render → flag).

Exit: a player can boot, explore, talk, fight with physics, make an evening choice,
save, reload, and replay a fight identically.

---

## 50. MVP definition

Strictly smaller than the slice: **Phase 2 + Phase 1 minimal**. Text-mode (or
bitmap-text) card battle with Hangul, a few cards, one enemy, RNG seeded, save of
stats. Proves the *core fun* (cards + Korean + deterministic) before any 3D/physics.
If the MVP isn't fun, the rest is pointless; this de-risks early.

---

## 51. Post-MVP expansion plan

After slice:
- Acts II–IV content (DSL only).
- More cards (→180), enemies, bosses.
- 회식 social dungeon (§13/§12 social meter).
- Audio layer.
- Texture support (optional), fog, dither.
- Tooling polish (replay diff UI, scene editor-lite).
- Endings router + relationship-dependent variation.
- The Hangul-corruption mystery payoff (최부장's daughter).

---

## 52. Features explicitly deferred or cut

- **Networking / multiplayer / cloud** — never.
- **OBB / capsule / convex-hull physics** — until a real need (maybe Act IV).
- **General Unicode** — only Hangul + ASCII + needed punctuation.
- **Skeletal animation** — billboards/sprites only.
- **PBR / GI / post-processing** — flat shading only.
- **Multithreading** — single thread; physics bursts are cheap.
- **Full modern IME parity** — two-beol only, no full compound edge cases beyond
  common ones.
- **Advanced audio synthesis** — samples/blips only.
- **ECS framework** — fixed pools + structs, not an ECS.
- **Arbitrary large worlds** — small dense rooms only.

---

## 53. Biggest technical risks

1. **Determinism leaks** from floating-point (F64) across TempleOS builds / order of
   operations in physics. Mitigation: fixed-step, ordered event processing, hash
   checks, avoid `==` on floats (epsilon), prefer fixed-point where safe.
2. **Renderer performance** at 320×240 in pure HolyC. Mitigation: tiny tris, culling,
   optional lower res, no textures first.
3. **Memory fragmentation / leaks** in a no-GC env. Mitigation: pools, arenas,
   disciplined Free.
4. **DSL complexity creep** (becomes a real language). Mitigation: hard scope, no
   loops/functions, visited-set guard.
5. **Physics making combat unwinnable/unfair.** Mitigation: physics damage is
   thresholded + readable; player can always fall back to non-physics cards.

## 54. Biggest design risks

1. **Joke without weight** — comedy that never lands emotionally. Mitigation: pillars
   #1; relationship arcs; the resignation/escape theme.
2. **Systems bloat** — every stat/social mechanic feeling inert. Mitigation: each stat
   has a distinct role (§8); social choices have visible, replayed consequences.
3. **Korean culture as caricature.** Mitigation: satire targets structures
   (눈치, 압박, 회식) not people; sympathetic + rejecting NPCs both present.
4. **Metafiction as cheap fourth-wall.** Mitigation: mechanics-first (replay,
   Hangul) revealed as in-world, not winks.
5. **Scope collapse** — trying everything at once. Mitigation: the phased roadmap +
   vertical slice gate.

## 55. Risk mitigations (summary)

- Determinism by construction + replay hashing (catches leaks early).
- Fun validated at MVP (text cards) before 3D/physics investment.
- Pools/arenas for memory safety.
- DSL hard-scoped; linter prevents dangling gotos.
- Culture reviewed against the "structures not people" rule.
- Physics damage gated so it never replaces player agency unfairly.

---

## 56. Recommended implementation order

0 → 1 → 2 (MVP fun check) → 3 → 4 → 5 → 6 → 7 → 8 → 9 (slice) → 10.

Do **not** parallelize engine subsystems blindly; dependencies: math→render;
Hangul→dialogue; events→everything; RNG→replay→all. But content (DSL scenes) can be
authored in parallel with engine once §8 lands.

---

## 57. Definition of "done"

The project is done when:
- A player can boot 성광정보기술 in TempleOS.
- Explore 3D floors, render Korean, type via IME.
- Build a deck, fight turn-based physics card battles deterministically.
- Hold dialogues with 눈치/hierarchy effects, messenger, relationships.
- Advance a calendar with real trade-offs.
- Reach Act IV and pick among ≥5 endings.
- Save/load and replay any combat identically.
- Use debug tools to inspect state.
- The Hangul-corruption and replay-as-surveillance mysteries pay off.

---

## 58. Final repository README-style pitch

The game is titled **퇴근** ("Clock Out"). The player's employer remains the
fictional company **성광정보기술** (Sungwang Information Technology).

```
# 퇴근 (Toegeun / "Clock Out")

A Korean 3D deckbuilding office RPG, written from scratch in HolyC for TempleOS.

You are a junior engineer at 성광정보기술 who wakes at 3:17 AM. Everyone is gone.
The building is impossible. Your job is now a dungeon, your manager is a boss fight,
and the only way out might be a letter of resignation -- or becoming the administrator.

Features:
- Custom software 3D renderer (320x240, crunchy, z-buffered)
- Minimal deterministic rigid-body physics (chairs are weapons)
- Hand-built Hangul renderer + two-beol IME (with one deliberate flaw)
- Turn-based deckbuilding combat where cards throw furniture
- Office-politics simulation: 눈치, 직급, 압박, blame/credit, relationships
- Dialogue/campaign DSL so the whole story is data, not code
- Deterministic replay that becomes the in-world surveillance system
- A calendar, messenger, and branching campaign about trying to leave work

"This is not a dream. It is a performance review."

## Build
Open in TempleOS. Compile Main.HC. Run.

## Controls
Arrows/WASD: move. Enter: confirm. F1: debug overlay. Han/Eng: IME toggle.

## Status
Phased build. See docs/roadmap. Vertical slice: 4F 개발1팀.
```

---

### Closing note for the builder

The single most important discipline: **keep every system deterministic and
event-driven from day one.** It is what makes TempleOS debugging survivable, makes
replay a real feature instead of a science project, and makes the metafiction land as
mechanics rather than jokes. Build the MVP (text cards + Korean + seed) first; if that
isn't fun, nothing downstream matters. Then earn the 3D and physics one phase at a
time. The weirdness is the point, but the *finish* is the achievement.

# 퇴근 (Toegeun / "Clock Out")

*A Korean 3D deckbuilding office RPG, built from scratch baby.*

This repository is the
**engine + vertical slice**, implemented in portable C that is 1:1 with the
HolyC/TempleOS design (same structs, event model, determinism rules). The plan
document lives at `masterplan.md`.

Premise: The player is a junior engineer at **성광정보기술** who wakes at 3:17 AM. The
building is impossible. Your job is now a dungeon, your manager is a boss fight,
and the only way out might be a letter of resignation -- or becoming the
administrator.

<p align="center"> <img src="assets/shots/reel.gif" width=85%> </p>


## 퇴근

퇴근은 순수 C로 처음부터 만든 한국식 3D 덱빌딩 오피스 RPG다.
플레이어는 성광정보기술의 주니어 엔지니어로, 새벽 3시 17분에 눈을 뜬다.
건물은 비뚤어졌고, 출근길은 던전이 되었고, 과장님은 보스전이 된다.
유일한 출구는 사직서 -- 혹은 관리자가 되는 것.

## Visuals

The engine renders every frame itself (`make shots` / `make gif`): a 320x240
software rasterizer with a dancheong night palette (16 오방색 hue columns x 16
luminance steps), per-face Lambert shading against moonlight, and view-depth fog
that swallows the far end of the office into 3:17 AM darkness.

| Scene | Clip |
|---|---|
| Title | ![타이틀](assets/shots/title.gif) |
| Office dialogue | ![대화](assets/shots/dialogue.gif) |
| Choice | ![선택](assets/shots/choice.gif) |
| Combat | ![전투](assets/shots/combat.gif) |
| Boss | ![보스전](assets/shots/boss.gif) |
| Game over | ![게임오버](assets/shots/gameover.gif) |

Run `make shots` to capture stills, then `make gif` to assemble the animated
clips above into `assets/shots/*.gif`.

## Renderer style (단청 night)

The painter uses a HUE+step palette contract instead of raw indices
(`render/render.H`): every color is *색 × step*, so shading and fog can move a
face brighter or darker within its own hue without ever hue-shifting. Faces
facing the moonlight lift toward LIT; faces turned away fall to a dark ambient
floor; distant geometry sinks toward night via perspective-correct depth fog.
Level art leans on the traditional painted-wood scheme: 청 teal dividers,
목 brown desks, 황 gold light, 홍 vermilion boss, 남 indigo night.

## What is implemented

| Subsystem | Module | Status |
|-----------|--------|--------|
| Math / RNG / events / strings | `core/` | done (seeded xorshift, event queue, UTF-8→jamo tokenizer) |
| Hangul compose + font + two-beol IME | `korean/` | done (jamo bitmaps, syllable composition, deliberate corruption flaw) |
| Software 3D renderer | `render/` | done (320×240, z-buffer, Lambert shading, depth fog, dancheong palette, PPM output, wireframe) |
| True-color UI compositor | `render/ui.` | done (RGBA overlay over the palette scene, Hangul/Latin text, panels, bars, cards, baked sprites) |
| Rigid-body physics | `physics/` | done (pool of 64, sphere/AABB/plane, sequential impulses, sleeping) |
| Cards / combat / statuses / AI | `game/` | done (data-driven cards, effect interpreter, deterministic turn loop) |
| DSL / scheduler / relationships / messenger / campaign | `narrative/` | done (colon-style scene scripting, time queue, NPC state) |
| Content (20 cards, 2 scenes, tools) | `content/`, `tools/` | done |

The integration test (`tests/integration_test.c`) proves end-to-end:
Korean glyph composition, IME typing, renderer framebuffer, **physics
determinism**, **combat determinism (replay-safe)**, a thrown chair dealing
damage to the enemy through the physics bridge, DSL scene with a 눈치-gated
choice, scheduler firing, and save/load round-trip.

## Build & test

```
make check
```

Requires a C99 compiler (`cc`/`clang`/`gcc`). All suites print PASS.

## Architecture notes

- **Everything is event-driven and deterministic.** One seeded RNG, fixed-step
  physics bursts, stable object ids, ordered event processing. This is what makes
  TempleOS debugging survivable and makes the replay infra a real feature.
- **Physics↔combat bridge:** cards emit `SPAWN_BODY`/`APPLY_FORCE` (never poke
  the world directly). Collision impulses become `DEAL_DAMAGE` events routed to
  the correct combatant via the body `owner` entity id.
- **HolyC port:** the logic here ports mechanically. Only the graphics/input/file
  shims (TempleOS `gr`, scancode, `FileRead`) and `<math.h>`/`<stdio.h>` differ;
  the structs, function signatures, and algorithms are identical.

## Not yet built

Networking, convex-hull physics, full Unicode, skeletal animation, PBR,
multithreading, ECS. The full 4-act campaign content (Acts II–IV, all NPCs,
multiple endings) is data authoring on top of the DSL - the engine supports it.

## 한국식 오피스 픽셀 아트

The character and interior art bundled with this repo is not original engine
output. It is included for local development and README preview only.

- **LimeZu** - Modern Office and Modern Interiors (characters), at
  [limezu.itch.io](https://limezu.itch.io).
  Commercial use is allowed, reselling the raw assets is not, and credit is
  appreciated (required on some packs).
- **Kenney** - UI, icons, playing cards, particle pack, and fonts, at
  [kenney.nl](https://kenney.nl).
  Released under CC0 (public domain, no attribution required).
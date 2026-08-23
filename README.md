# 퇴근 (Toegeun / "Clock Out")

A Korean 3D deckbuilding office RPG, built from scratch. This repository is the
**engine + vertical slice**, implemented in portable C that is 1:1 with the
HolyC/TempleOS design (same structs, event model, determinism rules). The plan
document lives at `../sungwang_masterplan.md` (or `masterplan.md` if copied here).

The player is a junior engineer at **성광정보기술** who wakes at 3:17 AM. The
building is impossible. Your job is now a dungeon, your manager is a boss fight,
and the only way out might be a letter of resignation -- or becoming the
administrator.

## What is implemented

| Subsystem | Module | Status |
|-----------|--------|--------|
| Math / RNG / events / strings | `core/` | done (seeded xorshift, event queue, UTF-8→jamo tokenizer) |
| Hangul compose + font + two-beol IME | `korean/` | done (jamo bitmaps, syllable composition, deliberate corruption flaw) |
| Software 3D renderer | `render/` | done (320×240, z-buffer, flat shading, PPM output, wireframe) |
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

## Not yet built (per the plan's deferral list)

Networking, convex-hull physics, full Unicode, skeletal animation, PBR,
multithreading, ECS. The full 4-act campaign content (Acts II–IV, all NPCs,
multiple endings) is data authoring on top of the DSL — the engine supports it.

# 퇴근 (Toegeun / "Clock Out")

*Premise.*
You are a junior engineer at 성광정보기술 who wakes at 3:17 AM to a building that will not let you leave.

The commute is a dungeon, your manager is a boss fight (like in IRL), and the only exits are a letter of resignation or a coup that puts you in charge.

The project runs on a hand-written 640x360 software renderer and a deterministic combat engine.
A playable macOS slice now connects one office, two battles, a deck reward, and an ending.

## Play the night

Install SDL2 with `brew install sdl2`, then run `make play` from the repository root.
The build uses the installed `sdl2-config` and a C compiler.
No Python or original source packs are needed to play with the bundled baked assets.

| Action | Keyboard | Controller |
|---|---|---|
| Select office hotspot, response, or card | Arrows or WASD | D-pad |
| Inspect / confirm / use card | Enter or E | A |
| End turn | Space | Y |
| Back / pause / resume | Escape | B |
| Pause / resume anywhere | | Start |
| Fullscreen | F11 | |
| Freeze animated effects | F2 | |
| Mute selection cues | F3 | |
| Quit | Close the window | |

Window focus loss or disconnection of the active controller pauses play.
Keyboard controls remain available when no controller is connected.
Fullscreen preserves the 640x360 image with integer scaling and letterboxing.
For reduced motion, press F2; this setting survives retry within the session.

Explore by selecting one of four named hotspots, rather than freely walking.
Talk to 김대리 before approaching the copier.
Inspecting the attendance record raises 눈치 to 6 and exposes enemy intent.
It also unlocks a response to 박과장 that removes 24 of his 100 HP and weakens his first two actions.
The copier's reward adds exactly one card to the deck; remaining HP carries into the manager fight.
Chairs resolve their physical collision damage when the turn ends.
Defeat and victory both offer a fresh start.
There is no save file in this slice.

The story and card selection are deliberately small.
Messenger, scheduling, the larger relationship simulation, free movement, and the four-act campaign are not wired into this playable night.
The sections and GIFs below describe the older presentation gallery and the wider engine.

<p align="center"> <img src="assets/shots/reel.gif" width=85%> </p>

## 퇴근

퇴근은 한국식 3D 덱빌딩 오피스 RPG다.
플레이어는 성광정보기술의 주니어 엔지니어로, 새벽 3시 17분에 눈을 뜬다.
건물은 비뚤어졌고, 출근길은 던전이 되었고, 과장님은 보스전이 된다.
출구는 사직서 하나, 아니면 관리자가 되는 것.

## The wider design

You explore the impossible office between encounters. The building rearranges itself after hours, as if the floor plan also hates overtime.
Dialogue scenes serve up 눈치 (nunchi) choices: the socially aware line only appears when your read of the room is high enough. Say the wrong thing and enjoy the consequences.
The campaign model tracks the scheduler, relationships, and work-life balance. These stats shape each run's outcome: triumph, burnout, or one more "quick" meeting.
Combat is deterministic. Cards telegraph intent, physics weapons like a thrown chair resolve through the same impulse solver as the world, and status effects stack in a fixed turn order. No dice, no excuses. Just consequences.
The reward screen presents your planned post-combat deck choice, because even survival comes with paperwork.
The boss is the manager, and beating them is the whole point of the slice.

The ten clips below are historical scripted captures of the presentation screens, not recordings of the new playable input loop.
Think of them as the original elevator pitch, with your manager waiting between floors.
Each screen draws real engine state onto the 640x360 renderer.

## Visuals

Ten scripted captures, one per screen, from the title screen to defeat.

<table>
<tr>
<td align="center" width="50%"><img src="assets/shots/title.gif" width=90%><br><sub>Title screen over a still night-office diorama.</sub></td>
<td align="center" width="50%"><img src="assets/shots/explore.gif" width=90%><br><sub>Exploration screen over the shifting after-hours office.</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/shots/dialogue.gif" width=90%><br><sub>A scene with the nameplate and an advance prompt.</sub></td>
<td align="center"><img src="assets/shots/choice.gif" width=90%><br><sub>A 눈치-gated choice list where some options stay locked.</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/shots/messenger.gif" width=90%><br><sub>Inbox messages arriving from coworkers and the boss.</sub></td>
<td align="center"><img src="assets/shots/schedule.gif" width=90%><br><sub>The day planner trading rest against deadlines.</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/shots/combat.gif" width=90%><br><sub>Card hand, energy strip, and a physics weapon in flight.</sub></td>
<td align="center"><img src="assets/shots/reward.gif" width=90%><br><sub>The reward screen offering a new card.</sub></td>
</tr>
<tr>
<td align="center"><img src="assets/shots/boss.gif" width=90%><br><sub>The manager encounter with telegraphed intent.</sub></td>
<td align="center"><img src="assets/shots/gameover.gif" width=90%><br><sub>Defeat, or the stiff 사직 ending.</sub></td>
</tr>
</table>

## Renderer style (단청 night)

The whole frame is drawn by a native 640x360 software rasterizer.
Colors come from a dancheong-night palette built as hue times step. Every face uses a color at a luminance level, so shading and fog move it brighter or darker within the same hue.
Faces catch moonlight through Lambert shading, and view-depth fog pulls the far office into 3:17 AM dark.
A true-color RGBA overlay carries the Hangul and Latin UI, panels, bars, and baked sprites on top of the palette scene.
Korean text is composed live from jamo bitmaps into syllables, and character art is baked from third-party pixel packs into engine sprites.

## Mechanics

The current code has two clear parts: implemented engine behavior and presentation-only screens.

### Implemented engine behavior

- Deterministic intent telegraphs: enemies declare their next action, while enemy reveal status or high nunchi exposes its exact type and value.
- Block and status effects: damage hits block before HP, and statuses stack with turn lifetimes on each combatant.
- Retain and exhaust piles: cards flagged retain skip the discard, and spent cards can move to an exhaust pile.
- Energy and HP drive combat, while the campaign state carries focus, nunchi, and work-life balance for scenes to spend.
- Nunchi-gated dialogue: DSL scene choices carry stat guards, so some options only appear when your read of the room is high enough.
- Scheduler, messenger, and relationships: a time-ordered scheduler fires scenes, an inbox delivers messages, and NPCs track eight relationship fields.
- Campaign flags: an act and flag state machine records story progress across scenes.
- Physics weapons: cards emit spawn-body and apply-force events, so a thrown chair deals damage through the same impulse solver as the world.

### Legacy presentation screens

The title, exploration, dialogue, choice, messenger, schedule, combat, reward, boss, and game-over screens live in `render/ui_app.H`.
They draw real card and combat state plus authored presentation data onto the 640x360 renderer.
The macOS host uses `render/slice_ui.HC` and `game/slice.HC` instead of driving this gallery.
The old messenger and schedule screens remain authored presentation data rather than live game flow.

## What is implemented

| Subsystem | Module | Status |
|-----------|--------|--------|
| Playable night | `game/slice.HC`, `render/slice_ui.HC` | title, hotspot exploration, clue, dialogue, two battles, reward, ending, pause and retry |
| macOS host | `tools/play.HC` | SDL2 window, integer scaling, keyboard, controller hotplug, queued audio |
| Math / RNG / events / strings | `core/` | done (seeded xorshift, event queue, UTF-8 to jamo tokenizer) |
| Hangul compose + font + two-beol IME | `korean/` | done (jamo bitmaps, syllable composition, deliberate corruption flaw) |
| Software 3D renderer | `render/` | done (640x360, z-buffer, Lambert shading, depth fog, dancheong palette, PPM output, wireframe) |
| True-color UI compositor | `render/ui.H` | done (RGBA overlay over the palette scene, Hangul/Latin text, panels, bars, cards, baked sprites) |
| Game-flow compositor / screens | `render/ui_app.H` | done (title, exploration, dialogue, choice, messenger, schedule, combat, reward, boss, game-over screens; compositor demos over engine state, no input loop yet) |
| Rigid-body physics | `physics/` | done (pool of 64, sphere/AABB/plane, sequential impulses, sleeping) |
| Cards / combat / statuses / AI | `game/` | done (data-driven cards, effect interpreter, deterministic turn loop) |
| DSL / scheduler / relationships / messenger / campaign | `narrative/` | done (colon-style scene scripting, time queue, NPC state) |
| Content (20 cards, 2 scenes, tools) | `content/`, `tools/` | done |
| 10 GIF capture pipeline | `tools/shot.HC`, `tools/asm_gif.py` | done (captures frames, assembles the reel and ten clips) |

The integration test (`tests/integration_test.HC`) checks the engine end to end.
Korean glyph composition, IME typing, renderer framebuffer, **physics
determinism**, **combat determinism (replay-safe)**, a thrown chair dealing
damage to the enemy through the physics bridge, DSL scene with a 눈치-gated
choice, scheduler firing, and save/load round-trip.
It is a headless engine test over the implemented subsystems. It does not launch a playable application.

## Build and test

```
make check
```

Requires a C99 compiler (`cc`/`clang`/`gcc`). All suites print PASS.

`make check-slice` runs the targeted playable-state tests.
They cover both dialogue paths, real combat victories, deterministic replay of inputs, defeat, retry, pause, reward uniqueness, locked exits, and read-only rendering.
They also capture eleven playable screens to `/tmp/clockout-slice-*.ppm` and compare host RGB output against the PPM compositor.
Every gallery capture follows legal game inputs, so boss health, carried cards, and the observed clue match the playable journey.

`make bin/clock-out && bin/clock-out --smoke` runs a bounded native-window journey from title to exit through injected SDL keyboard events.
It exits automatically and closes its own SDL resources.
It does not prove physical controller compatibility or audible sound quality.
`bin/clock-out --help` lists host controls and the smoke option.

There is no separate lint configuration; builds use `-Wall -Wextra`.

## Capture the clips

`make slice-shots` runs the playable tests and uses Pillow to generate all eleven `assets/shots/playable-*.png` images and three GIF reels in the README.
The title, office, attendance clue, coworker, combat, reward, manager response, boss, exit, defeat, and pause screens are all included.
The reels are `playable-office.gif`, `playable-combat.gif`, and `playable-night.gif`.
They animate authored state changes, not continuous movement.
An ignored `bin/slice-contact.png` lets you inspect the entire gallery at once.
Install Pillow with `python3 -m pip install Pillow` if it is not already available in your Python environment.

The original scripted GIF gallery can still be regenerated separately:

```
make gif
```

`make gif` captures the frames and assembles them into `assets/shots/*.gif`,
including `reel.gif` and the ten clips shown above.

## Architecture

- Everything is event-driven and deterministic. One seeded RNG, fixed-step physics bursts, stable object ids, and ordered event processing make replays reproducible.
- The physics to combat bridge uses events: cards emit `SPAWN_BODY` / `APPLY_FORCE` and never touch the world directly. Collision impulses become `DEAL_DAMAGE` events routed by the body owner entity id.
- The logic is a 1:1 port of the HolyC/TempleOS design. The graphics, input, and file shims differ, while the structs, signatures, and algorithms stay identical.

The playable state machine accepts discrete `SliceInput` commands and owns transitions and rewards.
The SDL host forwards input and presents a caller-owned RGB frame through `ui_frame_rgb`.
Drawing reads game state without advancing combat or the random stream.
SDL dependencies stay out of the headless engine and test builds.
The `.HC` extension preserves the project's HolyC-flavored source style; macOS executes a C-compiled binary, not the TempleOS HolyC compiler.

## Scope

This slice leaves the following work for later:

- Networking, convex-hull physics, full Unicode, skeletal animation, PBR, multithreading, and an ECS.
- The full campaign, Acts II through IV, every NPC, and multiple endings still need to be authored as DSL data. The engine supports them.
- Free walking, live messenger and schedule integration, save/load for the playable slice, and TempleOS hosting remain unimplemented.
- The third-party character and interior art comes from the credits below. It ships for local development and README preview only.

## Credits

`tools/asset_bake.py` reads `~/Creative/GameDev` by default, or the folder named by `CLOCKOUT_SRC`.
Run it with Python and Pillow only when rebuilding sprites.
It now includes four idle frames for each existing character, with stable feet anchors in the playable compositor.
Office furniture is simple 3D geometry; the LimeZu office packs informed its proportions and details rather than being pasted as top-down sprites into a perspective camera.
`python3 tools/gen_glyphs.py` regenerates the bundled 16px Korean glyph atlas when copy changes.
Original source packs stay outside this repository.
The local Modern Interiors license requires LimeZu credit and prohibits redistribution of the asset pack; verify distribution terms before publishing derived asset bundles.

The character and interior art bundled with this repo comes from the credits below. It is included for local development and README preview only.

- **LimeZu** - Modern Office and Modern Interiors (characters), at
  [limezu.itch.io](https://limezu.itch.io).
  Commercial use is allowed, reselling the raw assets is not, and credit is
  appreciated (required on some packs).
- **Kenney** - UI, icons, playing cards, particle pack, and fonts, at
  [kenney.nl](https://kenney.nl).
  Released under CC0 (public domain, no attribution required).

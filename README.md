# 퇴근

*Toegeun. "Clock Out."*

You are a junior engineer at 성광정보기술 who wakes at 3:17 AM to a building that will not let you leave.
Your manager is a boss fight.
The copier has already printed your name.

<p align="center">
  <img src="assets/shots/playable-title.png" width="88%" alt="Clock Out title over an empty fluorescent-lit office at 03:17 AM">
</p>

한국식 3D 덱빌딩 오피스 RPG.
새벽 3시 17분, 아직 사무실이다.

## Play on macOS

With SDL2 installed, run from the repository root:

```sh
make play
```

One playable night: inspect the office, talk to 김대리, stop the copier, choose a card, confront 박과장, and leave.
Reading the attendance record gives you something concrete to say back.
Keyboard and controller input drive the same deterministic combat engine.

The `.HC` sources and hand-written 640×360 renderer stay.
SDL supplies the macOS window, input, and short audio cues; it does not replace the engine.
This is a fixed-camera, hotspot-driven slice, not the full campaign or a TempleOS runtime.

[Controls, setup, tests, scope, and art credits](GUIDE.md).

## A few seconds inside the office

These short reels use the same playable-state captures as the gallery below.
They follow the actual route through the night, with the attendance clue changing the manager fight.

<p align="center">
  <img src="assets/shots/playable-office.gif" width="49%" alt="Playable reel from the title screen through the fourth-floor office, attendance clue, and coworker conversation">
  <img src="assets/shots/playable-combat.gif" width="49%" alt="Playable reel from copier combat through card reward, manager response, and performance review">
</p>

<p align="center">
  <img src="assets/shots/playable-night.gif" width="88%" alt="Full playable Clock Out night from title screen to victory, defeat, and pause">
</p>

## The night, screen by screen

All eleven overhauled screens are shown here, including the title above.
These are native-resolution captures reached through the playable state machine, with real health, cards, and consequences.

<table>
  <tr>
    <td width="50%"><img src="assets/shots/playable-office.png" alt="Fourth-floor office with selectable attendance record, coworker, copier, and exit"><br><sub>01. Four places to look. One way out.</sub></td>
    <td width="50%"><img src="assets/shots/playable-attendance.png" alt="Attendance record reveals that the manager clocked out at 18:02"><br><sub>02. Someone has already clocked out.</sub></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-coworker.png" alt="Kim asks why the copier keeps printing the player's name"><br><sub>03. A normal request from 김대리.</sub></td>
    <td><img src="assets/shots/playable-combat.png" alt="Copier battle with card costs, selected-card rules, player health, and enemy intent"><br><sub>04. The chair is part of the build.</sub></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-reward.png" alt="Three illustrated card rewards after defeating the copier"><br><sub>05. Survival comes with paperwork.</sub></td>
    <td><img src="assets/shots/playable-response.png" alt="The attendance clue unlocks a response to the manager's accusation"><br><sub>06. This time, you kept the receipt.</sub></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-boss.png" alt="Manager fight reflects the clue's damage and weakened attack, plus carried player health"><br><sub>07. Performance review.</sub></td>
    <td><img src="assets/shots/playable-exit.png" alt="Successful clock-out ending: the clock finally advances to 03:18"><br><sub>08. The clock finally moves.</sub></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-defeat.png" alt="Defeat returns the worker to 03:17 and offers a fresh start"><br><sub>09. Same desk. Same time.</sub></td>
    <td><img src="assets/shots/playable-pause.png" alt="Pause screen with resume, reduced effects, fullscreen, and quit controls"><br><sub>10. A break that actually pauses work.</sub></td>
  </tr>
</table>

Rebuild the full gallery and these three GIF reels with `make slice-shots`.
Character art: [LimeZu](https://limezu.itch.io).

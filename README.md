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

<p align="center">
  <img src="assets/shots/playable-office.gif" width="49%" alt="Clock Out office sequence">
  <img src="assets/shots/playable-combat.gif" width="49%" alt="Clock Out combat sequence">
</p>

<p align="center">
  <img src="assets/shots/playable-night.gif" width="88%" alt="Full Clock Out playable sequence">
</p>

## The night, screen by screen

All eleven overhauled screens are shown here, including the title above.
These are native-resolution captures reached through the playable state machine, with real health, cards, and consequences.

<table>
  <tr>
    <td width="50%"><img src="assets/shots/playable-office.png" alt="Fourth-floor office with selectable attendance record, coworker, copier, and exit"></td>
    <td width="50%"><img src="assets/shots/playable-attendance.png" alt="Attendance record reveals that the manager clocked out at 18:02"></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-coworker.png" alt="Kim asks why the copier keeps printing the player's name"></td>
    <td><img src="assets/shots/playable-combat.png" alt="Copier battle with card costs, selected-card rules, player health, and enemy intent"></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-reward.png" alt="Three illustrated card rewards after defeating the copier"></td>
    <td><img src="assets/shots/playable-response.png" alt="The attendance clue unlocks a response to the manager's accusation"></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-boss.png" alt="Manager fight reflects the clue's damage and weakened attack, plus carried player health"></td>
    <td><img src="assets/shots/playable-exit.png" alt="Successful clock-out ending: the clock finally advances to 03:18"></td>
  </tr>
  <tr>
    <td><img src="assets/shots/playable-defeat.png" alt="Defeat returns the worker to 03:17 and offers a fresh start"></td>
    <td><img src="assets/shots/playable-pause.png" alt="Pause screen with resume, reduced effects, fullscreen, and quit controls"></td>
  </tr>
</table>

Rebuild the full gallery and these three GIF reels with `make slice-shots`.

Office assets: [LimeZu](https://limezu.itch.io).
Character art by me (Josh).

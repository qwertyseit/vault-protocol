# Vault Protocol

A two-player co-op puzzle game for Android, made for the Mobile Game Development course (group MT-2401).

A bank-vault heist for two: the **Operator** holds the phone with a 3D vault, the **Expert** has the technical manual on another device. Neither can do it alone — you have to talk.

## How to play

- **Operator** — holds the phone, turns the vault, describes what is on each side and does the actions.
- **Expert** — opens [`Manual/Vault_Protocol_Manual_v1.3.pdf`](Manual/Vault_Protocol_Manual_v1.3.pdf) on a second device, finds the right rule and says what to do.
- **Side timers:** every module is sealed. Tap a side to open it: its own timer starts and the vault **locks** on that side until it is disarmed. A side timer at 00:00 or **3 strikes = alarm = mission failed**.
- **Records:** the best clear time of every mission is saved on the phone and shown on the menu.

| Mission | Modules | Side timers |
|---|---|---|
| 01 · Training Safe | Wires (3–4) + Override Button | 2:00 each |
| 02 · Bank Vault | Wires (4–5) + Override Button + Symbol Keypad | 1:30, Keypad 2:00 |
| 03 · Central Reserve | Wires (4–5) + Override Button + Symbol Keypad + Word Lock | 1:15, Keypad 1:45, Word Lock 3:00 |

The modules sit on the sides of the vault: front = timer and strike lights, right = Wires, back = Override Button, left = Symbol Keypad, top = Vault ID plate (the Expert needs it for most rules), bottom = Word Lock (Mission 3: a screen word and six word buttons that sound alike — STEEL / STEAL, CASH / CACHE — so everything has to be spelled).

## Controls

| Gesture | Action |
|---|---|
| Drag with one finger | Turn the vault in any direction; it settles on the nearest side, upright. Locked while a side is open |
| Tap | Open a sealed side; cut a wire, press a keypad key or a word button, tap the button |
| Press and hold | Hold the Override Button, let go on the right number of the PIN counter |
| Pinch with two fingers | Zoom (mouse wheel on a PC) |
| Pause button / Android back button | Pause: resume, restart, settings, main menu. The game also pauses by itself when the app goes to the background |

The menu also has **How to play** (opens by itself on the first start) and **Settings**: sound, vibration, spin speed (saved on the phone), **Perf monitor** (FPS, frame time and draw calls on screen, used for the performance test) and **Reset records**.

## Running the project

1. Install **Godot 4.7.2** (Standard version).
2. Project Manager → **Import** → select `project.godot`.
3. Press **F5**. The game opens in a portrait 450×800 window; the mouse works as a finger.

**Android:** Project → Export → preset **Android** (arm64-v8a + armeabi-v7a). Needs the Godot export templates, JDK 17 and the Android SDK set in Editor Settings.

**Testing tip:** run with `-- --seed=123` to get the same puzzles every time. The correct answers are printed to the Output panel when a mission starts.

## Project structure

```
project.godot          project settings (portrait 1080×1920, Compatibility renderer)
scenes/main.tscn       the only scene; everything else is created from code
scripts/
  main.gd              game states (menu → playing → paused → result), side timers,
                       strikes, HUD, pause menu, settings and How to play screens
  vault_3d.gd          the 3D vault: one 2D panel per side, rotation, touch handling
  puzzle_rules.gd      every puzzle rule, in the same order as the manual
  vault_id.gd          Vault ID and its checks
  wires_module.gd      module: wires
  button_module.gd     module: override button (tap / hold + PIN counter)
  keypad_module.gd     module: symbol keypad
  word_lock_module.gd  module: word lock (screen word + 6 word buttons, 3 stages)
  game_settings.gd     player settings saved in user://settings.cfg
  game_progress.gd     mission records (best time) saved in user://progress.cfg
  perf_monitor.gd      performance overlay (FPS, frame time, draw calls)
  vault_module.gd      base script for the modules (+ the shutter of a sealed side)
  mission_data.gd      settings of the three missions
  ui_factory.gd        UI helpers and colors
  sound_fx.gd          sound effects generated in code
Manual/                the Expert's technical manual (PDF)
```

## Team

| Member | Role | Contribution |
|---|---|---|
| **Adilseit Tuiyebay** | Game development | Godot project, gameplay code, 3D vault and touch input, UI and feedback, Android build |
| **Artemiy Kim** | Game design and documentation | Puzzle rules and mission balance, the Expert's technical manual (PDF), README and other documents, demo video, playtesting |

Versions: Assignment 2 — tag [`v0.2-a2`](https://github.com/qwertyseit/vault-protocol/tree/v0.2-a2). Assignment 3 — release [`v0.3-a3`](https://github.com/qwertyseit/vault-protocol/releases/tag/v0.3-a3) (pause, settings, How to play, Mission 3 with the Word Lock). Assignment 4 — release `v0.4-a4`, Android build 0.4 (side timers, simpler HUD, mission records, performance monitor, manual rev. 1.3).

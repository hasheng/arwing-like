# arwing-like

A small on-rails 3D space shooter prototype built with [Godot](https://godotengine.org) 4.7.2.
Inspired by classic arcade rail shooters; all art is primitive boxes and all audio is
synthesised in code. No third-party or Nintendo assets are used.

## Features
- Three levels with different rules: a rail canyon (scripted phases, obstacle walls), an asteroid
  belt (rocks split when shot, flight rings build a combo) and an all-range dogfight arena
  (free turning, chasing enemies, U-turn, circling boss)
- Mouse-aimed reticle, hold-to-lock homing missiles, barrel roll that reflects enemy shots
- Boost / brake gauge, loop, smart bombs
- Power-ups: shield, weapon levels, bomb, overdrive, repair
- Drone, diver, tank and ace enemies (aces dodge lasers mid-roll); formations pay a bonus
- Procedural audio, title screen, pause, saved high score

## Controls
WASD move (A/D turn in the dogfight) - mouse aim - LMB/Space fire - hold RMB/C lock on, release to launch -
B/MMB bomb - Shift boost - Ctrl brake - Q/E barrel roll - F loop / U-turn - P/Esc pause - R restart / next level

## Run
Open the folder in Godot 4.7+, or `godot --path .`

## Tests
Headless smoke tests: `godot --headless --path . --script res://tests/boss_smoke.gd` (also `enemy_smoke`, `mechanics_smoke`, `modes_smoke`, `flow_smoke`).

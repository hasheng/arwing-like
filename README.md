# arwing-like

A small on-rails 3D space shooter prototype built with [Godot](https://godotengine.org) 4.7.2.
Inspired by classic arcade rail shooters; all art is primitive boxes and all audio is
synthesised in code. No third-party or Nintendo assets are used.

## Features
- Three levels with different rules: a rail canyon (scripted phases, obstacle walls), an asteroid
  belt (rocks split when shot, flight rings build a combo) and an all-range dogfight arena
  (free turning, chasing enemies, U-turn)
- A fourth level, a trench run: surface approach, a walled trench with catwalks and gun emplacements,
  fighters on your tail (rear-view window; brake to shake them) and a vent that opens only briefly
  and only yields to a lock-on missile
- A different boss per level, each with its own rule: the Warden's cannons shield its core and it
  lunges once exposed; the Geode wears spinning crystal armour and hurls boulders you can shoot
  apart; the Rival can only be hurt from behind, so you have to out-turn or out-brake it
- Procedural chiptune music: a small sequencer renders looping stems (bass, drums, arp, lead) in
  code, builds with the level, switches to a boss track, and bends pitch with boost and brake
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
Add `-- --autostart --level=N` (0-3) to skip the title screen, `--boss` to jump to the boss fight, `--at=N` to start N units in, `--tail` to spawn a chaser.

## Tests
Headless smoke tests: `godot --headless --path . --script res://tests/boss_smoke.gd` (also `boss_mechanics`, `trench_smoke`, `enemy_smoke`, `mechanics_smoke`, `modes_smoke`, `flow_smoke`, `music_smoke`).

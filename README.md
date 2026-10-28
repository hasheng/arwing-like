# arwing-like

A small on-rails 3D space shooter prototype built with [Godot](https://godotengine.org) 4.7.2.
Inspired by classic arcade rail shooters; all art is primitive boxes and all audio is
synthesised in code. No third-party or Nintendo assets are used.

## Features
- Three levels (config table in `main.gd`), each ending in a boss
- Lasers, hold-to-lock homing missiles, barrel roll that dodges everything
- Drone, tank and diver enemies; pickups, explosions, screen shake
- Title screen, pause, saved high score

## Controls
WASD move · Space fire · hold Shift/C to lock on, release to launch · Q/E barrel roll · P/Esc pause · R restart / next level

## Run
Open the folder in Godot 4.7+, or `godot --path .`

## Tests
Headless smoke tests: `godot --headless --path . --script res://tests/boss_smoke.gd` (also `enemy_smoke`, `flow_smoke`).

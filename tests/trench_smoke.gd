extends SceneTree
## Headless test of the trench level: walls, scraping, tail fighters, and the vent finale.

var game


func _load():
	game.level_idx = 3
	game.carry_score = 0
	game.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	assert(m.cfg["name"] == "TRENCH RUN" and m.cfg.get("trench", false), "level 3 should be the trench")
	m.hp = 1000000.0
	return m


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	game = load("res://main.gd")

	# --- Surface first, then walls; scraping a wall hurts and pushes you back in.
	var m = await _load()
	assert(m.mirror_cam != null and m.station != null, "trench builds a rear view and the station")
	await _frames(5)
	m.rig.position.z = -900.0
	m.scenery_z = m.rig.position.z - 100.0
	await _frames(5)
	var slabs := 0
	for s in m.scenery:
		if s is MeshInstance3D and s.mesh is BoxMesh and (s.mesh as BoxMesh).size == Vector3(8, 50, 26):
			slabs += 1
	assert(slabs > 4, "trench walls should be built past the entrance, found %d" % slabs)
	assert(m.phase_idx >= 1, "phase did not advance into the trench")
	m.ship.position.x = 40.0
	m.iframes = 0.0
	var hp0: float = m.hp
	await _frames(2)
	assert(absf(m.ship.position.x) <= float(m.cfg["trench_half"]), "ship left the trench")
	assert(m.hp < hp0, "scraping the wall should cost health")
	assert(m.music.current == "trench", "trench song, got %s" % m.music.current)

	# --- A tail fighter holds station behind you, shoots, and is passed when you brake.
	m.ship.position = Vector3.ZERO
	m._spawn_tail()
	var tail: Dictionary = m.foes[m.foes.size() - 1]
	assert(tail["mode"] == "tail", "tail foe mode")
	await _frames(300)
	assert(tail in m.foes, "tail fighter vanished while it should be chasing")
	var off: float = tail["n"].global_position.z - m.ship.global_position.z
	assert(off > 5.0 and off < 70.0, "tail should hold station behind, offset %.1f" % off)
	var fired: bool = m.shots.size() > 0 or m.hp < hp0
	assert(fired, "tail fighter never fired")
	Input.action_press("brake")
	await _frames(240)
	Input.action_release("brake")
	off = tail["n"].global_position.z - m.ship.global_position.z
	assert(off < 0.0, "braking should let the tail overshoot, offset %.1f" % off)
	m.queue_free()
	await process_frame

	# --- Vent: shut or hit by a laser it holds; a torpedo through the open vent wins the level.
	m = await _load()
	m.rig.position.z = -float(m.cfg["boss_z"])
	await _frames(10)
	assert(m.boss_spawned and m.boss["kind"] == "port", "vent boss did not spawn")
	assert(m.music.current == "boss_trench", "boss song, got %s" % m.music.current)
	var d: Dictionary = m.boss
	var vent: Dictionary = d["parts"][0]
	assert(game.Bosses.targets(m) == [vent], "only the vent should be lockable")
	d["z0"] = m.rig.position.z - 200.0
	d["t"] = 0.5  # shut
	await _frames(1)
	assert(not d["open"], "vent should start shut")
	m._damage_target(vent, 8.0)
	assert(vent["hp"] == 8.0, "a torpedo hit a shut vent")
	d["t"] = 2.5  # open
	await _frames(1)
	assert(d["open"], "vent should be open in its window")
	m._damage_target(vent, 1.0)
	assert(vent["hp"] == 8.0, "a laser should glance off even an open vent")
	var score0: int = m.score
	m._damage_target(vent, 8.0)
	assert(m.boss.is_empty() and m.score >= score0 + 5000, "torpedo through the open vent should blow the station")
	await _frames(3)
	assert(m.state == "won", "state is " + m.state)
	m.queue_free()
	await process_frame

	# --- Miss it and you hit the wall.
	m = await _load()
	m.rig.position.z = -float(m.cfg["boss_z"])
	await _frames(10)
	m.boss["z0"] = m.ship.global_position.z - 3.0
	await _frames(3)
	assert(m.state == "dead", "flying into the wall should end the run, state %s" % m.state)
	m.queue_free()
	await process_frame
	game.level_idx = 0
	game.carry_score = 0
	print("TRENCH SMOKE OK")
	quit()

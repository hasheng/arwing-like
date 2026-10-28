extends SceneTree
## Headless smoke test for power-ups and the three level modes' distinct rules.

func _boot(lvl: int):
	var script = load("res://main.gd")
	script.level_idx = lvl
	script.carry_score = 0
	script.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.spawn_t = 1.0e9
	return m


func _initialize() -> void:
	# ---- power-ups (rail level)
	var m = await _boot(0)
	m.iframes = 0.0
	m._collect("shield")
	assert(m.shield == m.SHIELD_MAX, "shield not granted")
	var hp0: float = m.hp
	m._hurt(10.0)
	assert(m.hp == hp0 and m.shield == m.SHIELD_MAX - 10.0, "shield should absorb damage")
	m.iframes = 0.0
	m._hurt(100.0)
	assert(m.hp == hp0 - 70.0, "overflow damage should reach hp, got %f" % m.hp)
	m._collect("weapon")
	m._collect("weapon")
	assert(m.weapon == 3, "weapon level")
	m.lasers.clear()
	m._fire()
	assert(m.lasers.size() == 5, "level 3 fires a five-way spread, got %d" % m.lasers.size())
	m.iframes = 0.0
	m._hurt(25.0)
	assert(m.weapon == 2, "heavy hit should cost a weapon level")
	m._collect("bomb")
	assert(m.bombs == 2, "bomb pickup")
	m._collect("boost")
	assert(m.overdrive_t > 0.0, "overdrive")
	# Bomb wipes nearby enemies and shots.
	m.foes.clear()
	for i in 3:
		m._spawn_foe("drone", m.ship.global_position + Vector3(i * 4 - 4, 0, -40))
	m._enemy_shot(m.ship.global_position + Vector3(0, 0, -20), m.ship.global_position)
	m._bomb()
	assert(m.bombs == 1 and m.foes.size() == 0 and m.shots.size() == 0, "bomb should clear the area")
	m.queue_free()
	await process_frame

	# ---- asteroid level: rocks split, rings build a combo
	m = await _boot(1)
	assert(m.mode == "asteroid")
	var big: Dictionary = m._spawn_rock(m.ship.global_position + Vector3(0, 0, -50), 3, Vector3.ZERO)
	var n0: int = m.rocks.size()
	m._break_rock(big, true, true)
	assert(m.rocks.size() == n0 - 1 + 2, "big rock should split in two")
	assert(m.rocks[m.rocks.size() - 1]["size"] == 2, "pieces should be one size smaller")
	var small: Dictionary = m._spawn_rock(m.ship.global_position + Vector3(0, 0, -50), 1, Vector3.ZERO)
	var n1: int = m.rocks.size()
	m._break_rock(small, true, true)
	assert(m.rocks.size() == n1 - 1, "smallest rock must not split")
	# Ram a rock.
	m.iframes = 0.0
	hp0 = m.hp
	m._spawn_rock(m.ship.global_position, 2, Vector3.ZERO)
	m._move_rocks(0.016)
	assert(m.hp < hp0, "ramming a rock should hurt")
	# Ring: pass through the middle -> combo; miss -> reset.
	m.rocks.clear()
	var z: float = m.ship.global_position.z
	var ring := {"n": Node3D.new(), "z": z - 1.0, "done": false, "prev": z + 1.0}
	ring["n"].position = Vector3(m.ship.global_position.x, m.ship.global_position.y, z - 1.0)
	m.add_child(ring["n"])
	m.rings.append(ring)
	m.rig.position.z -= 3.0  # fly through it
	m._move_rings(0.016)
	assert(m.combo == 1, "ring pass should add combo")
	var ring2 := {"n": Node3D.new(), "z": m.ship.global_position.z - 1.0, "done": false, "prev": m.ship.global_position.z + 1.0}
	ring2["n"].position = Vector3(m.ship.global_position.x + 20.0, 0, m.ship.global_position.z - 1.0)
	m.add_child(ring2["n"])
	m.rings.append(ring2)
	m.rig.position.z -= 3.0
	m._move_rings(0.016)
	assert(m.combo == 0, "missed ring should reset combo")
	m.queue_free()
	await process_frame

	# ---- all-range level: free turning, chasers, boundary, U-turn
	m = await _boot(2)
	assert(m.mode == "allrange")
	var yaw0: float = m.rig.rotation.y
	Input.action_press("left")
	for i in 30:
		await physics_frame
	Input.action_release("left")
	assert(absf(m.rig.rotation.y - yaw0) > 0.3, "A should turn the rig in all-range")
	assert(absf(m.ship.position.x) < 1.0, "ship should not strafe in all-range")
	# U-turn flips heading.
	m.gauge = 1.0
	var fwd0: Vector3 = m._rig_forward()
	Input.action_press("loop")
	await physics_frame
	await physics_frame
	Input.action_release("loop")
	for i in 70:
		await physics_frame
	assert(m._rig_forward().dot(fwd0) < 0.0, "U-turn should reverse heading")
	# Chasers hunt the player.
	m.foes.clear()
	m.spawn_t = 0.0
	for i in 5:
		await physics_frame
	assert(m.foes.size() >= 1, "chasers should spawn")
	var f: Dictionary = m.foes[0]
	var d0: float = (f["n"].global_position as Vector3).distance_to(m.ship.global_position)
	for i in 30:
		await physics_frame
	assert(f["mode"] == "chase", "all-range foes use chase AI")
	# Boundary assist: heading outward at the edge turns the rig back in.
	var arena: float = m.cfg["arena"]
	m.rig.position = Vector3(0, 0, arena - 5.0)
	m.rig.rotation.y = 0.0  # facing -z = toward the centre; flip it outward
	m.rig.rotation.y = PI
	for i in 120:
		await physics_frame
	assert(Vector2(m.rig.position.x, m.rig.position.z).length() <= arena + 0.5, "rig escaped the arena")
	# Quota gates the boss.
	assert(not m.boss_spawned, "boss before quota")
	m.kills = int(m.cfg["quota"])
	for i in 5:
		await physics_frame
	assert(m.boss_spawned, "boss should arrive at the kill quota")
	m.queue_free()
	await process_frame

	# ---- ace dodges lasers mid-roll
	m = await _boot(0)
	var ace: Dictionary = m._spawn_foe("ace", m.ship.global_position + Vector3(0, 0, -30))
	ace["rolling"] = 0.4
	var hp_ace: float = ace["hp"]
	var l := Node3D.new()
	m.add_child(l)
	l.global_position = ace["n"].global_position
	m.lasers.append({"n": l, "v": Vector3.ZERO})
	m._move_lasers(0.016)
	assert(ace["hp"] == hp_ace, "rolling ace should slip lasers")
	ace["rolling"] = 0.0
	m.lasers.clear()  # the first entry would hit too: the same laser node is still in the list
	m.lasers.append({"n": l, "v": Vector3.ZERO})
	m._move_lasers(0.016)
	assert(ace["hp"] == hp_ace - 1.0, "ace should take laser hits otherwise")

	print("MODES SMOKE OK")
	quit()

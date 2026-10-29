extends SceneTree
## Headless smoke test, run per level: reach the boss, lock on, launch, kill it, expect "won".

func _initialize() -> void:
	var script = load("res://main.gd")
	for lvl in script.LEVELS.size():
		script.level_idx = lvl
		script.carry_score = 0
		script.started = true
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		await process_frame
		assert(m.cfg["name"] == script.LEVELS[lvl]["name"], "wrong level config")
		if m.mode == "allrange":
			m.kills = int(m.cfg["quota"])
		else:
			m.rig.position.z = -m.cfg["boss_z"]
		m.hp = 1000000.0
		for i in 400:
			await physics_frame
		assert(m.boss_spawned and not m.boss.is_empty(), "boss did not spawn, level %d" % lvl)
		m.boss["entry"] = 1.0
		var kind: String = m.boss["kind"]
		if kind == "port":  # a fixed wall you fly into: put it in missile range and hold the vent open
			m.boss["z0"] = m.rig.position.z - 130.0
			m.boss["hold_open"] = true
		# Aiming is covered elsewhere; lock directly so an orbiting boss cannot be out of reach.
		m.locks = [script.Bosses.targets(m)[0]]
		m._launch_missiles()
		for i in 150:
			await physics_frame
		if kind == "port":
			assert(m.boss.is_empty(), "one torpedo should blow the vent, level %d" % lvl)
		else:
			assert(script.Bosses.ratio(m) < 1.0, "missile did not damage boss, level %d" % lvl)
			for p in m.boss["parts"].duplicate():  # armour first: shielded bodies shrug off the finishing blow
				m._damage_target(p, 999.0)
			m.boss["hp"] = 1.0
			m._damage_target(m.boss, 5.0, m.boss["n"].global_position - m.boss["dir"] * 5.0)  # a rear hit, for the rival
		for i in 3:
			await physics_frame
		assert(m.state == "won", "state is " + m.state)
		print("LEVEL %d (%s) OK score=%d" % [lvl, m.mode, m.score])
		m.queue_free()
		await process_frame
	script.level_idx = 0
	script.carry_score = 0
	print("SMOKE OK")
	quit()

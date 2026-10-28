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
		m.locks = [m.boss]  # aiming is covered elsewhere; lock directly so the orbiting boss cannot be out of reach
		m._launch_missiles()
		for i in 150:
			await physics_frame
		assert(m.boss["hp"] < m.cfg["boss_hp"], "missile did not damage boss, level %d" % lvl)
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

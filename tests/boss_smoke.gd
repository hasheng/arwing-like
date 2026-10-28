extends SceneTree
## Headless smoke test, run per level: jump to the boss, lock on, launch, kill it, expect "won".
## Then check R on the win screen advances the static level index.

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
		m.rig.position.z = -m.cfg["boss_z"]
		m.hp = 1000000.0
		for i in 400:
			await physics_frame
		assert(m.boss_spawned and not m.boss.is_empty(), "boss did not spawn, level %d" % lvl)
		m.boss["entry"] = 1.0
		m._lock_next()
		assert(m.locks.size() == 1, "boss not lockable")
		m._launch_missiles()
		for i in 90:
			await physics_frame
		assert(m.boss["hp"] < m.cfg["boss_hp"], "missile did not damage boss")
		m.boss["hp"] = 1.0
		m._damage_target(m.boss, 5.0)
		for i in 3:
			await physics_frame
		assert(m.state == "won", "state is " + m.state)
		print("LEVEL %d OK score=%d" % [lvl, m.score])
		m.queue_free()
		await process_frame
	script.level_idx = 0
	script.carry_score = 0
	print("SMOKE OK")
	quit()

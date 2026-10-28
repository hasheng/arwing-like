extends SceneTree
## Headless smoke test for enemy kinds: tanks take three hits, divers dive and ram.

func _initialize() -> void:
	var script = load("res://main.gd")
	script.level_idx = 0
	script.carry_score = 0
	script.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.cfg = m.cfg.duplicate(true)  # LEVELS is const; copy before editing the mix
	m.spawn_t = 1.0e9

	m.cfg["mix"] = {"tank": 1.0}
	m._spawn_foe()
	assert(m.foes.size() == 1 and m.foes[0]["hp"] == 3.0, "tank hp")
	m._damage_target(m.foes[0], 1.0)
	m._damage_target(m.foes[0], 1.0)
	assert(m.foes.size() == 1, "tank died early")
	m._damage_target(m.foes[0], 1.0)
	await physics_frame
	assert(m.foes.size() == 0, "tank survived three hits")
	assert(m.score == 300, "tank score %d" % m.score)

	m.cfg["mix"] = {"diver": 1.0}
	m._spawn_foe()
	m.foes[0]["n"].global_position = m.ship.global_position + Vector3(4, 2, -100)
	var hp0: float = m.hp
	var dove := false
	for i in 240:
		await physics_frame
		if m.foes.size() > 0 and m.foes[0].get("diving", false):
			dove = true
	assert(dove, "diver never dove")
	assert(m.hp < hp0, "diver did not ram")
	print("ENEMY SMOKE OK")
	quit()

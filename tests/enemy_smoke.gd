extends SceneTree
## Headless smoke test for enemies: tanks take three hits, divers dive and ram,
## formations pay a bonus only if every member is shot down.

func _initialize() -> void:
	var script = load("res://main.gd")
	script.level_idx = 0
	script.carry_score = 0
	script.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.spawn_t = 1.0e9  # no random spawns during the test

	# Tank: three hits, scores 300, leaves a wreck rather than vanishing.
	var tank: Dictionary = m._spawn_foe("tank", Vector3(0, 0, m.rig.position.z - 100.0))
	assert(tank["hp"] == 3.0, "tank hp")
	m._damage_target(tank, 1.0)
	m._damage_target(tank, 1.0)
	assert(m.foes.size() == 1, "tank died early")
	m._damage_target(tank, 1.0)
	assert(m.foes.size() == 0, "tank survived three hits")
	assert(m.wrecks.size() == 1, "shot-down tank should become a wreck")
	assert(m.score == 300, "tank score %d" % m.score)
	for i in 60:
		await physics_frame
	assert(m.wrecks.size() == 0, "wreck never exploded")

	# Diver: flies in, locks on, then rams the ship.
	var d: Dictionary = m._spawn_foe("diver", m.ship.global_position + Vector3(4, 2, -100))
	var hp0: float = m.hp
	var dove := false
	for i in 300:
		await physics_frame
		if d.get("diving", false):
			dove = true
	assert(dove, "diver never dove")
	assert(m.hp < hp0, "diver did not ram")

	# Formation fully shot down: bonus + pickup.
	m.iframes = 0.0
	m.score = 0
	m.pickups.clear()
	m._spawn_wave("vee")
	assert(m.foes.size() == 5, "vee should spawn five")
	var wid: int = m.foes[0]["wave"]
	for f in m.foes.duplicate():
		m._damage_target(f, 99.0)
	assert(m.score >= 5 * 100 + 500, "no formation bonus, score %d" % m.score)
	assert(m.pickups.size() >= 1, "no bonus pickup")

	# Formation with an escapee: no bonus.
	m.score = 0
	m._spawn_wave("line")
	wid = m.foes[0]["wave"]
	var escapee: Dictionary = m.foes[0]
	m._destroy_foe(escapee, false)
	for f in m.foes.duplicate():
		m._damage_target(f, 99.0)
	assert(m.score == 400, "escaped formation still paid, score %d" % m.score)
	assert(m.waves[wid] < 0, "wave should be marked failed")

	print("ENEMY SMOKE OK")
	quit()

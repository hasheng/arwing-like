extends SceneTree
## Headless smoke test for flight mechanics: boost/brake gauge, loop, shot reflection,
## obstacle collision with invulnerability frames.

func _initialize() -> void:
	var script = load("res://main.gd")
	script.level_idx = 0
	script.carry_score = 0
	script.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.spawn_t = 1.0e9

	# Boost drains the gauge and speeds the rig up; releasing refills it.
	var z0: float = m.rig.position.z
	Input.action_press("boost")
	for i in 60:
		await physics_frame
	assert(m.gauge < 1.0, "boost did not drain gauge")
	assert(m.speed_mult > 1.5, "boost did not speed up, mult %f" % m.speed_mult)
	Input.action_release("boost")
	var g: float = m.gauge
	for i in 60:
		await physics_frame
	assert(m.gauge > g, "gauge did not refill")

	# Brake slows below cruise.
	Input.action_press("brake")
	for i in 60:
		await physics_frame
	assert(m.speed_mult < 0.8, "brake did not slow, mult %f" % m.speed_mult)
	Input.action_release("brake")
	for i in 120:
		await physics_frame

	# Emptying the gauge locks boost until it recovers.
	m.gauge = 0.01
	Input.action_press("boost")
	for i in 10:
		await physics_frame
	assert(m.gauge_locked, "empty gauge should lock")
	Input.action_release("boost")

	# Loop costs gauge and sets the looping flag.
	m.gauge = 1.0
	m.gauge_locked = false
	m.ship.loop()
	assert(m.ship.looping, "loop flag")

	# Barrel roll reflects an enemy shot instead of taking damage.
	await create_timer(1.0).timeout
	m.iframes = 0.0
	m.shots.clear()
	var hp0: float = m.hp
	m.ship.barrel_roll(1.0)
	m._enemy_shot(m.ship.global_position + Vector3(0, 0, -3), m.ship.global_position)
	for i in 3:
		await physics_frame
	assert(m.hp == hp0, "roll should reflect, not take damage")
	assert(m.shots.size() == 1 and m.shots[0]["reflected"], "shot not reflected")
	await create_timer(1.0).timeout

	# Obstacle: hurts once, then invulnerability frames absorb the next hit.
	m.shots.clear()
	m.iframes = 0.0
	hp0 = m.hp
	var sp: Vector3 = m.ship.global_position
	m.obstacles.append({"n": Node3D.new(), "z": sp.z, "boxes": [AABB(sp - Vector3(1, 1, 1), Vector3(2, 2, 2))]})
	m._check_obstacles()
	assert(m.hp == hp0 - 25.0, "obstacle should cost 25, hp %f -> %f" % [hp0, m.hp])
	m._check_obstacles()
	assert(m.hp == hp0 - 25.0, "iframes should absorb the second hit")

	# Mouse aim: before the mouse moves we aim dead ahead; after, at the cursor (top-left in headless).
	m.mouse_seen = false
	m._update_aim()
	assert(is_equal_approx(m.aim_point.x, m.ship.global_position.x), "should aim straight ahead")
	m.mouse_seen = true
	m._update_aim()
	assert(m.aim_point.x < m.ship.global_position.x and m.aim_point.y > m.ship.global_position.y, "aim did not follow mouse")
	m.lasers.clear()
	m._fire()
	assert(m.lasers.size() == 2 and (m.lasers[0]["v"] as Vector3).x < 0.0, "lasers did not head toward the aim point")
	# Lock-on follows the reticle: an enemy under the aim ray locks, one far off it does not.
	m.mouse_seen = false  # straight ahead keeps the target inside the arena clamp
	m._update_aim()
	m.foes.clear()
	var on_ray: Dictionary = m._spawn_foe("drone", m.ship.global_position + (m.aim_point - m.ship.global_position).normalized() * 60.0)
	var off_ray: Dictionary = m._spawn_foe("drone", m.ship.global_position + Vector3(25, -10, -60))
	m.locks.clear()
	m._lock_next()
	assert(m.locks.size() == 1 and m.locks[0]["n"] == on_ray["n"], "lock-on should pick the enemy under the reticle")

	print("MECHANICS SMOKE OK")
	quit()

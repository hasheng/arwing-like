extends SceneTree
## Headless test of what makes each boss different: warden armour + lunge, geode shards + boulders,
## rival rear-only damage. Every assertion is about an invariant of the rule, not a tuned number.

var game


func _level(lvl: int):
	game.level_idx = lvl
	game.carry_score = 0
	game.started = true
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	if m.mode == "allrange":
		m.kills = int(m.cfg["quota"])
	else:
		m.rig.position.z = -m.cfg["boss_z"]
	m.hp = 1000000.0
	for i in 400:
		await physics_frame
	assert(m.boss_spawned and not m.boss.is_empty(), "boss did not spawn, level %d" % lvl)
	m.boss["entry"] = 1.0
	return m


func _dealt(m, dmg: float, from := Vector3.INF) -> float:
	var before: float = m.boss["hp"]
	m._damage_target(m.boss, dmg, from)
	return before - float(m.boss["hp"])


func _initialize() -> void:
	game = load("res://main.gd")

	# --- WARDEN: cannons shield the core; once they are gone it takes full damage and lunges.
	var m = await _level(0)
	var d: Dictionary = m.boss
	assert(d["kind"] == "warden" and d["parts"].size() == 2, "warden should have two cannons")
	assert(d["shielded"], "warden starts shielded")
	var shielded_dmg := _dealt(m, 10.0)
	assert(shielded_dmg < 2.0, "shielded core took %.1f" % shielded_dmg)
	var r0: float = game.Bosses.ratio(m)
	m._damage_target(d["parts"][0], 999.0)
	assert(d["parts"][0]["dead"] and d["shielded"], "one cannon down must not drop the shield")
	assert(game.Bosses.ratio(m) < r0, "bar did not move when a cannon died")
	assert(game.Bosses.targets(m).size() == 2, "lock targets should be one cannon plus the body")
	m._damage_target(d["parts"][1], 999.0)
	assert(not d["shielded"], "shield should drop with the last cannon")
	var open_dmg := _dealt(m, 10.0)
	assert(open_dmg > shielded_dmg * 5.0, "exposed core should take far more (%.1f vs %.1f)" % [open_dmg, shielded_dmg])
	d["lunge_cd"] = 0.0
	for i in 5:
		await physics_frame
	assert(d["lunge"] >= 0.0, "warden did not start a lunge")
	d["x"] = m.ship.global_position.x
	d["y"] = m.ship.global_position.y
	d["lunge"] = 1.45
	m.iframes = 0.0
	var hp0: float = m.hp
	await physics_frame
	assert(m.hp < hp0, "lunge dive through the ship did no damage")
	m.queue_free()
	await process_frame

	# --- GEODE: shards stand between you and the core; lasers hit them first; it throws boulders.
	m = await _level(1)
	d = m.boss
	assert(d["kind"] == "geode" and d["parts"].size() == 4, "geode should have four shards")
	var shard: Dictionary = d["parts"][0]
	var hit: Dictionary = game.Bosses.hit_test(m, shard["n"].global_position)
	assert(hit.get("part", false), "a laser at a shard should strike the shard")
	hit = game.Bosses.hit_test(m, d["n"].global_position)
	assert(not hit.is_empty() and not hit.get("part", false), "a laser through the hole should reach the core")
	armoured_check(m)
	d["throw"] = 0.0
	var rocks0: int = m.rocks.size()
	await physics_frame
	assert(m.rocks.size() > rocks0, "geode threw no boulder")
	var boulder: Dictionary = m.rocks[m.rocks.size() - 1]
	assert((boulder["vel"] as Vector3).z > 5.0, "boulder is not coming toward the ship")
	for p in d["parts"].duplicate():
		m._damage_target(p, 999.0)
	assert(game.Bosses.live_parts(d) == 0, "shards not all destroyed")
	assert(_dealt(m, 10.0) >= 9.9, "broken armour should take full damage")
	m.queue_free()
	await process_frame

	# --- RIVAL: front hits glance off, rear hits land. It stays in the arena and keeps switching tactics.
	m = await _level(2)
	d = m.boss
	assert(d["kind"] == "rival" and d["parts"].is_empty(), "rival has no parts")
	var pos: Vector3 = d["n"].global_position
	var front := _dealt(m, 10.0, pos + d["dir"] * 5.0)
	var rear := _dealt(m, 10.0, pos - d["dir"] * 5.0)
	assert(front < 2.0, "frontal hit did %.1f" % front)
	assert(rear > 9.9, "rear hit did only %.1f" % rear)
	assert(_dealt(m, 10.0) > 9.9, "a bomb (no direction) should always land")
	d["state_t"] = 0.0
	var s0: String = d["state"]
	await physics_frame
	assert(d["state"] != s0, "rival did not change tactics")
	var p0: Vector3 = d["n"].global_position
	for i in 120:
		await physics_frame
	var p1: Vector3 = d["n"].global_position
	assert(p0.distance_to(p1) > 20.0, "rival is not moving")
	assert(Vector2(p1.x, p1.z).length() < float(m.cfg["arena"]) + 10.0, "rival left the arena")
	m.queue_free()
	await process_frame
	game.level_idx = 0
	game.carry_score = 0
	print("BOSS MECHANICS OK")
	quit()


func armoured_check(m) -> void:
	var d: Dictionary = m.boss
	var armoured := _dealt(m, 10.0)
	assert(armoured > 0.0 and armoured < 9.0, "shard armour should reduce, not block, damage (%.1f)" % armoured)

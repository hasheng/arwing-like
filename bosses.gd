extends RefCounted
## One boss per level mode, each with its own rule for how to hurt it.
##   WARDEN (rail):      wing cannons shield the core. Destroy them, then dodge its lunge.
##   GEODE (asteroid):   spinning crystal armour; it hurls boulders you can shoot apart.
##   RIVAL (all-range):  only vulnerable from behind. Brake, loop or out-turn it to get on its tail.
## The boss dict lives in main.gd (main.boss). Parts are targets of their own: {n, hp, r, part, dead}.

const Util = preload("res://util.gd")

const KINDS := {"rail": "warden", "asteroid": "geode", "allrange": "rival"}
const TITLES := {"warden": "WARDEN", "geode": "GEODE", "rival": "RIVAL"}


static func spawn(m) -> Dictionary:
	var kind: String = KINDS[m.mode]
	var color: Color = m.cfg["boss_color"]
	var n := Node3D.new()
	var parts: Array = []
	var hp := float(m.cfg["boss_hp"])
	var d := {"kind": kind, "n": n, "hp": hp, "max": hp, "t": 0.0, "fire": 2.0, "entry": 0.0, "flash": 0.0,
			"summon": 8.0, "parts": parts, "r": 6.0, "title": TITLES[kind], "clang": 0.0,
			"x": 0.0, "y": 0.0, "lunge": -1.0, "lunge_cd": 6.0, "shielded": false, "throw": 3.0,
			"state": "hunt", "state_t": 8.0, "dir": Vector3.FORWARD, "bank": 0.0, "flee": Vector3.RIGHT}
	match kind:
		"warden":
			_build_warden(n, color, parts)
			d["shielded"] = true
		"geode":
			d["r"] = 4.6
			_build_geode(n, color, parts)
		_:
			d["r"] = 4.4
			_build_rival(n, color)
	m.add_child(n)
	if kind == "rival":
		n.global_position = m.ship.global_position + m._rig_forward() * 120.0
		d["dir"] = -m._rig_forward()
	else:
		n.global_position = Vector3(0, 0, m.rig.position.z - 200.0)
	return d


# ------------------------------------------------------------------------------ models

static func _part(parts: Array, n: Node3D, name: String, hp: float, r: float) -> Dictionary:
	var p := {"n": n, "hp": hp, "max": hp, "r": r, "part": true, "name": name, "dead": false,
			"flash": 0.0, "fire": randf_range(0.6, 1.6)}
	parts.append(p)
	return p


static func _build_warden(n: Node3D, color: Color, parts: Array) -> void:
	n.add_child(Util.box(Vector3(9, 3, 7), color))
	n.add_child(Util.box(Vector3(4, 1.4, 4), color.darkened(0.3), Vector3(0, 2.1, -0.5)))
	n.add_child(Util.box(Vector3(2.0, 1.0, 6.0), color.darkened(0.45), Vector3(0, 0, -5)))
	for side in [-1.0, 1.0]:
		n.add_child(Util.box(Vector3(6, 0.7, 3.0), color.darkened(0.4), Vector3(side * 6.0, 0, 0.5)))
		var gun := Node3D.new()
		gun.name = "CannonL" if side < 0.0 else "CannonR"
		gun.position = Vector3(side * 10.0, 0, 1.5)
		gun.add_child(Util.box(Vector3(2.6, 2.6, 2.6), color.lightened(0.15)))
		gun.add_child(Util.tube(0.4, 3.2, Color(0.15, 0.15, 0.2), Vector3(0, 0, 2.6)))
		gun.add_child(Util.glow(Util.ball(0.5, Color(1, 0.2, 0.2), Vector3(0, 1.5, 0)), Color(1, 0.2, 0.2), 2.5))
		n.add_child(gun)
		_part(parts, gun, gun.name, 14.0, 2.9)
	var core := Util.glow(Util.box(Vector3(2.4, 2.4, 2.4), Color(1.0, 0.55, 0.1), Vector3(0, 0.2, 3.8)), Color(1.0, 0.5, 0.1), 1.5)
	core.name = "Core"
	n.add_child(core)
	var sh := Util.ball(4.0, Color(0.3, 0.7, 1.0, 0.3), Vector3(0, 0.2, 3.8))
	sh.name = "Shield"
	var sm: StandardMaterial3D = sh.material_override
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	n.add_child(sh)


static func _build_geode(n: Node3D, color: Color, parts: Array) -> void:
	var core := Util.glow(Util.ball(3.4, color.lightened(0.3)), color.lightened(0.5), 1.6)
	core.name = "Core"
	n.add_child(core)
	for i in 6:  # crystal spikes through the core for a silhouette
		var spike := Util.box(Vector3(1.0, 1.0, 9.0), color.darkened(0.15))
		spike.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		n.add_child(spike)
	var ring := Node3D.new()
	ring.name = "Ring"
	ring.position = Vector3(0, 0, 3.0)
	n.add_child(ring)
	for i in 4:
		var a := i * TAU / 4.0
		var shard := Node3D.new()
		shard.name = "Shard%d" % i
		shard.position = Vector3(cos(a), sin(a), 0) * 4.6
		var crystal := Util.glow(Util.box(Vector3(2.2, 5.0, 2.2), color.lightened(0.55)), color.lightened(0.6), 1.2)
		crystal.rotation.z = a
		shard.add_child(crystal)
		ring.add_child(shard)
		_part(parts, shard, shard.name, 8.0, 3.0)


static func _build_rival(n: Node3D, color: Color) -> void:
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * 1.7
	body.add_child(Util.box(Vector3(2.4, 1.1, 6.0), color))
	body.add_child(Util.cone(0.9, 3.4, color, Vector3(0, 0, -4.5), false, 6))
	body.add_child(Util.glow(Util.ball(0.7, Color(1.0, 0.9, 0.3), Vector3(0, 0.7, -1.0), Vector3(1, 0.7, 1.9)), Color(1.0, 0.8, 0.2), 1.2))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(side * 1.0, 0, 0.8)
		w.rotation.y = side * 0.5  # forward-swept
		w.add_child(Util.box(Vector3(6.0, 0.18, 2.4), color.darkened(0.3), Vector3(side * 3.0, 0, 0)))
		w.add_child(Util.box(Vector3(0.2, 1.2, 1.6), Color(0.95, 0.85, 0.3), Vector3(side * 6.0, 0.5, 0)))
		body.add_child(w)
		body.add_child(Util.box(Vector3(0.18, 1.5, 1.6), color.darkened(0.2), Vector3(side * 0.7, 1.0, 2.6)))
		var eng := Util.glow(Util.tube(0.55, 1.2, Color(1.0, 0.4, 0.15), Vector3(side * 0.8, 0, 3.4)), Color(1.0, 0.4, 0.1), 1.0)
		eng.name = "Engine"
		body.add_child(eng)
	n.add_child(body)


# ---------------------------------------------------------------------------- queries

static func live_parts(d: Dictionary) -> int:
	var c := 0
	for p in d["parts"]:
		if not p["dead"]:
			c += 1
	return c


## Everything a missile can lock onto: surviving parts first, then the body.
static func targets(m) -> Array:
	var out: Array = []
	if m.boss.is_empty():
		return out
	for p in m.boss["parts"]:
		if not p["dead"]:
			out.append(p)
	out.append(m.boss)
	return out


## Which boss target (a part or the body) a laser or shot at world point p has struck, or {}.
static func hit_test(m, p: Vector3, extra := 0.0) -> Dictionary:
	if m.boss.is_empty():
		return {}
	for part in m.boss["parts"]:
		if not part["dead"] and p.distance_to(part["n"].global_position) < float(part["r"]) + extra:
			return part
	if p.distance_to(m.boss["n"].global_position) < float(m.boss["r"]) + extra:
		return m.boss
	return {}


## Total health left across the body and every part, 0..1, for the HUD bar.
static func ratio(m) -> float:
	var d: Dictionary = m.boss
	if d.is_empty():
		return -1.0
	var cur := maxf(float(d["hp"]), 0.0)
	var mx := float(d["max"])
	for p in d["parts"]:
		mx += float(p["max"])
		if not p["dead"]:
			cur += maxf(float(p["hp"]), 0.0)
	return cur / mx


## Scales damage landing on the boss body. `from` is where the hit came from (INF = no direction, e.g. a bomb).
static func filter(m, dmg: float, from: Vector3) -> float:
	var d: Dictionary = m.boss
	match d["kind"]:
		"warden":
			if live_parts(d) > 0:
				_clang(m, d, from)
				return dmg * 0.08
		"geode":
			if live_parts(d) > 0:
				return dmg * 0.4
		"rival":
			if from != Vector3.INF and is_front_hit(d, from):
				_clang(m, d, from)
				return dmg * 0.1
	return dmg


## True when a hit from `from` lands on the rival's front half rather than its engines.
static func is_front_hit(d: Dictionary, from: Vector3) -> bool:
	var v: Vector3 = from - (d["n"] as Node3D).global_position
	return v.length() > 0.1 and v.normalized().dot(d["dir"]) > -0.15


static func _clang(m, d: Dictionary, from: Vector3) -> void:
	if float(d["clang"]) > 0.0:
		return
	d["clang"] = 0.15
	m._sfx("deflect")
	if from != Vector3.INF:
		Util.burst(m, from, Color(0.8, 0.9, 1.0), 6, 0.6)


static func damage_part(m, p: Dictionary, dmg: float) -> void:
	if p["dead"]:
		return
	p["hp"] = float(p["hp"]) - dmg
	m.score += 15
	var pos: Vector3 = p["n"].global_position
	if float(p["hp"]) > 0.0:
		p["flash"] = 0.08
		Util.flash(p["n"], true)
		Util.burst(m, pos, Color(1.0, 1.0, 0.6), 6, 0.5)
		return
	p["dead"] = true
	m.score += 400
	m.shake = 0.8
	Util.burst(m, pos, Color(1.0, 0.6, 0.2), 40, 1.8)
	m._sfx("boom")
	p["n"].queue_free()
	var d: Dictionary = m.boss
	if live_parts(d) == 0:
		match d["kind"]:
			"warden":
				d["shielded"] = false
				var sh = d["n"].get_node_or_null("Shield")
				if sh:
					sh.visible = false
				m.hud.toast("CORE EXPOSED")
			"geode":
				m.hud.toast("ARMOUR BROKEN")
	else:
		m.hud.toast("CANNON DOWN" if d["kind"] == "warden" else "SHARD DOWN")


## Smart bomb: hurts every part and the body.
static func bomb(m, dmg: float) -> void:
	for p in m.boss["parts"].duplicate():
		if not p["dead"]:
			m._damage_target(p, dmg)
	if not m.boss.is_empty():
		m._damage_target(m.boss, dmg)


# ---------------------------------------------------------------------------- behaviour

static func update(m, delta: float) -> void:
	var d: Dictionary = m.boss
	d["t"] += delta
	d["entry"] = minf(float(d["entry"]) + delta / 3.0, 1.0)
	d["clang"] = maxf(float(d["clang"]) - delta, 0.0)
	var n: Node3D = d["n"]
	if float(d["flash"]) > 0.0:
		d["flash"] = float(d["flash"]) - delta
		if float(d["flash"]) <= 0.0:
			Util.flash(n, false)
	for p in d["parts"]:
		if not p["dead"] and float(p["flash"]) > 0.0:
			p["flash"] = float(p["flash"]) - delta
			if float(p["flash"]) <= 0.0:
				Util.flash(p["n"], false)
	match d["kind"]:
		"warden":
			_warden(m, d, delta)
		"geode":
			_geode(m, d, delta)
		_:
			_rival(m, d, delta)


static func _pulse(core: MeshInstance3D, d: Dictionary, windup: bool) -> void:
	core.scale = Vector3.ONE * (1.5 if windup else 1.0 + 0.12 * sin(float(d["t"]) * 6.0))
	if float(d["flash"]) <= 0.0:
		(core.material_override as StandardMaterial3D).emission_energy_multiplier = 5.0 if windup else 1.5


static func _warden(m, d: Dictionary, delta: float) -> void:
	var n: Node3D = d["n"]
	var sp: Vector3 = m.ship.global_position
	var t: float = d["t"]
	var entry: float = d["entry"]
	var exposed: bool = not d["shielded"]
	var enraged: bool = d["hp"] < d["max"] * 0.5
	var sway := 0.8 * (1.5 if exposed else 1.0) * (1.4 if enraged else 1.0)
	var eased := 1.0 - pow(1.0 - entry, 3.0)

	var tx := sin(t * sway) * 16.0
	var zoff := lerpf(200.0, 70.0, entry)
	var xspeed := 16.0
	var lunge: float = d["lunge"]
	if exposed and entry >= 1.0 and lunge < 0.0:
		d["lunge_cd"] = float(d["lunge_cd"]) - delta
		if float(d["lunge_cd"]) <= 0.0:
			lunge = 0.0
			d["lunge_cd"] = 5.0 if enraged else 7.0
	var charging := false
	if lunge >= 0.0:
		lunge += delta
		if lunge < 0.9:  # telegraph: slides onto your lane, core flaring
			tx = sp.x
			xspeed = 26.0
			zoff = 70.0
			charging = true
		elif lunge < 1.8:  # committed: no more steering, dives at you
			tx = d["x"]
			xspeed = 0.0
			zoff = lerpf(70.0, 6.0, clampf((lunge - 0.9) / 0.5, 0.0, 1.0))
		elif lunge < 2.8:
			zoff = lerpf(6.0, 70.0, lunge - 1.8)
		else:
			lunge = -1.0
		d["lunge"] = lunge
	d["x"] = move_toward(float(d["x"]), tx, xspeed * delta)
	var ty := sin(t * sway * 1.3) * 5.0
	if lunge >= 0.0 and lunge < 1.8:
		ty = sp.y
	d["y"] = move_toward(float(d["y"]), ty, 14.0 * delta)
	var prev_x := n.position.x
	n.position = Vector3(d["x"], d["y"], m.rig.position.z - zoff)
	var vx := (n.position.x - prev_x) / maxf(delta, 0.0001)
	n.rotation.z = (1.0 - eased) * TAU * 2.0 - vx * 0.012
	n.rotation.x = sin(t * 1.3) * 0.08

	# Contact: box test against its body while diving.
	var rel: Vector3 = sp - n.global_position
	if absf(rel.x) < 8.0 and absf(rel.y) < 3.8 and absf(rel.z) < 8.0:
		m._hurt(30.0)

	var core: MeshInstance3D = n.get_node("Core")
	var sh = n.get_node_or_null("Shield")
	if sh and sh.visible:
		sh.scale = Vector3.ONE * (1.0 + 0.04 * sin(t * 5.0))
	if entry < 1.0:
		_pulse(core, d, false)
		return
	if not exposed:
		# Cannons track you and fire aimed bursts, staggered.
		for p in d["parts"]:
			if p["dead"]:
				continue
			var g: Node3D = p["n"]
			g.look_at(sp)
			g.rotate_object_local(Vector3.UP, PI)
			p["fire"] = float(p["fire"]) - delta
			if float(p["fire"]) <= 0.0:
				p["fire"] = 1.5 if enraged else 2.0
				for i in range(-1, 2):
					m._enemy_shot(g.global_position, sp + m._rig_right() * i * 3.0)
		_pulse(core, d, false)
		return
	d["fire"] = float(d["fire"]) - delta
	var windup: bool = float(d["fire"]) < 0.45 or charging
	_pulse(core, d, windup)
	if float(d["fire"]) <= 0.0:
		d["fire"] = 0.75 if enraged else 1.2
		if lunge < 0.0:
			var spread := 2 if enraged else 1
			for i in range(-spread, spread + 1):
				m._enemy_shot(n.global_position, sp + m._rig_right() * i * 4.0)


static func _geode(m, d: Dictionary, delta: float) -> void:
	var n: Node3D = d["n"]
	var sp: Vector3 = m.ship.global_position
	var t: float = d["t"]
	var entry: float = d["entry"]
	var dead := 4 - live_parts(d)
	var cracked := dead >= 4
	var sway := 0.6 + 0.12 * dead
	n.position = Vector3(sin(t * sway) * 14.0, sin(t * sway * 1.4) * 5.0, m.rig.position.z - lerpf(200.0, 95.0, entry))
	n.rotation.z += delta * (0.4 if cracked else 0.2)
	var ring: Node3D = n.get_node("Ring")
	ring.rotation.z += delta * (1.1 + 0.5 * dead)
	for p in d["parts"]:
		if not p["dead"]:
			(p["n"] as Node3D).rotation.z += delta * 2.0

	var rel: Vector3 = sp - n.global_position
	if rel.length() < 8.0:
		m._hurt(30.0)

	var core: MeshInstance3D = n.get_node("Core")
	d["throw"] = float(d["throw"]) - delta
	_pulse(core, d, float(d["throw"]) < 0.5 and entry >= 1.0)
	if entry < 1.0 or float(d["throw"]) > 0.0:
		return
	d["throw"] = 2.2 if cracked else 3.8 - 0.5 * dead
	# Boulders led onto where you will be. Shoot them apart, bat them back, or fly around.
	var count := 3 if cracked else 1
	for i in count:
		var from := n.global_position + Vector3(0, 1.0, 4.0)
		var flight := from.distance_to(sp) / 40.0
		var lead: Vector3 = sp + m._rig_forward() * 30.0 * float(m.speed_mult) * flight
		lead += m._rig_right() * (i - (count - 1) * 0.5) * 9.0
		m._spawn_rock(from, 2, (lead - from).normalized() * 40.0)
	m._sfx("launch")


static func _rival(m, d: Dictionary, delta: float) -> void:
	var n: Node3D = d["n"]
	var sp: Vector3 = m.ship.global_position
	var fwd: Vector3 = m._rig_forward()
	var pos := n.global_position
	var dir: Vector3 = d["dir"]
	var enraged: bool = d["hp"] < d["max"] * 0.5
	var arena := float(m.cfg["arena"])
	d["state_t"] = float(d["state_t"]) - delta

	var want := dir
	var speed := 36.0 * (1.15 if enraged else 1.0)
	var turn := 1.9 * (1.25 if enraged else 1.0)
	if d["state"] == "hunt":
		want = ((sp - fwd * 22.0) - pos).normalized()  # get on your tail
		if float(d["state_t"]) <= 0.0:
			d["state"] = "break"
			d["state_t"] = 4.5
			var away := pos - sp
			away.y = 0.0
			if away.length() < 1.0:
				away = -fwd
			d["flee"] = away.normalized().rotated(Vector3.UP, randf_range(0.7, 1.2) * (1.0 if randf() < 0.5 else -1.0))
	else:
		want = d["flee"]
		turn = 1.4
		speed *= 1.1
		if float(d["state_t"]) <= 0.0:
			d["state"] = "hunt"
			d["state_t"] = 7.0
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > arena - 40.0:
		want = Vector3(-pos.x, 0.0, -pos.z).normalized()
	if pos.y > 16.0:
		want.y = -0.5
	elif pos.y < -8.0:
		want.y = 0.5
	want = want.normalized()
	var old := dir
	if dir.dot(want) < -0.995:
		want = (want + dir.cross(Vector3.UP).normalized() * 0.4).normalized()
	dir = dir.slerp(want, clampf(turn * delta, 0.0, 1.0)).normalized()
	d["dir"] = dir
	pos += dir * speed * delta
	n.global_position = pos
	n.look_at(pos + dir, Vector3.UP)
	var turn_rate := old.cross(dir).y / maxf(delta, 0.0001)
	d["bank"] = lerpf(float(d["bank"]), clampf(turn_rate * 0.6, -1.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	n.rotate_object_local(Vector3(0, 0, 1), float(d["bank"]))

	# Engines flare when you are on its tail: that is the only place it can be hurt.
	var behind := not is_front_hit(d, sp)
	for e in n.find_children("Engine", "MeshInstance3D", true, false):
		var em: StandardMaterial3D = e.material_override
		em.emission_energy_multiplier = lerpf(em.emission_energy_multiplier, 5.0 if behind else 0.8, clampf(delta * 8.0, 0.0, 1.0))

	# Fire when it has you lined up.
	d["fire"] = float(d["fire"]) - delta
	var to_ship := sp - pos
	if float(d["fire"]) <= 0.0 and d["entry"] >= 1.0 and to_ship.length() < 90.0 and dir.dot(to_ship.normalized()) > 0.93:
		d["fire"] = 0.35 if enraged else 0.5
		m._enemy_shot(pos + dir * 4.0, sp)
	if to_ship.length() < 6.0:
		m._hurt(25.0)
	d["summon"] = float(d["summon"]) - delta
	if float(d["summon"]) <= 0.0 and m.foes.size() < 3 and d["entry"] >= 1.0:
		d["summon"] = 9.0 if enraged else 13.0
		for i in 2:
			m._spawn_chaser()

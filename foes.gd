extends RefCounted
## Enemy models and their animation. Gameplay (movement, damage) stays in main.gd.
## Kinds: drone (weaving fighter), diver (kamikaze needle), tank (turret), ace (rolls to dodge).

const Util = preload("res://util.gd")


static func build(kind: String) -> Node3D:
	var n := Node3D.new()
	match kind:
		"tank":
			n.add_child(Util.box(Vector3(3.0, 0.9, 3.4), Color(0.5, 0.5, 0.58)))
			for side in [-1.0, 1.0]:
				n.add_child(Util.box(Vector3(0.7, 0.7, 3.8), Color(0.2, 0.2, 0.24), Vector3(side * 1.7, -0.2, 0)))
			n.add_child(Util.box(Vector3(5.2, 0.15, 1.0), Color(0.3, 0.3, 0.38), Vector3(0, 0.3, 0.6)))
			var tur := Node3D.new()
			tur.name = "Turret"
			tur.position = Vector3(0, 0.8, 0)
			tur.add_child(Util.box(Vector3(1.6, 0.7, 1.6), Color(0.38, 0.38, 0.46)))
			tur.add_child(Util.ball(0.6, Color(0.3, 0.3, 0.38), Vector3(0, 0.4, 0)))
			var barrel := Util.tube(0.16, 2.2, Color(0.18, 0.18, 0.22), Vector3(0, 0.1, -1.4))
			barrel.name = "Barrel"
			tur.add_child(barrel)
			tur.add_child(Util.glow(Util.ball(0.2, Color(1.0, 0.3, 0.2), Vector3(0, 0.7, 0.4)), Color(1.0, 0.2, 0.1), 2.0))
			n.add_child(tur)
		"diver":
			n.add_child(Util.cone(0.5, 3.0, Color(1.0, 0.85, 0.2), Vector3(0, 0, -0.3), false, 5))
			var spin := Node3D.new()
			spin.name = "Spin"
			for i in 3:
				var fin := Util.box(Vector3(0.1, 0.9, 0.9), Color(0.8, 0.55, 0.1), Vector3(0, 0, 1.0))
				var holder := Node3D.new()
				holder.rotation.z = i * TAU / 3.0
				fin.position = Vector3(0, 0.55, 1.0)
				holder.add_child(fin)
				spin.add_child(holder)
			n.add_child(spin)
			var g := Util.glow(Util.cone(0.35, 1.2, Color(1.0, 0.4, 0.1), Vector3(0, 0, 1.9), true), Color(1.0, 0.4, 0.1), 3.0)
			g.name = "Glow"
			n.add_child(g)
		"ace":
			var roll := Node3D.new()
			roll.name = "Roll"
			roll.add_child(Util.box(Vector3(0.9, 0.4, 2.4), Color(0.5, 0.2, 0.7)))
			roll.add_child(Util.cone(0.38, 1.6, Color(0.5, 0.2, 0.7), Vector3(0, 0, -1.9), false, 5))
			roll.add_child(Util.glow(Util.ball(0.3, Color(1.0, 0.9, 0.3), Vector3(0, 0.3, -0.3), Vector3(1, 0.7, 1.8)), Color(1.0, 0.8, 0.2), 1.0))
			_wings(roll, Color(0.3, 0.1, 0.45), 2.2, 1.2, -0.35)  # forward-swept
			for side in [-1.0, 1.0]:
				var g := Util.glow(Util.tube(0.22, 0.4, Color(1.0, 0.4, 0.9), Vector3(side * 0.5, 0, 1.3)), Color(1.0, 0.3, 0.9), 3.0)
				g.name = "Glow"
				roll.add_child(g)
			n.add_child(roll)
		_:
			var roll := Node3D.new()
			roll.name = "Roll"
			roll.add_child(Util.box(Vector3(0.9, 0.5, 2.0), Color(0.85, 0.2, 0.2)))
			roll.add_child(Util.cone(0.36, 1.4, Color(0.85, 0.2, 0.2), Vector3(0, 0, -1.6), false, 5))
			roll.add_child(Util.ball(0.32, Color(0.3, 0.05, 0.05), Vector3(0, 0.3, -0.4), Vector3(1, 0.7, 1.6)))
			_wings(roll, Color(0.55, 0.1, 0.1), 1.8, 1.0, 0.25)
			var g := Util.glow(Util.tube(0.25, 0.4, Color(1.0, 0.5, 0.2), Vector3(0, 0, 1.2)), Color(1.0, 0.4, 0.1), 2.5)
			g.name = "Glow"
			roll.add_child(g)
			n.add_child(roll)
	return n


## Wing pair on pivots so they can flap; sweep > 0 swept back.
static func _wings(parent: Node3D, color: Color, span: float, chord: float, sweep: float) -> void:
	for side in [-1.0, 1.0]:
		var p := Node3D.new()
		p.name = "WingL" if side < 0.0 else "WingR"
		p.position = Vector3(side * 0.4, 0, 0.2)
		p.rotation.y = -side * sweep
		p.add_child(Util.box(Vector3(span, 0.09, chord), color, Vector3(side * span * 0.5, 0, 0)))
		p.add_child(Util.box(Vector3(0.1, 0.4, chord * 0.6), Color(0.95, 0.85, 0.3), Vector3(side * span, 0.18, 0)))
		parent.add_child(p)


static func _find(n: Node, name: String) -> Node3D:
	return n.find_child(name, true, false) as Node3D


## Per-frame animation. f carries: t (alive time), age, bank (target roll), flash, recoil,
## roll_t / rolling (cosmetic barrel rolls; the ace is untouchable by lasers while rolling), diving.
static func animate(f: Dictionary, delta: float, sp: Vector3) -> void:
	var n: Node3D = f["n"]
	var t: float = f["t"]
	var kind: String = f["kind"]
	var k := clampf(delta * 8.0, 0.0, 1.0)

	# Pop in from small instead of appearing at full size.
	var grow := clampf(float(f["age"]) / 0.5, 0.0, 1.0)
	n.scale = Vector3.ONE * (0.3 + 0.7 * (1.0 - pow(1.0 - grow, 3.0)))

	# Bank into turns. Chasers are re-oriented by look_at every frame, so they apply it directly.
	var bank: float = f["bank"]
	if f["mode"] == "chase":
		n.rotation.z = bank
	elif kind == "tank":
		n.rotation.z = lerpf(n.rotation.z, bank * 0.4, k)
	elif kind != "diver" or not f.get("diving", false):
		n.rotation.z = lerpf(n.rotation.z, bank, k)

	for g in n.find_children("Glow", "MeshInstance3D", true, false):
		g.scale = Vector3(1, 1, (0.8 + 0.4 * sin(t * 40.0)) * (2.0 if f.get("diving", false) else 1.0))

	match kind:
		"tank":
			var tur := _find(n, "Turret")
			var d := sp - n.global_position
			tur.rotation.y = lerp_angle(tur.rotation.y, atan2(-d.x, -d.z), k * 0.6)
			var barrel := _find(n, "Barrel")
			f["recoil"] = maxf(float(f["recoil"]) - delta * 5.0, 0.0)
			barrel.position.z = -1.4 + float(f["recoil"]) * 0.7  # kicks back when it fires
		"diver":
			var spin := _find(n, "Spin")
			spin.rotation.z += delta * (14.0 if f.get("diving", false) else 3.0)
		_:
			var flap := sin(t * 9.0) * (0.45 if kind == "drone" else 0.2)
			_find(n, "WingL").rotation.z = flap
			_find(n, "WingR").rotation.z = -flap
			n.rotation.x = lerpf(n.rotation.x, sin(t * 2.0) * 0.08, k) if f["mode"] != "chase" else n.rotation.x
			_roll_cycle(f, delta, kind == "ace")

	if float(f["flash"]) > 0.0:
		f["flash"] = float(f["flash"]) - delta
		if float(f["flash"]) <= 0.0:
			Util.flash(n, false)


## Occasional barrel roll. Aces roll more often, and are immune to lasers while doing it.
static func _roll_cycle(f: Dictionary, delta: float, ace: bool) -> void:
	var roll := _find(f["n"], "Roll")
	if roll == null:
		return
	if float(f["rolling"]) > 0.0:
		f["rolling"] = float(f["rolling"]) - delta
		var prog := 1.0 - maxf(float(f["rolling"]), 0.0) / 0.5
		roll.rotation.z = prog * TAU
		if float(f["rolling"]) <= 0.0:
			roll.rotation.z = 0.0
	else:
		f["roll_t"] = float(f["roll_t"]) - delta
		if float(f["roll_t"]) <= 0.0:
			f["rolling"] = 0.5
			f["roll_t"] = randf_range(1.2, 2.6) if ace else randf_range(3.0, 6.0)

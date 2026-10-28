extends RefCounted
## Small helpers shared by the game scripts.


static func mesh(m: Mesh, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(b, color, pos)


static func glow(mi: MeshInstance3D, color: Color, energy := 1.5) -> MeshInstance3D:
	var m: StandardMaterial3D = mi.material_override
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return mi


## Cone pointing -Z (the nose direction), or +Z when back is set (exhaust flames).
static func cone(r: float, h: float, color: Color, pos := Vector3.ZERO, back := false, seg := 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var mi := mesh(c, color, pos)
	mi.rotation.x = PI * 0.5 if back else -PI * 0.5
	return mi


static func ball(r: float, color: Color, pos := Vector3.ZERO, squash := Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	var mi := mesh(s, color, pos)
	mi.scale = squash
	return mi


## Cylinder lying along Z (engine pods, barrels).
static func tube(r: float, h: float, color: Color, pos := Vector3.ZERO, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var mi := mesh(c, color, pos)
	mi.rotation.x = PI * 0.5
	return mi


## White hit-flash on every mesh under n. The material's own glow is remembered and restored.
static func flash(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override
			if on:
				if not m.has_meta("em0"):
					m.set_meta("em0", [m.emission_enabled, m.emission, m.emission_energy_multiplier])
				m.emission_enabled = true
				m.emission = Color(1, 1, 1)
				m.emission_energy_multiplier = 1.5
			elif m.has_meta("em0"):
				var e: Array = m.get_meta("em0")
				m.emission_enabled = e[0]
				m.emission = e[1]
				m.emission_energy_multiplier = e[2]
				m.remove_meta("em0")
		flash(c, on)


## Synthesised sound effect: sine sweep mixed with noise, quadratic decay. No audio assets needed.
static func tone(freq: float, dur: float, noise := 0.0, slide := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * maxf(freq + slide * t, 20.0) / rate
		var s := sin(ph) * (1.0 - noise) + (randf() * 2.0 - 1.0) * noise
		s *= (1.0 - t) * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 12000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


static func burst(parent: Node, pos: Vector3, color: Color, amount := 24, power := 1.0) -> void:
	var p := CPUParticles3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.35, 0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material = mat
	p.mesh = b
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 5.0 * power
	p.initial_velocity_max = 14.0 * power
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true


static func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


static func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


static func setup_input() -> void:
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("charge", MOUSE_BUTTON_RIGHT)
	_bind_mouse("bomb", MOUSE_BUTTON_MIDDLE)
	_bind("bomb", [KEY_B])
	_bind("left", [KEY_A, KEY_LEFT])
	_bind("right", [KEY_D, KEY_RIGHT])
	_bind("up", [KEY_W, KEY_UP])
	_bind("down", [KEY_S, KEY_DOWN])
	_bind("fire", [KEY_SPACE])
	_bind("charge", [KEY_C, KEY_X])
	_bind("boost", [KEY_SHIFT])
	_bind("brake", [KEY_CTRL, KEY_Z])
	_bind("loop", [KEY_F])
	_bind("roll_l", [KEY_Q])
	_bind("roll_r", [KEY_E])
	_bind("restart", [KEY_R])
	_bind("pause", [KEY_P, KEY_ESCAPE])

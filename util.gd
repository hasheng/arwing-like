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


static func setup_input() -> void:
	_bind("left", [KEY_A, KEY_LEFT])
	_bind("right", [KEY_D, KEY_RIGHT])
	_bind("up", [KEY_W, KEY_UP])
	_bind("down", [KEY_S, KEY_DOWN])
	_bind("fire", [KEY_SPACE])
	_bind("charge", [KEY_SHIFT, KEY_C])
	_bind("roll_l", [KEY_Q])
	_bind("roll_r", [KEY_E])
	_bind("restart", [KEY_R])
	_bind("pause", [KEY_P, KEY_ESCAPE])

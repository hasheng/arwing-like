extends Node3D
## Player ship. Moves in a 2D plane relative to the rig that flies down the level.
## Animation lives here: banking, aileron flex, wing sweep (boost) and air-brake flaps, engine
## flames and exhaust trail, wingtip vapour, shield bubble, barrel roll and loop.

const Util = preload("res://util.gd")
const MOVE_SPEED := 24.0
const ACCEL := 110.0
const LIMIT := Vector2(30.0, 14.0)

var rolling := false   # barrel roll: reflects enemy shots
var looping := false   # somersault: shots pass through
var bank := 0.0        # current bank angle, read by the camera

var _tilt: Node3D
var _roll: Node3D
var _wing := {}        # side (-1/+1) -> {pivot, tip}
var _flames: Array = []
var _reticle: Node3D
var _shield: MeshInstance3D
var _exhaust: Array = []
var _vapour: Array = []
var _vel := Vector2.ZERO
var _thrust := 0.0
var _t := 0.0


var evading: bool:
	get: return rolling or looping


func _ready() -> void:
	_tilt = Node3D.new()
	add_child(_tilt)
	_roll = Node3D.new()
	_tilt.add_child(_roll)
	var hull := Color(0.82, 0.85, 0.92)
	var dark := Color(0.35, 0.38, 0.48)
	var blue := Color(0.15, 0.4, 0.9)
	var red := Color(0.9, 0.25, 0.25)

	# Fuselage: tapered nose, body, canopy, spine.
	_roll.add_child(Util.box(Vector3(0.95, 0.45, 2.4), hull, Vector3(0, 0, 0.3)))
	_roll.add_child(Util.cone(0.42, 1.8, hull, Vector3(0, 0, -1.7), false, 6))
	_roll.add_child(Util.cone(0.1, 0.5, red, Vector3(0, 0, -2.75), false, 4))
	_roll.add_child(Util.glow(Util.ball(0.42, Color(0.4, 0.9, 1.0), Vector3(0, 0.32, -0.5), Vector3(0.9, 0.7, 2.0)), Color(0.2, 0.6, 0.9), 0.6))
	_roll.add_child(Util.box(Vector3(0.3, 0.2, 1.6), dark, Vector3(0, 0.3, 1.0)))
	# Twin tail fins, canted outward.
	for side in [-1.0, 1.0]:
		var fin := Util.box(Vector3(0.1, 1.0, 0.9), blue, Vector3(side * 0.35, 0.55, 1.35))
		fin.rotation.z = -side * 0.25
		_roll.add_child(fin)
	# Engine pods with flames.
	for side in [-1.0, 1.0]:
		_roll.add_child(Util.tube(0.28, 1.6, dark, Vector3(side * 0.75, -0.05, 0.7)))
		_roll.add_child(Util.glow(Util.tube(0.3, 0.12, Color(1.0, 0.6, 0.2), Vector3(side * 0.75, -0.05, 1.5)), Color(1.0, 0.5, 0.1), 2.0))
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.75, -0.05, 1.56)
		var flame := Util.glow(Util.cone(0.24, 1.4, Color(1.0, 0.6, 0.2), Vector3(0, 0, 0.7), true), Color(1.0, 0.5, 0.1), 3.0)
		pivot.add_child(flame)
		_roll.add_child(pivot)
		_flames.append({"pivot": pivot, "mat": flame.material_override})
	# Swept wings: inner root + flexing tip aileron, red tip fin.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.45, 0, 0.7)
		pivot.rotation.y = -side * 0.12  # slight sweep back
		pivot.add_child(Util.box(Vector3(1.7, 0.1, 1.6), blue, Vector3(side * 0.85, 0, 0)))
		pivot.add_child(Util.box(Vector3(1.7, 0.1, 0.5), dark, Vector3(side * 0.85, 0.02, 0.8)))
		var tip := Node3D.new()
		tip.position = Vector3(side * 1.7, 0, 0.1)
		tip.add_child(Util.box(Vector3(1.0, 0.09, 1.2), hull, Vector3(side * 0.5, 0, 0)))
		tip.add_child(Util.box(Vector3(0.12, 0.45, 0.8), red, Vector3(side * 1.0, 0.22, 0.1)))
		pivot.add_child(tip)
		_roll.add_child(pivot)
		_wing[side] = {"pivot": pivot, "tip": tip}
		# Exhaust trail and wingtip vapour live in world space so they stay behind as we fly.
		var ex := _trail(Color(1.0, 0.6, 0.2), 0.12, 0.3, 5.0)
		ex.position = Vector3(side * 0.75, -0.05, 1.7)
		_roll.add_child(ex)
		_exhaust.append(ex)
		var vp := _trail(Color(0.9, 0.95, 1.0), 0.14, 0.7, 0.0)
		vp.position = Vector3(side * 3.2, 0, 0.8)
		vp.emitting = false
		_roll.add_child(vp)
		_vapour.append(vp)

	# Shield bubble, shown while the shield power-up lasts.
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.3, 0.6, 1.0, 0.22)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.emission_enabled = true
	smat.emission = Color(0.2, 0.5, 1.0)
	_shield = MeshInstance3D.new()
	_shield.mesh = sphere
	_shield.material_override = smat
	_shield.visible = false
	add_child(_shield)

	# Aiming reticle: follows the mouse (see set_aim_world).
	_reticle = Node3D.new()
	_reticle.position = Vector3(0, 0, -28)
	for i in 4:
		var bar := Util.box(Vector3(1.6, 0.12, 0.12), Color(0.5, 1.0, 0.6))
		bar.rotation.z = i * PI * 0.5
		bar.position = Vector3.RIGHT.rotated(Vector3.BACK, i * PI * 0.5) * 1.6
		_reticle.add_child(bar)
	add_child(_reticle)


func _trail(color: Color, size: float, life: float, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(size, size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material = mat
	p.mesh = b
	p.amount = 18
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 6.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = speed
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	return p


func steer(dir: Vector2, delta: float, strafe := true) -> void:
	# Velocity eases toward the stick, so turns have weight instead of snapping.
	_vel = _vel.move_toward(dir * MOVE_SPEED, ACCEL * delta)
	if strafe:
		position.x = clampf(position.x + _vel.x * delta, -LIMIT.x, LIMIT.x)
	else:
		position.x = lerpf(position.x, 0.0, clampf(delta * 6.0, 0.0, 1.0))  # all-range: A/D turn the whole rig
	position.y = clampf(position.y + _vel.y * delta, -LIMIT.y, LIMIT.y)
	var k := clampf(delta * 7.0, 0.0, 1.0)
	var nx := _vel.x / MOVE_SPEED
	var ny := _vel.y / MOVE_SPEED
	_tilt.rotation.z = lerpf(_tilt.rotation.z, -nx * 0.9, k)
	_tilt.rotation.x = lerpf(_tilt.rotation.x, ny * 0.45, k)
	_tilt.rotation.y = lerpf(_tilt.rotation.y, -nx * 0.3, k)
	bank = _tilt.rotation.z
	_t += delta
	# Ailerons flex into the turn, opposite on each wing.
	for side in _wing:
		var tip: Node3D = _wing[side]["tip"]
		tip.rotation.z = lerpf(tip.rotation.z, -side * nx * 0.5, k)
	for v in _vapour:
		v.emitting = absf(bank) > 0.35 or _thrust > 0.5


## -1 = air brake, 0 = cruise, +1 = boost.
func set_thrust(target: float, delta: float) -> void:
	_thrust = lerpf(_thrust, target, clampf(delta * 6.0, 0.0, 1.0))
	var b := maxf(_thrust, 0.0)
	var br := maxf(-_thrust, 0.0)
	for side in _wing:
		var pivot: Node3D = _wing[side]["pivot"]
		# Sweep back on boost, flap up on brake.
		pivot.rotation = Vector3(0, -side * (0.12 + 0.35 * b), side * 0.7 * br)
	for f in _flames:
		var pivot: Node3D = f["pivot"]
		pivot.scale.z = (1.0 + 2.2 * b - 0.5 * br) * (0.9 + 0.2 * sin(_t * 45.0))
		var m: StandardMaterial3D = f["mat"]
		m.emission = Color(1.0, 0.5, 0.1).lerp(Color(0.4, 0.8, 1.0), b)
		m.albedo_color = m.emission
		m.emission_energy_multiplier = 2.0 + 4.0 * b
	for e in _exhaust:
		e.lifetime = clampf(0.25 + 0.3 * b - 0.1 * br, 0.1, 0.6)  # longer trail when boosting


func set_shield(ratio: float, delta: float) -> void:
	_shield.visible = ratio > 0.0
	if _shield.visible:
		var m: StandardMaterial3D = _shield.material_override
		# Flicker harder as it runs low.
		var flick := 1.0 if ratio > 0.3 else 0.5 + 0.5 * sin(_t * 30.0)
		m.albedo_color.a = 0.22 * flick
		_shield.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 8.0))


## The reticle is the mouse cursor: it sits wherever the aim ray meets the aim plane.
func set_aim_world(p: Vector3) -> void:
	_reticle.global_position = p


func set_aiming(charging: bool, t: float, delta: float) -> void:
	var m: StandardMaterial3D
	for c in _reticle.get_children():
		m = c.material_override
		m.albedo_color = Color(1.0, 0.3, 0.3) if charging else Color(0.5, 1.0, 0.6)
	_reticle.rotation.z = t * 3.0 if charging else lerpf(_reticle.rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_reticle.scale = Vector3.ONE * (1.0 + (0.4 if charging else 0.0))


func barrel_roll(side: float) -> void:
	if rolling:
		return
	rolling = true
	var tw := create_tween()
	tw.tween_property(_roll, "rotation:z", -side * TAU, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_roll_done)


func _roll_done() -> void:
	_roll.rotation.z = 0.0
	rolling = false


func loop() -> void:
	if looping:
		return
	looping = true
	var tw := create_tween()
	tw.tween_property(_roll, "rotation:x", TAU, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_loop_done)


func _loop_done() -> void:
	_roll.rotation.x = 0.0
	looping = false

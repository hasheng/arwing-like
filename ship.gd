extends Node3D
## Player ship. Moves in a 2D plane relative to the rig that flies down the level.

const Util = preload("res://util.gd")
const MOVE_SPEED := 14.0
const LIMIT := Vector2(12.0, 7.0)

var rolling := false
var _tilt: Node3D
var _roll: Node3D


func _ready() -> void:
	_tilt = Node3D.new()
	add_child(_tilt)
	_roll = Node3D.new()
	_tilt.add_child(_roll)
	var hull := Color(0.75, 0.78, 0.85)
	var accent := Color(0.2, 0.45, 0.9)
	_roll.add_child(Util.box(Vector3(0.9, 0.4, 3.0), hull))
	_roll.add_child(Util.box(Vector3(4.2, 0.1, 1.3), accent, Vector3(0, 0, 0.6)))
	_roll.add_child(Util.box(Vector3(0.12, 0.9, 0.9), accent, Vector3(0, 0.5, 1.2)))
	_roll.add_child(Util.box(Vector3(0.5, 0.3, 0.8), Color(0.9, 0.8, 0.3), Vector3(0, 0.3, -0.4)))


func steer(dir: Vector2, delta: float) -> void:
	position.x = clampf(position.x + dir.x * MOVE_SPEED * delta, -LIMIT.x, LIMIT.x)
	position.y = clampf(position.y + dir.y * MOVE_SPEED * delta, -LIMIT.y, LIMIT.y)
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_tilt.rotation.z = lerpf(_tilt.rotation.z, -dir.x * 0.5, k)
	_tilt.rotation.x = lerpf(_tilt.rotation.x, dir.y * 0.3, k)


func barrel_roll(side: float) -> void:
	if rolling:
		return
	rolling = true
	var tw := create_tween()
	tw.tween_property(_roll, "rotation:z", -side * TAU, 0.5)
	tw.finished.connect(_roll_done)


func _roll_done() -> void:
	_roll.rotation.z = 0.0
	rolling = false

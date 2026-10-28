extends RefCounted
## Level hazards placed in the flight path. Each spawn returns the node plus world-space AABBs
## for collision, so the ship can fly around, between or through the gaps.

const Util = preload("res://util.gd")
const FLOOR := -16.0
const CEIL := 24.0


static func spawn(parent: Node3D, z: float, kind: String, color: Color, at_x := NAN) -> Dictionary:
	var n := Node3D.new()
	parent.add_child(n)
	var boxes: Array = []
	match kind:
		"arch":
			var cx := randf_range(-16.0, 16.0) if is_nan(at_x) else at_x
			var cy := randf_range(-4.0, 6.0)
			var gap := 7.0
			var top := cy + gap
			var h := top - FLOOR
			_add(n, boxes, Vector3(cx - gap - 1.5, FLOOR + h * 0.5, z), Vector3(3, h, 3), color)
			_add(n, boxes, Vector3(cx + gap + 1.5, FLOOR + h * 0.5, z), Vector3(3, h, 3), color)
			_add(n, boxes, Vector3(cx, top + 1.5, z), Vector3(gap * 2.0 + 6.0, 3, 3), color.lightened(0.15))
		"wall":
			# Full-width wall with one hole to thread: the ship has to commit to a line.
			var hx := randf_range(-18.0, 18.0)
			var hy := randf_range(-7.0, 8.0)
			var hw := 7.0
			var hh := 5.0
			_rect(n, boxes, z, -45.0, hx - hw, FLOOR, CEIL, color)
			_rect(n, boxes, z, hx + hw, 45.0, FLOOR, CEIL, color)
			_rect(n, boxes, z, hx - hw, hx + hw, FLOOR, hy - hh, color)
			_rect(n, boxes, z, hx - hw, hx + hw, hy + hh, CEIL, color)
		_:
			var x := randf_range(-24.0, 24.0) if is_nan(at_x) else at_x
			var h := randf_range(14.0, 28.0)
			_add(n, boxes, Vector3(x, FLOOR + h * 0.5, z), Vector3(4, h, 4), color)
	return {"n": n, "z": z, "boxes": boxes}


static func _rect(n: Node3D, boxes: Array, z: float, x0: float, x1: float, y0: float, y1: float, color: Color) -> void:
	if x1 - x0 < 0.1 or y1 - y0 < 0.1:
		return
	_add(n, boxes, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z), Vector3(x1 - x0, y1 - y0, 3.0), color)


static func _add(n: Node3D, boxes: Array, center: Vector3, size: Vector3, color: Color) -> void:
	n.add_child(Util.box(size, color, center))
	boxes.append(AABB(center - size * 0.5, size))


## Asteroid of size 1..3. Size sets radius and toughness; bigger ones split when destroyed.
const ROCK_RADIUS := [0.0, 1.5, 2.8, 4.5]
const ROCK_HP := [0, 1, 3, 6]


static func rock(parent: Node3D, pos: Vector3, size: int, color: Color) -> Node3D:
	var r: float = ROCK_RADIUS[size]
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 7
	s.rings = 4
	var mi := Util.mesh(s, color.darkened(randf_range(0.0, 0.35)))
	mi.scale = Vector3(randf_range(0.8, 1.2), randf_range(0.8, 1.2), randf_range(0.8, 1.2))
	n.add_child(mi)
	n.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	return n


## Flight ring: fly through the middle to build a combo.
static func ring(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	for i in 12:
		var a := i * TAU / 12.0
		var seg := Util.glow(Util.box(Vector3(1.6, 0.5, 0.5), Color(0.3, 1.0, 1.0)), Color(0.2, 0.9, 1.0), 2.0)
		seg.position = Vector3(cos(a), sin(a), 0) * 5.8
		seg.rotation.z = a + PI * 0.5
		n.add_child(seg)
	return n

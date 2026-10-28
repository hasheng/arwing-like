extends RefCounted
## Power-up models. Effects live in main.gd (_collect); each kind has its own shape, colour and label.

const Util = preload("res://util.gd")

const KINDS := {
	"repair": {"label": "REPAIR", "color": Color(0.2, 1.0, 0.4), "weight": 35},
	"shield": {"label": "SHIELD", "color": Color(0.3, 0.6, 1.0), "weight": 22},
	"weapon": {"label": "WEAPON", "color": Color(1.0, 0.9, 0.2), "weight": 20},
	"bomb": {"label": "BOMB", "color": Color(1.0, 0.3, 0.2), "weight": 13},
	"boost": {"label": "OVERDRIVE", "color": Color(0.3, 1.0, 1.0), "weight": 10},
}


static func roll() -> String:
	var total := 0
	for k in KINDS:
		total += int(KINDS[k]["weight"])
	var r := randi() % total
	for k in KINDS:
		r -= int(KINDS[k]["weight"])
		if r < 0:
			return k
	return "repair"


static func build(kind: String) -> Node3D:
	var col: Color = KINDS[kind]["color"]
	var n := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	match kind:
		"repair":  # a plus sign
			body.add_child(Util.glow(Util.box(Vector3(1.7, 0.55, 0.55), col), col))
			body.add_child(Util.glow(Util.box(Vector3(0.55, 1.7, 0.55), col), col))
		"shield":  # a bubble inside a ring
			body.add_child(Util.glow(Util.ball(0.9, col), col, 1.2))
			var ring := Util.glow(Util.tube(1.4, 0.15, col, Vector3.ZERO, 12), col)
			ring.rotation.x = 0.0
			body.add_child(ring)
		"weapon":  # three bolts fanned out
			for i in range(-1, 2):
				var bolt := Util.glow(Util.cone(0.28, 1.6, col, Vector3(i * 0.7, 0, 0)), col)
				bolt.rotation.z = -i * 0.3
				body.add_child(bolt)
		"bomb":  # a mine
			body.add_child(Util.glow(Util.ball(0.8, col), col, 1.0))
			for axis in 3:
				var spike := Util.box(Vector3(2.2, 0.2, 0.2), Color(0.9, 0.9, 0.9))
				spike.rotation = Vector3(0, 0, 0)
				if axis == 1:
					spike.rotation.z = PI * 0.5
				elif axis == 2:
					spike.rotation.y = PI * 0.5
				body.add_child(spike)
		"boost":  # an arrowhead
			body.add_child(Util.glow(Util.cone(0.8, 2.0, col), col))
			body.add_child(Util.glow(Util.tube(0.45, 0.9, col, Vector3(0, 0, 1.3)), col))
	var label := Label3D.new()
	label.text = KINDS[kind]["label"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 36
	label.pixel_size = 0.03
	label.modulate = col
	label.outline_size = 8
	label.position = Vector3(0, 2.3, 0)
	n.add_child(label)
	return n

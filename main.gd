extends Node3D
## Level controller: flies the rig forward, spawns enemies and scenery, resolves hits, draws the HUD.

const Util = preload("res://util.gd")
const Ship = preload("res://ship.gd")

const FORWARD_SPEED := 30.0
const LASER_SPEED := 120.0
const FIRE_COOLDOWN := 0.15
const LEVELS := [
	{
		"name": "CORNERIA-ish", "sky": Color(0.05, 0.07, 0.18), "ground": Color(0.12, 0.3, 0.2),
		"pillar": Color(0.35, 0.3, 0.45), "boss_color": Color(0.45, 0.1, 0.55),
		"boss_z": 1200.0, "boss_hp": 60.0, "spawn": Vector2(0.6, 1.4),
		"foe_speed": 8.0, "shot_speed": 55.0, "mix": {"drone": 1.0},
	},
	{
		"name": "ASTEROID BELT", "sky": Color(0.14, 0.05, 0.08), "ground": Color(0.3, 0.14, 0.08),
		"pillar": Color(0.5, 0.35, 0.25), "boss_color": Color(0.1, 0.45, 0.5),
		"boss_z": 1600.0, "boss_hp": 100.0, "spawn": Vector2(0.4, 1.0),
		"foe_speed": 14.0, "shot_speed": 70.0, "mix": {"drone": 0.6, "diver": 0.4},
	},
	{
		"name": "SPACE STATION", "sky": Color(0.02, 0.02, 0.06), "ground": Color(0.15, 0.16, 0.22),
		"pillar": Color(0.3, 0.32, 0.4), "boss_color": Color(0.7, 0.15, 0.15),
		"boss_z": 2000.0, "boss_hp": 150.0, "spawn": Vector2(0.35, 0.9),
		"foe_speed": 12.0, "shot_speed": 80.0,
		"mix": {"drone": 0.35, "tank": 0.3, "diver": 0.35},
	},
]

## Survive across scene reloads: which level we are on and the score at its start.
static var level_idx := 0
static var carry_score := 0
static var started := false   # false until the title screen has been dismissed once
static var high_score := -1   # -1 = not loaded from disk yet

const SAVE_PATH := "user://save.json"

var cfg: Dictionary
const MISSILE_SPEED := 90.0
const MAX_LOCKS := 4
const LOCK_INTERVAL := 0.25

var rig: Node3D
var ship: Node3D
var cam: Camera3D
var ground: MeshInstance3D
var hud: Label

var lasers: Array = []   # {n: Node3D}
var foes: Array = []     # {n: Node3D, t: float, fire: float, x0: float}
var shots: Array = []    # {n: Node3D, v: Vector3}
var scenery: Array = []
var missiles: Array = [] # {n: Node3D, target: Dictionary}
var locks: Array = []    # target dicts (foes or the boss)
var charge_t := 0.0
var boss: Dictionary = {} # {n, hp, t, fire, entry}
var boss_spawned := false
var pickups: Array = []
var shake := 0.0
var sfx: Dictionary = {}
var sfx_players: Array = []

var hp := 100.0
var score := 0
var state := "play"      # play | dead | won
var spawn_t := 1.0
var scenery_z := 0.0
var fire_t := 0.0


func _ready() -> void:
	randomize()
	Util.setup_input()
	cfg = LEVELS[level_idx]
	score = carry_score
	state = "play" if started else "title"
	if high_score < 0:
		high_score = _load_high()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cfg["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.fog_enabled = true
	env.fog_light_color = cfg["sky"]
	env.fog_density = 0.008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	rig = Node3D.new()
	add_child(rig)
	ship = Ship.new()
	rig.add_child(ship)
	cam = Camera3D.new()
	cam.fov = 70
	rig.add_child(cam)
	cam.look_at_from_position(Vector3(0, 3, 10), Vector3(0, 0, -30))

	ground = Util.box(Vector3(200, 1, 400), cfg["ground"], Vector3(0, -9, 0))
	add_child(ground)

	sfx = {
		"laser": Util.tone(900.0, 0.08, 0.0, -500.0),
		"boom": Util.tone(120.0, 0.4, 0.8, -80.0),
		"hit": Util.tone(200.0, 0.2, 0.5, -100.0),
		"pick": Util.tone(500.0, 0.15, 0.0, 600.0),
		"launch": Util.tone(300.0, 0.25, 0.2, 500.0),
	}
	for i in 8:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		sfx_players.append(ap)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(20, 16)
	hud.add_theme_font_size_override("font_size", 24)
	layer.add_child(hud)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		if state == "won":
			level_idx += 1
			carry_score = score
			if level_idx >= LEVELS.size():
				level_idx = 0
				carry_score = 0
		get_tree().reload_current_scene()
		return

	if state == "title" and Input.is_action_just_pressed("fire"):
		started = true
		state = "play"
	elif Input.is_action_just_pressed("pause"):
		if state == "play":
			state = "paused"
		elif state == "paused":
			state = "play"

	if state == "play":
		_play(delta)
	_update_hud()


func _load_high() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return int(d.get("high_score", 0)) if d is Dictionary else 0


func _end_run(new_state: String) -> void:
	state = new_state
	if score > high_score:
		high_score = score
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"high_score": high_score}))


func _play(delta: float) -> void:
	rig.position.z -= FORWARD_SPEED * delta
	ground.position.z = rig.position.z - 100.0

	var dir := Input.get_vector("left", "right", "down", "up")
	ship.steer(dir, delta)
	shake = maxf(shake - delta * 1.5, 0.0)
	cam.position.x = ship.position.x * 0.4 + randf_range(-shake, shake)
	cam.position.y = 3.0 + ship.position.y * 0.3 + randf_range(-shake, shake)
	if Input.is_action_just_pressed("roll_l"):
		ship.barrel_roll(-1.0)
	if Input.is_action_just_pressed("roll_r"):
		ship.barrel_roll(1.0)

	fire_t -= delta
	if Input.is_action_pressed("fire") and fire_t <= 0.0:
		fire_t = FIRE_COOLDOWN
		_fire()

	_charge(delta)

	if not boss_spawned and -rig.position.z >= cfg["boss_z"]:
		_spawn_boss()
	if not boss_spawned:
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = randf_range(cfg["spawn"].x, cfg["spawn"].y)
			_spawn_foe()
	_spawn_scenery()

	_move_lasers(delta)
	_move_foes(delta)
	_move_boss(delta)
	_move_missiles(delta)
	_move_shots(delta)
	_move_pickups(delta)

	if hp <= 0.0:
		_end_run("dead")
	elif boss_spawned and boss.is_empty():
		_end_run("won")


func _sfx(name: String) -> void:
	for p in sfx_players:
		if not p.playing:
			p.stream = sfx[name]
			p.play()
			return


func _hurt(amount: float) -> void:
	hp -= amount
	shake = 0.6
	_sfx("hit")


func _drop_pickup(pos: Vector3) -> void:
	var n := Util.box(Vector3(1.2, 1.2, 1.2), Color(0.2, 1.0, 0.4), pos)
	add_child(n)
	pickups.append(n)


func _move_pickups(delta: float) -> void:
	var sp := ship.global_position
	for n in pickups.duplicate():
		n.rotation.y += delta * 3.0
		if n.position.distance_to(sp) < 3.0:
			hp = minf(hp + 25.0, 100.0)
			_sfx("pick")
			pickups.erase(n)
			n.queue_free()
		elif n.position.z > rig.position.z + 15.0:
			pickups.erase(n)
			n.queue_free()


## Hold the charge key to lock onto targets in front of the ship; release to fire homing missiles.
func _charge(delta: float) -> void:
	locks = locks.filter(func(t): return _alive(t))
	if Input.is_action_pressed("charge"):
		var before := int(charge_t / LOCK_INTERVAL)
		charge_t += delta
		if int(charge_t / LOCK_INTERVAL) > before and locks.size() < MAX_LOCKS:
			_lock_next()
	elif charge_t > 0.0:
		_launch_missiles()
		charge_t = 0.0


func _alive(t: Dictionary) -> bool:
	return is_instance_valid(t["n"]) and not t["n"].is_queued_for_deletion()


func _is_boss(t: Dictionary) -> bool:
	return not boss.is_empty() and t["n"] == boss["n"]


func _lock_next() -> void:
	var sp := ship.global_position
	var best: Dictionary = {}
	var best_d := INF
	var cands: Array = foes.duplicate()
	if not boss.is_empty():
		cands.append(boss)
	for t in cands:
		if t in locks:
			continue
		var p: Vector3 = t["n"].global_position
		var ahead := sp.z - p.z
		if ahead < 10.0 or ahead > 140.0:
			continue
		var off := Vector2(p.x - sp.x, p.y - sp.y).length()
		if off < 9.0 and ahead + off < best_d:
			best_d = ahead + off
			best = t
	if best.is_empty():
		return
	locks.append(best)
	var m := Util.box(Vector3(2.4, 2.4, 0.2), Color(1.0, 0.15, 0.15))
	m.name = "LockMark"
	best["n"].add_child(m)


func _launch_missiles() -> void:
	for t in locks:
		if not _alive(t):
			continue
		var mk = t["n"].get_node_or_null("LockMark")
		if mk:
			mk.queue_free()
		var n := Util.box(Vector3(0.35, 0.35, 1.2), Color(1.0, 0.9, 0.2))
		add_child(n)
		n.global_position = ship.global_position
		missiles.append({"n": n, "target": t})
	if not locks.is_empty():
		_sfx("launch")
	locks.clear()


func _move_missiles(delta: float) -> void:
	for m in missiles.duplicate():
		var n: Node3D = m["n"]
		var t: Dictionary = m["target"]
		var alive := _alive(t)
		var dir := Vector3(0, 0, -1)
		if alive:
			dir = (t["n"].global_position - n.global_position).normalized()
		n.position += dir * MISSILE_SPEED * delta
		var done := false
		if alive and n.position.distance_to(t["n"].global_position) < (6.0 if _is_boss(t) else 2.6):
			_damage_target(t, 8.0)
			done = true
		elif n.position.z < rig.position.z - 260.0:
			done = true
		if done:
			missiles.erase(m)
			n.queue_free()


func _damage_target(t: Dictionary, dmg: float) -> void:
	if _is_boss(t):
		boss["hp"] -= dmg
		score += 10
		if boss["hp"] <= 0.0:
			score += 2000
			Util.burst(self, boss["n"].global_position, Color(1.0, 0.7, 0.2), 120, 3.0)
			_sfx("boom")
			boss["n"].queue_free()
			boss = {}
	else:
		t["hp"] -= dmg
		if t["hp"] > 0.0:
			Util.burst(self, t["n"].global_position, Color(1.0, 1.0, 0.6), 6, 0.5)
			return
		score += t["pts"]
		if randf() < 0.15:
			_drop_pickup(t["n"].global_position)
		_kill_foe(t)


func _spawn_boss() -> void:
	boss_spawned = true
	var n := Node3D.new()
	n.add_child(Util.box(Vector3(8, 3, 8), cfg["boss_color"]))
	n.add_child(Util.box(Vector3(18, 0.5, 3), Color(0.3, 0.05, 0.4), Vector3(0, 0, 1)))
	n.add_child(Util.box(Vector3(2.5, 2.5, 2.5), Color(1.0, 0.55, 0.1), Vector3(0, 0, 4.2)))
	add_child(n)
	n.global_position = Vector3(0, 0, rig.position.z - 200.0)
	boss = {"n": n, "hp": cfg["boss_hp"], "t": 0.0, "fire": 2.0, "entry": 0.0}


func _move_boss(delta: float) -> void:
	if boss.is_empty():
		return
	var n: Node3D = boss["n"]
	boss["t"] += delta
	boss["entry"] = minf(boss["entry"] + delta / 3.0, 1.0)
	var enraged: bool = boss["hp"] < cfg["boss_hp"] * 0.5
	var sway := 1.6 if enraged else 0.8
	n.position = Vector3(sin(boss["t"] * sway) * 8.0, sin(boss["t"] * sway * 1.3) * 3.0,
			rig.position.z - lerpf(200.0, 70.0, boss["entry"]))
	boss["fire"] -= delta
	if boss["fire"] <= 0.0 and boss["entry"] >= 1.0:
		boss["fire"] = 0.8 if enraged else 1.4
		var sp := ship.global_position
		var spread := 2 if enraged else 1
		for i in range(-spread, spread + 1):
			_enemy_shot(n.position, sp + Vector3(i * 4.0, 0, 0))


func _fire() -> void:
	for side in [-1.0, 1.0]:
		var l := Util.box(Vector3(0.12, 0.12, 2.0), Color(0.3, 1.0, 0.4))
		add_child(l)
		l.global_position = ship.global_position + Vector3(side * 1.6, 0, -1.0)
		lasers.append({"n": l})
	_sfx("laser")


## Weighted pick from the level's enemy mix.
func _pick_kind() -> String:
	var mix: Dictionary = cfg["mix"]
	var total := 0.0
	for k in mix:
		total += mix[k]
	var r := randf() * total
	for k in mix:
		r -= mix[k]
		if r <= 0.0:
			return k
	return "drone"


func _spawn_foe() -> void:
	var kind := _pick_kind()
	var n := Node3D.new()
	var hp := 1.0
	var pts := 100
	var fire := randf_range(1.0, 3.0)
	match kind:
		"tank":
			n.add_child(Util.box(Vector3(3.2, 1.0, 3.2), Color(0.5, 0.5, 0.58)))
			n.add_child(Util.box(Vector3(5.2, 0.15, 1.0), Color(0.3, 0.3, 0.38)))
			hp = 3.0
			pts = 300
		"diver":
			n.add_child(Util.box(Vector3(1.0, 0.8, 2.6), Color(1.0, 0.85, 0.2)))
			n.add_child(Util.box(Vector3(2.6, 0.1, 0.7), Color(0.8, 0.6, 0.1), Vector3(0, 0, 0.5)))
			pts = 150
			fire = INF  # divers ram instead of shooting
		_:
			n.add_child(Util.box(Vector3(2.0, 0.5, 2.0), Color(0.85, 0.2, 0.2)))
			n.add_child(Util.box(Vector3(3.6, 0.1, 0.8), Color(0.5, 0.1, 0.1)))
	add_child(n)
	var x0 := randf_range(-10.0, 10.0)
	n.global_position = Vector3(x0, randf_range(-5.0, 5.0), rig.position.z - 140.0)
	foes.append({"n": n, "t": randf() * TAU, "fire": fire, "x0": x0,
			"kind": kind, "hp": hp, "pts": pts})


func _spawn_scenery() -> void:
	while scenery_z > rig.position.z - 200.0:
		for side in [-1.0, 1.0]:
			var h := randf_range(6.0, 22.0)
			var p := Util.box(Vector3(4, h, 4), cfg["pillar"],
					Vector3(side * randf_range(20.0, 32.0), -9.0 + h * 0.5, scenery_z))
			add_child(p)
			scenery.append(p)
		scenery_z -= 25.0
	for p in scenery.duplicate():
		if p.position.z > rig.position.z + 20.0:
			scenery.erase(p)
			p.queue_free()


func _move_lasers(delta: float) -> void:
	for l in lasers.duplicate():
		var n: Node3D = l["n"]
		n.position.z -= LASER_SPEED * delta
		var hit := false
		for f in foes.duplicate():
			if n.position.distance_to(f["n"].position) < 2.2:
				_damage_target(f, 1.0)
				hit = true
				break
		if not hit and not boss.is_empty() and n.position.distance_to(boss["n"].position) < 6.0:
			_damage_target(boss, 1.0)
			hit = true
		if hit or n.position.z < rig.position.z - 250.0:
			lasers.erase(l)
			n.queue_free()


func _kill_foe(f: Dictionary, boom := true) -> void:
	if boom:
		Util.burst(self, f["n"].global_position, Color(1.0, 0.55, 0.1))
		_sfx("boom")
	foes.erase(f)
	f["n"].queue_free()


func _move_foes(delta: float) -> void:
	var sp := ship.global_position
	for f in foes.duplicate():
		var n: Node3D = f["n"]
		f["t"] += delta
		if f.get("diving", false):
			n.position += f["dir"] * 45.0 * delta
		else:
			n.position.z += cfg["foe_speed"] * delta
			n.position.x = f["x0"] + sin(f["t"] * 1.5) * 3.0
			n.rotation.z = cos(f["t"] * 1.5) * 0.4
			if f["kind"] == "diver" and n.position.z > sp.z - 55.0:
				f["diving"] = true
				f["dir"] = (sp - n.position).normalized()
				n.look_at(sp)
		f["fire"] -= delta
		if f["fire"] <= 0.0 and n.position.z < sp.z - 15.0:
			f["fire"] = randf_range(1.5, 3.0) * (0.6 if f["kind"] == "tank" else 1.0)
			_enemy_shot(n.position, sp)
		if not ship.rolling and n.position.distance_to(sp) < 2.6:
			_hurt(20.0)
			_kill_foe(f)
		elif n.position.z > rig.position.z + 15.0:
			_kill_foe(f, false)


func _enemy_shot(from: Vector3, to: Vector3) -> void:
	var s := Util.box(Vector3(0.4, 0.4, 0.4), Color(1.0, 0.5, 0.1))
	add_child(s)
	s.global_position = from
	shots.append({"n": s, "v": (to - from).normalized() * cfg["shot_speed"]})


func _move_shots(delta: float) -> void:
	var sp := ship.global_position
	for s in shots.duplicate():
		var n: Node3D = s["n"]
		n.position += s["v"] * delta
		var gone := false
		if not ship.rolling and n.position.distance_to(sp) < 1.6:
			_hurt(8.0)
			gone = true
		elif n.position.z > rig.position.z + 15.0:
			gone = true
		if gone:
			shots.erase(s)
			n.queue_free()


func _update_hud() -> void:
	var pct := clampi(int(-rig.position.z / cfg["boss_z"] * 100.0), 0, 100)
	var msg := "%s   HP %d   SCORE %d   HI %d   PROGRESS %d%%" % [
			cfg["name"], maxf(hp, 0.0), score, maxi(high_score, score), pct]
	if not boss.is_empty():
		msg += "   BOSS %d/%d" % [maxf(boss["hp"], 0.0), cfg["boss_hp"]]
	if state == "title":
		msg = "ARWING-LIKE  (working title)\n\nHI SCORE %d\n\nWASD move    SPACE fire\nhold SHIFT / C: lock on, release to launch\nQ / E: barrel roll (dodges everything)\nP / ESC: pause\n\nPress SPACE to start" % maxi(high_score, 0)
	elif state == "paused":
		msg += "\nPAUSED  -  P to resume"
	elif state == "dead":
		msg += "\nGAME OVER  -  R to restart"
	elif state == "won":
		var last := level_idx + 1 >= LEVELS.size()
		msg += "\nLEVEL COMPLETE  -  R for %s" % ("a new run" if last else "the next level")
	else:
		msg += "\nWASD move   SPACE fire   hold SHIFT lock-on, release to launch   Q/E barrel roll (dodges)"
	hud.text = msg

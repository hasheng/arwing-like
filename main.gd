extends Node3D
## Level controller. Three modes, each with its own rules (see LEVELS):
##   rail      - fixed forward flight through a canyon of obstacles and formations
##   asteroid  - destructible, splitting asteroids and flight rings for a combo
##   allrange  - free-turning dogfight arena with chasing enemies and a U-turn
## Models/animation: ship.gd, foes.gd, pickups.gd. Hazards: obstacles.gd. Screen UI: hud.gd.

const Util = preload("res://util.gd")
const Ship = preload("res://ship.gd")
const Foes = preload("res://foes.gd")
const Obstacles = preload("res://obstacles.gd")
const Pickups = preload("res://pickups.gd")
const Hud = preload("res://hud.gd")
const Bosses = preload("res://bosses.gd")
const Music = preload("res://music.gd")

const FORWARD_SPEED := 30.0
const BOOST_MULT := 2.2
const BRAKE_MULT := 0.4
const GAUGE_DRAIN := 0.25      # per second: a full gauge lasts 4 s
const GAUGE_REGEN := 0.17
const LOOP_COST := 0.25
const UTURN_COST := 0.5
const LASER_SPEED := 120.0
const FIRE_COOLDOWN := 0.15
const MISSILE_SPEED := 90.0
const MAX_LOCKS := 4
const LOCK_INTERVAL := 0.25
const IFRAMES := 1.2
const SHIELD_MAX := 40.0
const BOMB_RADIUS := 80.0
const TURN_RATE := 1.7         # all-range yaw, rad/s
const ARENA := Vector2(30.0, 14.0)  # half-extents of the flyable area, matches Ship.LIMIT
const SAVE_PATH := "user://save.json"

const LEVELS := [
	{
		"name": "CORNERIA-ish", "mode": "rail",
		"sky": Color(0.05, 0.07, 0.18), "horizon": Color(0.38, 0.3, 0.5), "ground": Color(0.12, 0.3, 0.2),
		"pillar": Color(0.35, 0.3, 0.45), "boss_color": Color(0.45, 0.1, 0.55),
		"boss_z": 1200.0, "boss_hp": 60.0, "spawn": Vector2(2.5, 4.0),
		"foe_speed": 8.0, "shot_speed": 55.0, "shot_dmg": 8.0, "mix": {"drone": 1.0},
		"waves": ["single", "single", "vee", "line"],
		"obstacles": {"gap": 100.0, "kinds": ["column"]},
		"phases": [
			{"from": 0.0, "name": "OPEN SKIES"},
			{"from": 350.0, "name": "ENEMY SURGE", "spawn": 0.5, "obs": 2.0},
			{"from": 700.0, "name": "THE GAUNTLET", "spawn": 1.6, "obs": 0.45},
		],
	},
	{
		"name": "ASTEROID BELT", "mode": "asteroid",
		"sky": Color(0.1, 0.04, 0.07), "horizon": Color(0.55, 0.22, 0.14), "ground": Color(0.3, 0.14, 0.08),
		"pillar": Color(0.5, 0.38, 0.28), "boss_color": Color(0.1, 0.45, 0.5),
		"boss_z": 1600.0, "boss_hp": 100.0, "spawn": Vector2(3.5, 5.5),
		"foe_speed": 12.0, "shot_speed": 70.0, "shot_dmg": 10.0, "mix": {"drone": 0.6, "diver": 0.4},
		"waves": ["single", "vee", "line", "ring", "dive_ring"],
		"obstacles": {"gap": 999.0, "kinds": []},
		"rocks": {"gap": 26.0}, "rings_gap": 85.0,
		"phases": [
			{"from": 0.0, "name": "DRIFT FIELD"},
			{"from": 500.0, "name": "METEOR STORM", "rocks": 0.5, "spawn": 1.4},
			{"from": 1000.0, "name": "CLEAR LANE", "rocks": 2.2, "spawn": 0.5},
		],
	},
	{
		"name": "SPACE STATION", "mode": "allrange",
		"sky": Color(0.02, 0.02, 0.06), "horizon": Color(0.12, 0.14, 0.3), "ground": Color(0.15, 0.16, 0.22),
		"pillar": Color(0.3, 0.32, 0.4), "boss_color": Color(0.7, 0.15, 0.15),
		"boss_hp": 120.0, "quota": 14, "max_foes": 6, "arena": 210.0,
		"foe_speed": 24.0, "shot_speed": 80.0, "shot_dmg": 12.0,
		"mix": {"drone": 0.45, "diver": 0.2, "ace": 0.35},
	},
	{
		# Surface run, then a narrow trench with catwalks and gun emplacements, fighters on your tail,
		# and one small vent at the end. Rail rules; "trench" adds walls, scraping and the tail chasers.
		"name": "TRENCH RUN", "mode": "rail", "trench": true, "song": "trench", "boss": "port",
		"sky": Color(0.02, 0.03, 0.08), "horizon": Color(0.22, 0.25, 0.36), "ground": Color(0.2, 0.21, 0.26),
		"pillar": Color(0.34, 0.36, 0.42), "boss_color": Color(0.36, 0.38, 0.46),
		"boss_z": 2300.0, "boss_hp": 1.0e9, "spawn": Vector2(2.5, 4.0),
		"foe_speed": 10.0, "shot_speed": 60.0, "shot_dmg": 8.0, "mix": {"drone": 0.8, "diver": 0.2},
		"waves": ["single", "vee", "line", "tanks"],
		"obstacles": {"gap": 90.0, "kinds": ["column"]},
		"trench_from": 700.0, "trench_half": 17.0,
		"phases": [
			{"from": 0.0, "name": "SURFACE APPROACH"},
			{"from": 650.0, "name": "ENTER THE TRENCH", "spawn": 0.9, "obs": 0.8, "kinds": ["bridge", "wall"], "tail": 14.0},
			{"from": 1500.0, "name": "STAY ON TARGET", "spawn": 0.7, "obs": 0.6, "kinds": ["bridge", "wall", "bridge"], "tail": 9.0},
			{"from": 2050.0, "name": "FINAL APPROACH", "spawn": 1.6, "obs": 3.0, "kinds": ["bridge"]},
		],
	},
]

## Survive across scene reloads: which level we are on and the score at its start.
static var level_idx := 0
static var carry_score := 0
static var started := false   # false until the title screen has been dismissed once
static var high_score := -1   # -1 = not loaded from disk yet

var cfg: Dictionary
var mode := "rail"
var rig: Node3D
var ship: Node3D
var cam: Camera3D
var ground: MeshInstance3D
var planet: MeshInstance3D
var streaks: CPUParticles3D
var hud: CanvasLayer

var lasers: Array = []     # {n, v}
var foes: Array = []       # see _spawn_foe
var shots: Array = []      # {n, v, reflected}
var scenery: Array = []
var obstacles: Array = []  # {n, z, boxes}
var rocks: Array = []      # {n, size, hp, vel, spin, r}
var rings: Array = []      # {n, z, done, prev}
var missiles: Array = []   # {n, target}
var locks: Array = []      # target dicts (foes or the boss)
var wrecks: Array = []     # destroyed foes tumbling out of the sky
var pickups: Array = []    # {n, kind, t}
var waves: Dictionary = {} # wave id -> foes left; negative once the player let one escape
var boss: Dictionary = {}  # {n, hp, t, fire, entry, flash, a, summon}
var boss_spawned := false

var hp := 100.0
var shield := 0.0
var weapon := 1            # 1 twin, 2 triple, 3 five-way
var bombs := 1
var overdrive_t := 0.0     # infinite boost gauge while > 0
var combo := 0
var kills := 0
var score := 0
var state := "play"        # title | play | paused | dead | won
var gauge := 1.0           # boost/brake/loop meter, 0..1
var gauge_locked := false  # emptied: unusable until it refills a little
var speed_mult := 1.0
var iframes := 0.0
var shake := 0.0
var charge_t := 0.0
var fire_t := 0.0
var spawn_t := 1.5
var scenery_z := 0.0
var next_obs_z := -140.0
var next_rock_z := -90.0
var next_ring_z := -160.0
var wave_id := 0
var phase_idx := -1
var uturn_t := 0.0
var sfx: Dictionary = {}
var sfx_players: Array = []
var music: Node
var music_state := ""           # last state the music was told about
var shot_mode := false          # --boss: scripted screenshots (ignores pause, close-up camera)
var tail_t := 8.0               # trench: seconds until the next fighter drops in behind you
var mirror_cam: Camera3D        # trench: rear view, because the chasers are behind the camera
var mirror_box: Control
var station: Node3D             # trench: the big sphere you are flying toward
var aim_point := Vector3.ZERO   # world point under the mouse, on a plane ahead of the ship
var mouse_seen := false         # until the mouse moves, aim straight ahead


func _ready() -> void:
	randomize()
	Util.setup_input()
	for a in OS.get_cmdline_user_args():  # --level=N jumps to a level (scripted screenshots)
		if a.begins_with("--level="):
			level_idx = clampi(int(a.get_slice("=", 1)), 0, LEVELS.size() - 1)
	cfg = LEVELS[level_idx]
	mode = cfg["mode"]
	score = carry_score
	if "--autostart" in OS.get_cmdline_user_args():  # for scripted screenshots
		started = true
	state = "play" if started else "title"
	if high_score < 0:
		high_score = _load_high()

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var smat := ProceduralSkyMaterial.new()
	smat.sky_top_color = cfg["sky"]
	smat.sky_horizon_color = cfg["horizon"]
	smat.ground_horizon_color = cfg["horizon"]
	smat.ground_bottom_color = cfg["sky"]
	sky.sky_material = smat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.fog_enabled = true
	env.fog_light_color = (cfg["horizon"] as Color).darkened(0.4)
	env.fog_density = 0.005
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	rig = Node3D.new()
	add_child(rig)
	if mode == "allrange":
		rig.position = Vector3(0, 0, 80)
	ship = Ship.new()
	rig.add_child(ship)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 500.0
	rig.add_child(cam)
	cam.position = Vector3(0, 3, 10)

	# Speed lines: streaks flying past the rig, faster when boosting.
	streaks = CPUParticles3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.06, 4.0)
	var smat2 := StandardMaterial3D.new()
	smat2.albedo_color = Color(0.7, 0.8, 1.0)
	smat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat2
	streaks.mesh = sm
	streaks.amount = 70
	streaks.lifetime = 0.9
	streaks.local_coords = true
	streaks.position = Vector3(0, 0, -70)
	streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	streaks.emission_box_extents = Vector3(38, 22, 1)
	streaks.direction = Vector3(0, 0, 1)
	streaks.spread = 0.0
	streaks.gravity = Vector3.ZERO
	streaks.initial_velocity_min = 90.0
	streaks.initial_velocity_max = 90.0
	rig.add_child(streaks)

	var gsize := Vector3(700, 1, 700) if mode == "allrange" else Vector3(400, 1, 600)
	ground = Util.box(gsize, cfg["ground"], Vector3(0, -17, 0))
	ground.visible = mode != "asteroid"
	add_child(ground)
	if mode == "asteroid":
		_build_planet()
	if mode == "allrange":
		_build_arena()

	sfx = {
		"laser": Util.tone(900.0, 0.08, 0.0, -500.0),
		"boom": Util.tone(120.0, 0.4, 0.8, -80.0),
		"hit": Util.tone(200.0, 0.2, 0.5, -100.0),
		"pick": Util.tone(500.0, 0.15, 0.0, 600.0),
		"launch": Util.tone(300.0, 0.25, 0.2, 500.0),
		"deflect": Util.tone(1300.0, 0.12, 0.1, 400.0),
		"boost": Util.tone(160.0, 0.35, 0.3, 500.0),
		"bomb": Util.tone(70.0, 0.8, 0.9, -40.0),
		"power": Util.tone(400.0, 0.3, 0.0, 900.0),
	}
	for i in 10:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -9.0  # ten overlapping voices at full level clip the mix
		add_child(ap)
		sfx_players.append(ap)

	hud = Hud.new()
	add_child(hud)
	music = Music.new()
	add_child(music)
	music.play_song(cfg.get("song", mode))
	if cfg.get("trench", false):
		_build_station()
		_build_mirror()
	for a in OS.get_cmdline_user_args():  # --at=N starts N units down the level (scripted screenshots)
		if a.begins_with("--at="):
			rig.position.z = -float(a.get_slice("=", 1))
			scenery_z = rig.position.z
			next_obs_z = rig.position.z - 100.0
			next_rock_z = rig.position.z - 100.0
			next_ring_z = rig.position.z - 160.0
		if a == "--tail":
			_spawn_tail()
	if "--boss" in OS.get_cmdline_user_args():  # jump to the boss fight (scripted screenshots)
		shot_mode = true
		if mode == "allrange":
			kills = int(cfg["quota"])
		else:
			rig.position.z = -float(cfg["boss_z"])
	_update_camera(1.0)


func _build_planet() -> void:
	var s := SphereMesh.new()
	s.radius = 140.0
	s.height = 280.0
	s.radial_segments = 16
	s.rings = 8
	planet = Util.mesh(s, (cfg["horizon"] as Color).darkened(0.1))
	add_child(planet)


## The sphere on the horizon: a sky-filling moon-sized station with a band round the middle and a lens.
func _build_station() -> void:
	station = Node3D.new()
	var s := SphereMesh.new()
	s.radius = 300.0
	s.height = 600.0
	s.radial_segments = 24
	s.rings = 12
	var c: Color = cfg["pillar"]
	station.add_child(Util.mesh(s, c.darkened(0.15)))
	var ring := CylinderMesh.new()
	ring.top_radius = 304.0
	ring.bottom_radius = 304.0
	ring.height = 14.0
	ring.radial_segments = 24
	station.add_child(Util.mesh(ring, c.darkened(0.45)))
	var lens := Util.glow(Util.ball(46.0, Color(0.5, 1.0, 0.6)), Color(0.4, 1.0, 0.5), 1.6)
	lens.position = Vector3(-90, 130, 270)
	station.add_child(lens)
	add_child(station)


## Rear-view window: enemy fighters sit behind the chase camera, so show them in a corner.
func _build_mirror() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var frame := ColorRect.new()
	frame.color = Color(0, 0, 0, 0.7)
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -386.0
	frame.offset_right = -14.0
	frame.offset_top = 36.0  # below the boss bar
	frame.offset_bottom = 176.0
	layer.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(6, 6)
	svc.size = Vector2(360, 128)
	frame.add_child(svc)
	var sv := SubViewport.new()
	sv.size = Vector2i(360, 128)
	svc.add_child(sv)
	mirror_cam = Camera3D.new()
	mirror_cam.fov = 80.0
	mirror_cam.far = 300.0
	sv.add_child(mirror_cam)
	var lab := Label.new()
	lab.text = "REAR"
	lab.add_theme_font_size_override("font_size", 14)
	lab.position = Vector2(10, 4)
	frame.add_child(lab)
	mirror_box = frame


func _update_mirror() -> void:
	mirror_box.visible = state != "title"
	var sp := ship.global_position
	var back := -_rig_forward()
	mirror_cam.global_position = sp + Vector3(0, 2.2, 0) + back * 1.0
	mirror_cam.look_at(sp + Vector3(0, 1.6, 0) + back * 60.0)


## All-range arena: glowing boundary posts and a scatter of columns/arches to weave through.
func _build_arena() -> void:
	var arena: float = cfg["arena"]
	for i in 36:
		var a := i * TAU / 36.0
		var post := Util.glow(Util.box(Vector3(3, 50, 3), Color(1.0, 0.4, 0.2), Vector3(cos(a) * arena, 8, sin(a) * arena)),
				Color(1.0, 0.35, 0.1), 1.5)
		add_child(post)
	for i in 24:
		var a := randf() * TAU
		var r := randf_range(35.0, arena - 25.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var kind: String = ["column", "column", "arch"].pick_random()
		var o := Obstacles.spawn(self, p.z, kind, (cfg["pillar"] as Color).lightened(0.1), p.x)
		obstacles.append(o)


func _rig_forward() -> Vector3:
	return -rig.global_transform.basis.z


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_seen = true


func _update_aim() -> void:
	var sp := ship.global_position
	var f := _rig_forward()
	var plane_pt := sp + f * 40.0
	if not mouse_seen:
		aim_point = plane_pt
		return
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var denom := d.dot(f)
	if denom < 0.05:
		return
	var p := o + d * ((plane_pt - o).dot(f) / denom)
	var loc := rig.to_local(p)
	loc.x = clampf(loc.x, -ARENA.x - 12.0, ARENA.x + 12.0)
	loc.y = clampf(loc.y, -ARENA.y - 8.0, ARENA.y + 10.0)
	aim_point = rig.to_global(loc)


func _physics_process(delta: float) -> void:
	var want_mode := Input.MOUSE_MODE_CONFINED_HIDDEN if state == "play" else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want_mode:
		Input.mouse_mode = want_mode
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

	if shot_mode and state == "paused":
		state = "play"
	if state == "play":
		_play(delta)
	elif state == "dead" or state == "won":
		_move_wrecks(delta)  # let the last explosions finish
	_update_music()
	_update_hud()


## The score follows the action: stems fade in as the level builds, the boss gets its own track,
## boost and brake bend the pitch, and the end of a run gets a short sting.
func _update_music() -> void:
	if state != music_state:
		music_state = state
		match state:
			"dead":
				music.play_song("defeat", false)
			"won":
				music.play_song("victory", false)
			"play", "title":
				pass
	if state == "dead" or state == "won":
		music.set_intensity(1.0)
		return
	var base: String = cfg.get("song", mode)
	var song := base
	var level := 0.3
	if boss_spawned:
		song = "boss_" + base
		level = 1.0
	elif mode == "allrange":
		level = 0.25 + 0.75 * clampf(float(kills) / float(cfg["quota"]), 0.0, 1.0)
	else:
		level = [0.25, 0.5, 1.0][clampi(phase_idx, 0, 2)]
	if state == "title":
		level = 0.0
	music.play_song(song)
	music.set_intensity(level)
	music.duck = 10.0 if state == "paused" else 0.0
	music.speed = 1.0 + (speed_mult - 1.0) * 0.07 if state == "play" else 1.0


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
	_flight(delta)

	var dir := Input.get_vector("left", "right", "down", "up")
	ship.steer(dir, delta, mode != "allrange")
	if Input.is_action_just_pressed("roll_l"):
		ship.barrel_roll(-1.0)
	if Input.is_action_just_pressed("roll_r"):
		ship.barrel_roll(1.0)
	if Input.is_action_just_pressed("loop") and not ship.looping:
		if mode == "allrange":
			if gauge >= UTURN_COST:  # Immelmann: loop up and come out facing the other way
				gauge -= UTURN_COST
				uturn_t = 0.8
				ship.loop()
				_sfx("boost")
		elif gauge >= LOOP_COST:
			gauge -= LOOP_COST
			ship.loop()
			_sfx("boost")
	if Input.is_action_just_pressed("bomb"):
		_bomb()

	iframes = maxf(iframes - delta, 0.0)
	ship.visible = iframes <= 0.0 or int(iframes * 14.0) % 2 == 0
	ship.set_shield(shield / SHIELD_MAX, delta)
	overdrive_t = maxf(overdrive_t - delta, 0.0)

	_update_aim()
	ship.set_aim_world(aim_point)
	fire_t -= delta
	if Input.is_action_pressed("fire") and fire_t <= 0.0:
		fire_t = FIRE_COOLDOWN
		_fire()
	_charge(delta)
	ship.set_aiming(charge_t > 0.0, charge_t, delta)

	_spawn_things(delta)

	_move_lasers(delta)
	_move_foes(delta)
	_move_boss(delta)
	_move_missiles(delta)
	_move_shots(delta)
	_move_rocks(delta)
	_move_rings(delta)
	_move_wrecks(delta)
	_move_pickups(delta)
	_check_obstacles()
	_check_trench()
	_update_camera(delta)
	if mirror_cam:
		_update_mirror()

	if hp <= 0.0:
		_end_run("dead")
	elif boss_spawned and boss.is_empty():
		_end_run("won")


## What shows up next depends on the level mode.
func _spawn_things(delta: float) -> void:
	var ph := _phase()
	if mode == "allrange":
		if not boss_spawned and kills >= int(cfg["quota"]):
			_spawn_boss()
		if not boss_spawned:
			spawn_t -= delta
			if spawn_t <= 0.0 and foes.size() < int(cfg["max_foes"]):
				spawn_t = 1.0
				_spawn_chaser()
		return
	if not boss_spawned and -rig.position.z >= cfg["boss_z"]:
		_spawn_boss()
	if not boss_spawned:
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = randf_range(cfg["spawn"].x, cfg["spawn"].y) * float(ph.get("spawn", 1.0))
			var pattern: String = cfg["waves"].pick_random()
			_spawn_wave(pattern)
		if mode == "rail":
			_spawn_obstacles(float(ph.get("obs", 1.0)), ph.get("kinds", []))
			if float(ph.get("tail", 0.0)) > 0.0:
				tail_t -= delta
				if tail_t <= 0.0:
					tail_t = float(ph["tail"]) * randf_range(0.8, 1.2)
					_spawn_tail()
		else:
			_spawn_rocks(float(ph.get("rocks", 1.0)))
			_spawn_rings()
	if mode == "rail":
		_spawn_scenery()
	elif mode == "asteroid":
		planet.position = rig.position + Vector3(-190, 50, -700)
	if station:
		station.position = rig.position + Vector3(-90, 40, -760)


## Scripted level segments: the pace changes as you progress and each change is announced.
func _phase() -> Dictionary:
	var phases: Array = cfg.get("phases", [])
	var dist := -rig.position.z
	var idx := -1
	for i in phases.size():
		if dist >= float(phases[i]["from"]):
			idx = i
	if idx != phase_idx:
		phase_idx = idx
		if idx > 0:
			hud.toast(phases[idx]["name"])
	return phases[idx] if idx >= 0 else {}


## Boost / brake with the shared gauge, and the forward motion that follows from it.
func _flight(delta: float) -> void:
	var want := 0.0
	if overdrive_t > 0.0:
		gauge = 1.0
		gauge_locked = false
		if Input.is_action_pressed("boost"):
			want = 1.0
		elif Input.is_action_pressed("brake"):
			want = -1.0
	else:
		if not gauge_locked and gauge > 0.0:
			if Input.is_action_pressed("boost"):
				want = 1.0
			elif Input.is_action_pressed("brake"):
				want = -1.0
		if want != 0.0:
			gauge = maxf(gauge - GAUGE_DRAIN * delta, 0.0)
			if gauge <= 0.0:
				gauge_locked = true
		else:
			gauge = minf(gauge + GAUGE_REGEN * delta, 1.0)
			if gauge >= 0.3:
				gauge_locked = false
	var target := BOOST_MULT if want > 0.0 else (BRAKE_MULT if want < 0.0 else 1.0)
	speed_mult = lerpf(speed_mult, target, clampf(delta * 4.0, 0.0, 1.0))

	if mode == "allrange":
		# A/D turn the whole rig; the arena edge steers you back in.
		rig.rotation.y += Input.get_axis("right", "left") * TURN_RATE * delta
		if uturn_t > 0.0:
			rig.rotation.y += PI / 0.8 * delta
			uturn_t -= delta
		rig.position += _rig_forward() * FORWARD_SPEED * speed_mult * delta
		var arena: float = cfg["arena"]
		var flat := Vector2(rig.position.x, rig.position.z)
		if flat.length() > arena - 30.0:
			var out := flat.normalized()
			var heading := Vector2(_rig_forward().x, _rig_forward().z)
			if heading.dot(out) > 0.0:
				var toward := -out
				rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-toward.x, -toward.y), 2.8 * delta)
			if flat.length() > arena:
				var clamped := out * arena
				rig.position.x = clamped.x
				rig.position.z = clamped.y
	else:
		rig.position.z -= FORWARD_SPEED * speed_mult * delta
		ground.position.z = rig.position.z - 100.0
	ship.set_thrust(want, delta)
	streaks.speed_scale = speed_mult


func _update_camera(delta: float) -> void:
	# Chase camera with lag: it trails the ship, rolls with its bank, and stretches on boost.
	var k := clampf(delta * 5.0, 0.0, 1.0)
	var tgt := Vector3(ship.position.x * 0.75, 3.0 + ship.position.y * 0.6, 10.0 + (speed_mult - 1.0) * 1.8)
	cam.position = cam.position.lerp(tgt, k)
	cam.fov = lerpf(cam.fov, 70.0 + (speed_mult - 1.0) * 12.0, k)
	shake = maxf(shake - delta * 1.5, 0.0)
	cam.h_offset = randf_range(-shake, shake)
	cam.v_offset = randf_range(-shake, shake)
	cam.look_at(rig.to_global(Vector3(ship.position.x * 0.35, ship.position.y * 0.35, -30)))
	cam.rotation.z = -ship.bank * 0.35
	if shot_mode and not boss.is_empty():  # --boss: close-up on the boss for scripted screenshots
		var bn: Node3D = boss["n"]
		cam.global_position = bn.global_position - (boss["dir"] as Vector3) * 30.0 + Vector3(11, 7, 0)
		cam.look_at(bn.global_position)


func _sfx(name: String) -> void:
	for p in sfx_players:
		if not p.playing:
			p.stream = sfx[name]
			p.play()
			return


func _hurt(amount: float) -> void:
	if iframes > 0.0:
		return
	iframes = IFRAMES
	shake = 0.7
	hud.damage_flash()
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		_sfx("deflect")
		if amount <= 0.0:
			shake = 0.35
			return
	hp -= amount
	if amount >= 15.0:
		weapon = maxi(weapon - 1, 1)  # a heavy hit knocks a weapon level off
	_sfx("hit")


# ---------------------------------------------------------------------------- power-ups

func _drop_pickup(pos: Vector3, kind := "") -> void:
	if kind == "":
		kind = Pickups.roll()
	var n := Pickups.build(kind)
	add_child(n)
	n.global_position = pos
	pickups.append({"n": n, "kind": kind, "t": 0.0})


func _move_pickups(delta: float) -> void:
	var sp := ship.global_position
	for p in pickups.duplicate():
		var n: Node3D = p["n"]
		p["t"] += delta
		var body: Node3D = n.get_node("Body")
		body.rotation.y += delta * 3.0
		body.position.y = sin(float(p["t"]) * 3.0) * 0.4
		var d := n.global_position.distance_to(sp)
		if d < 14.0:  # gentle magnet
			n.global_position = n.global_position.move_toward(sp, 22.0 * delta)
		if d < 3.5:
			_collect(p["kind"])
			pickups.erase(p)
			n.queue_free()
		elif _gone(n.global_position, 15.0) and mode != "allrange":
			pickups.erase(p)
			n.queue_free()


func _collect(kind: String) -> void:
	match kind:
		"repair":
			hp = minf(hp + 30.0, 100.0)
			hud.toast("REPAIR  +30 HP")
		"shield":
			shield = SHIELD_MAX
			hud.toast("SHIELD UP")
		"weapon":
			weapon = mini(weapon + 1, 3)
			hud.toast("WEAPON LEVEL %d" % weapon)
		"bomb":
			bombs = mini(bombs + 1, 3)
			hud.toast("SMART BOMB  x%d" % bombs)
		"boost":
			overdrive_t = 6.0
			hud.toast("OVERDRIVE  -  unlimited boost")
	_sfx("power")


## Smart bomb: shockwave that wipes nearby enemies, shots and rocks and hurts the boss.
func _bomb() -> void:
	if bombs <= 0:
		return
	bombs -= 1
	var sp := ship.global_position
	_sfx("bomb")
	shake = 1.2
	hud.damage_flash()
	var wave := Util.ball(1.0, Color(1.0, 0.7, 0.3, 0.35))
	var m: StandardMaterial3D = wave.material_override
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(wave)
	wave.global_position = sp
	var tw := create_tween()
	tw.tween_property(wave, "scale", Vector3.ONE * BOMB_RADIUS, 0.5).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.finished.connect(wave.queue_free)
	for f in foes.duplicate():
		if (f["n"].global_position as Vector3).distance_to(sp) < BOMB_RADIUS:
			f["hp"] = 0.0
			_damage_target(f, 1.0)
	for s in shots.duplicate():
		if (s["n"].global_position as Vector3).distance_to(sp) < BOMB_RADIUS:
			shots.erase(s)
			s["n"].queue_free()
	for rk in rocks.duplicate():
		if (rk["n"].global_position as Vector3).distance_to(sp) < BOMB_RADIUS:
			_break_rock(rk, true, false)
	if not boss.is_empty() and (boss["n"].global_position as Vector3).distance_to(sp) < BOMB_RADIUS * 1.4:
		Bosses.bomb(self, 15.0)


# ------------------------------------------------------------------------------ lock-on

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
	return not t.get("dead", false) and is_instance_valid(t["n"]) and not t["n"].is_queued_for_deletion()


func _is_boss(t: Dictionary) -> bool:
	return not boss.is_empty() and t["n"] == boss["n"]


func _lock_next() -> void:
	var sp := ship.global_position
	var best: Dictionary = {}
	var best_d := INF
	var cands: Array = foes.duplicate()
	cands.append_array(Bosses.targets(self))
	for t in cands:
		if t in locks:
			continue
		# Lock onto whatever the reticle is pointing at: distance from the aim ray.
		var aim_dir := (aim_point - sp).normalized()
		var v: Vector3 = (t["n"].global_position as Vector3) - sp
		var along := v.dot(aim_dir)
		if along < 10.0 or along > 140.0:
			continue
		var off := (v - aim_dir * along).length()
		var reach := 8.0 + along * 0.06 + (9.0 if _is_boss(t) else 0.0)  # the boss is big: forgive aim
		if off < reach and along + off < best_d:
			best_d = along + off
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
		var dir := _rig_forward()
		if alive:
			dir = (t["n"].global_position - n.global_position).normalized()
			n.look_at(n.global_position + dir)
		n.position += dir * MISSILE_SPEED * delta
		var done := false
		if alive and n.position.distance_to(t["n"].global_position) < float(t.get("r", 2.6)):
			_damage_target(t, 8.0, n.global_position)
			done = true
		elif _gone(n.global_position, 1.0e9):
			done = true
		if done:
			missiles.erase(m)
			n.queue_free()


# ----------------------------------------------------------------------------- damage

## `from` is where the hit came from, for bosses that can only be hurt from some directions.
func _damage_target(t: Dictionary, dmg: float, from := Vector3.INF) -> void:
	if t.get("part", false):
		Bosses.damage_part(self, t, dmg)
		return
	if _is_boss(t):
		var dealt := Bosses.filter(self, dmg, from)
		boss["hp"] -= dealt
		if dealt >= dmg:
			score += 10
			boss["flash"] = 0.08
			Util.flash(boss["n"], true)
		if boss["hp"] <= 0.0:
			score += 2000
			Util.burst(self, boss["n"].global_position, Color(1.0, 0.7, 0.2), 120, 3.0)
			_sfx("boom")
			shake = 1.2
			boss["n"].queue_free()
			boss = {}
	else:
		t["hp"] -= dmg
		if t["hp"] > 0.0:
			t["flash"] = 0.08
			Util.flash(t["n"], true)
			Util.burst(self, t["n"].global_position, Color(1.0, 1.0, 0.6), 6, 0.5)
			return
		score += t["pts"]
		var elite: bool = t["kind"] == "tank" or t["kind"] == "ace"
		if randf() < (0.3 if elite else 0.15):
			_drop_pickup(t["n"].global_position)
		_destroy_foe(t, true)


func _spawn_boss() -> void:
	boss_spawned = true
	boss = Bosses.spawn(self)
	hud.toast("%s APPROACHING" % boss["title"])


func _move_boss(delta: float) -> void:
	if boss.is_empty():
		return
	Bosses.update(self, delta)


func _rig_right() -> Vector3:
	return rig.global_transform.basis.x


# ----------------------------------------------------------------------------- weapons

func _fire() -> void:
	var spreads: Array = [[0.0]]
	match weapon:
		1:
			spreads = [0.0]
		2:
			spreads = [-0.06, 0.0, 0.06]
		_:
			spreads = [-0.14, -0.07, 0.0, 0.07, 0.14]
	var right := _rig_right()
	var guns: Array = [-1.0, 1.0] if weapon == 1 else [0.0]
	for side in guns:
		var origin: Vector3 = ship.global_position + right * float(side) * 1.6 - _rig_forward() * 1.0
		var base: Vector3 = (aim_point - origin).normalized()
		for sp_off in spreads:
			var l := Util.box(Vector3(0.12, 0.12, 2.0), Color(0.3, 1.0, 0.4) if weapon < 3 else Color(1.0, 0.9, 0.3))
			add_child(l)
			var v: Vector3 = (base + right * float(sp_off)).normalized() * LASER_SPEED
			l.global_position = origin
			l.look_at(origin + v)
			lasers.append({"n": l, "v": v})
			if weapon == 1:
				break  # twin guns fire straight; spread only applies to higher levels
	_sfx("laser")


func _move_lasers(delta: float) -> void:
	for l in lasers.duplicate():
		var n: Node3D = l["n"]
		n.position += (l["v"] as Vector3) * delta
		var hit := false
		for f in foes.duplicate():
			if f["kind"] == "ace" and float(f["rolling"]) > 0.0:
				continue  # aces slip lasers mid-roll
			if n.position.distance_to(f["n"].position) < 2.2:
				_damage_target(f, 1.0)
				hit = true
				break
		if not hit:
			for rk in rocks:
				if n.position.distance_to(rk["n"].position) < float(rk["r"]) + 0.5:
					_hit_rock(rk, 1)
					hit = true
					break
		if not hit:
			var bt := Bosses.hit_test(self, n.global_position)
			if not bt.is_empty():
				_damage_target(bt, 1.0, n.global_position)
				hit = true
		if hit or _gone(n.global_position, 20.0):
			lasers.erase(l)
			n.queue_free()


## Distance-based culling that works for any heading; in rail/asteroid also drops things behind us.
func _gone(p: Vector3, back := 15.0) -> bool:
	var rel := p - rig.global_position
	if rel.length() > 320.0:
		return true
	return mode != "allrange" and rel.dot(_rig_forward()) < -back


# ------------------------------------------------------------------------------- foes

## Weighted pick from the level's single-enemy mix.
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


## Spawns a formation. Clearing every member earns a bonus; letting one escape forfeits it.
func _spawn_wave(pattern: String) -> void:
	var cx := randf_range(-14.0, 14.0)
	var cy := randf_range(-4.0, 6.0)
	var z := rig.position.z - 160.0
	var members: Array = []  # {kind, off, mode, phase}
	match pattern:
		"vee":
			for i in range(-2, 3):
				members.append({"kind": "drone", "off": Vector3(i * 4.5, 0, absf(i) * 6.0)})
		"line":
			for i in range(-2, 3):
				members.append({"kind": "drone", "off": Vector3(i * 7.0, 0, 0)})
		"ring", "dive_ring":
			var kind := "drone" if pattern == "ring" else "diver"
			var count := 6 if pattern == "ring" else 5
			cx = clampf(cx, -16.0, 16.0)
			for i in count:
				members.append({"kind": kind, "off": Vector3.ZERO, "mode": "ring", "phase": i * TAU / count})
		"tanks":
			members.append({"kind": "tank", "off": Vector3(-9, -3, 0)})
			members.append({"kind": "tank", "off": Vector3(9, 3, 0)})
		_:
			members.append({"kind": _pick_kind(), "off": Vector3(cx, cy, 0) * 0.6, "phase": randf() * TAU})
	var wid := 0
	if members.size() > 1:
		wave_id += 1
		wid = wave_id
		waves[wid] = members.size()
	for m in members:
		var fmode: String = m.get("mode", "sine")
		var phase: float = m.get("phase", 0.0)
		var pos := Vector3(cx, cy, z) + (m["off"] as Vector3)
		_spawn_foe(m["kind"], pos, wid, fmode, phase)


func _spawn_chaser() -> void:
	var sp := ship.global_position
	var a := randf() * TAU
	var pos := sp + Vector3(cos(a), 0, sin(a)) * randf_range(100.0, 140.0)
	var arena: float = cfg["arena"]
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > arena - 10.0:
		flat = flat.normalized() * (arena - 10.0)
		pos.x = flat.x
		pos.z = flat.y
	pos.y = randf_range(-6.0, 8.0)
	var f := _spawn_foe(_pick_kind(), pos, 0, "chase", 0.0)
	f["vel"] = (sp - pos).normalized() * float(cfg["foe_speed"])


## A fighter that drops in behind you and shoots forward. Shake it by braking (it overshoots and is
## then in your sights), boosting away, rolling to reflect its shots, or looping under them.
func _spawn_tail() -> void:
	var sp := ship.global_position
	var f := _spawn_foe("drone", Vector3(sp.x, sp.y, sp.z + 120.0), 0, "tail", 0.0)
	f["side"] = [-1.0, 1.0].pick_random()
	hud.toast("FIGHTER ON YOUR TAIL  -  check the rear view, brake to shake it")


func _spawn_foe(kind: String, pos: Vector3, wid := 0, fmode := "sine", phase := 0.0) -> Dictionary:
	var n := Foes.build(kind)
	add_child(n)
	if mode != "allrange":
		pos.x = clampf(pos.x, -ARENA.x + 2.0, ARENA.x - 2.0)
		pos.y = clampf(pos.y, -ARENA.y + 2.0, ARENA.y - 2.0)
	n.global_position = pos
	var hp_v := 1.0
	var pts := 100
	match kind:
		"tank":
			hp_v = 3.0
			pts = 300
		"diver":
			pts = 150
		"ace":
			hp_v = 4.0
			pts = 400
	var fire := INF if kind == "diver" else randf_range(1.0, 3.0)  # divers ram instead of shooting
	var f := {"n": n, "t": phase, "age": 0.0, "fire": fire, "base": pos, "kind": kind,
			"hp": hp_v, "pts": pts, "wave": wid, "mode": fmode, "phase": phase,
			"vx": 0.0, "bank": 0.0, "flash": 0.0, "dead": false, "recoil": 0.0,
			"roll_t": randf_range(1.0, 4.0), "rolling": 0.0,
			"vel": Vector3.ZERO, "state": "attack", "state_t": randf_range(3.0, 6.0), "evade": Vector3.ZERO}
	foes.append(f)
	return f


func _move_foes(delta: float) -> void:
	var sp := ship.global_position
	for f in foes.duplicate():
		var n: Node3D = f["n"]
		f["t"] += delta
		f["age"] += delta
		if mode == "allrange":
			_chase(f, delta, sp)
		else:
			_rail_motion(f, delta, sp)
		Foes.animate(f, delta, sp)
		_foe_fire(f, delta, sp)
		if f.get("diving", false):
			f["trail"] = float(f.get("trail", 0.0)) - delta
			if float(f["trail"]) <= 0.0:
				f["trail"] = 0.07
				Util.burst(self, n.global_position, Color(1.0, 0.5, 0.15), 3, 0.2)
		if n.global_position.distance_to(sp) < 2.8:
			# Ramming hurts even mid-roll: only shots are reflected.
			_hurt(20.0)
			Util.burst(self, n.global_position, Color(1.0, 0.55, 0.1))
			_sfx("boom")
			_destroy_foe(f, false)
		elif mode != "allrange" and _gone(n.global_position, 400.0 if f["mode"] == "tail" else 15.0):
			_destroy_foe(f, false)


func _rail_motion(f: Dictionary, delta: float, sp: Vector3) -> void:
	var n: Node3D = f["n"]
	var prev_x := n.position.x
	var base: Vector3 = f["base"]
	if f["mode"] == "tail":
		# Holds station ~32 behind at your own speed. Brake and it flies past into your sights; boost and it falls away.
		var off := n.position.z - sp.z
		n.position.z -= (FORWARD_SPEED + clampf((off - 32.0) * 0.8, -6.0, 25.0)) * delta
		var k := clampf(delta * 1.5, 0.0, 1.0)
		n.position.x = lerpf(n.position.x, sp.x + float(f["side"]) * 6.0, k)
		n.position.y = lerpf(n.position.y, sp.y + 1.0, k)
		f["vx"] = (n.position.x - prev_x) / maxf(delta, 0.0001)
		f["bank"] = clampf(-float(f["vx"]) * 0.08, -0.7, 0.7)
		return
	if f.get("diving", false):
		n.position += (f["dir"] as Vector3) * 45.0 * delta
	else:
		n.position.z += cfg["foe_speed"] * delta
		var t: float = f["t"]
		if f["mode"] == "ring":
			n.position.x = base.x + cos(t * 1.2 + float(f["phase"])) * 9.0
			n.position.y = base.y + sin(t * 1.2 + float(f["phase"])) * 6.0
		else:
			n.position.x = base.x + sin(t * 1.5) * 4.0
			n.position.y = base.y + sin(t * 1.1) * 1.5
		if f["kind"] == "diver" and n.position.z > sp.z - 55.0:
			f["diving"] = true
			# Lead the target: the rig keeps flying forward while the diver closes in.
			var vship := Vector3(0, 0, -FORWARD_SPEED * speed_mult)
			var lead := sp + vship * (n.position.distance_to(sp) / (45.0 + FORWARD_SPEED * speed_mult))
			f["dir"] = (lead - n.position).normalized()
			n.look_at(lead)
	f["vx"] = (n.position.x - prev_x) / maxf(delta, 0.0001)
	f["bank"] = clampf(-float(f["vx"]) * 0.08, -0.7, 0.7)


## All-range AI: attack runs toward the player, then break away and come around again.
## Divers never break off; aces turn tighter and roll to dodge lasers.
func _chase(f: Dictionary, delta: float, sp: Vector3) -> void:
	var n: Node3D = f["n"]
	var kind: String = f["kind"]
	var to := sp - n.global_position
	var dist := to.length()
	f["state_t"] -= delta
	var desired: Vector3
	if f["state"] == "attack":
		desired = to.normalized()
		if kind != "diver" and (dist < 24.0 or float(f["state_t"]) <= 0.0):
			f["state"] = "evade"
			f["state_t"] = randf_range(1.5, 2.8)
			var away := -to.normalized()
			f["evade"] = (away + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * 0.7).normalized()
	else:
		desired = f["evade"]
		if float(f["state_t"]) <= 0.0 or dist > 110.0:
			f["state"] = "attack"
			f["state_t"] = randf_range(3.0, 6.0)
	var turn := 1.8
	var spd := float(cfg["foe_speed"])
	match kind:
		"diver":
			turn = 3.5
			spd *= 1.5
		"ace":
			turn = 2.8
			spd *= 1.2
	var cur: Vector3 = f["vel"]
	var cdir := cur.normalized() if cur.length() > 0.1 else desired
	if cdir.dot(desired) < -0.98:  # head-on reversal: pick a side instead of an undefined slerp
		desired = (desired + cdir.cross(Vector3.UP).normalized() * 0.5).normalized()
	var ndir := cdir.slerp(desired, clampf(turn * delta, 0.0, 1.0)).normalized()
	f["vel"] = ndir * spd
	n.position += (f["vel"] as Vector3) * delta
	n.look_at(n.global_position + ndir)
	var turn_rate := cdir.cross(ndir).y / maxf(delta, 0.0001)
	f["bank"] = clampf(-turn_rate * 0.35, -0.9, 0.9)
	n.position.y = clampf(n.position.y, -12.0, 18.0)
	var flat := Vector2(n.position.x, n.position.z)
	var arena: float = cfg["arena"]
	if flat.length() > arena:
		flat = flat.normalized() * arena
		n.position.x = flat.x
		n.position.z = flat.y


func _foe_fire(f: Dictionary, delta: float, sp: Vector3) -> void:
	var n: Node3D = f["n"]
	f["fire"] -= delta
	if f["fire"] > 0.0:
		return
	var from: Vector3 = n.global_position
	if mode == "allrange":
		var to := sp - from
		var dist := to.length()
		var facing: Vector3 = (f["vel"] as Vector3).normalized()
		if dist > 90.0 or facing.dot(to / dist) < 0.85:
			return
		f["fire"] = randf_range(1.2, 2.4)
		var vship := _rig_forward() * FORWARD_SPEED * speed_mult
		_enemy_shot(from, sp + vship * (dist / float(cfg["shot_speed"])))
	elif f["mode"] == "tail":
		if from.z < sp.z + 6.0 or from.z - sp.z > 90.0:
			return  # only fires from behind, and only when close enough to be a threat
		f["fire"] = randf_range(1.1, 1.8)
		_enemy_shot(from, sp, 90.0)
	else:
		if from.z >= sp.z - 15.0:
			return
		f["fire"] = randf_range(1.5, 3.0) * (0.6 if f["kind"] == "tank" else 1.0)
		_enemy_shot(from, sp)
	f["recoil"] = 1.0


## by_player: shot down (wreck animation, wave credit, kill count). Otherwise rammed or escaped.
func _destroy_foe(f: Dictionary, by_player: bool) -> void:
	foes.erase(f)
	f["dead"] = true
	var n: Node3D = f["n"]
	var wid: int = f["wave"]
	if by_player:
		kills += 1
		if waves.has(wid) and waves[wid] > 0:
			waves[wid] -= 1
			if waves[wid] == 0:
				score += 500
				_drop_pickup(n.global_position)
				hud.toast("FORMATION CLEARED  +500")
		var mk = n.get_node_or_null("LockMark")
		if mk:
			mk.queue_free()
		n.scale = Vector3.ONE
		# Each kind goes down differently.
		var kind: String = f["kind"]
		if kind == "diver":
			Util.burst(self, n.global_position, Color(1.0, 0.6, 0.1), 30, 1.4)
			_sfx("boom")
			n.queue_free()
			return
		var life := 0.7
		var vy := 3.0
		var spin := Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-10, 10))
		var boom := 24
		if kind == "tank":
			life = 0.9
			vy = 9.0  # blast flips it into the air
			spin = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-3, 3))
			boom = 48
		elif kind == "ace":
			life = 1.0
			vy = 5.0
			spin = Vector3(0, randf_range(-3, 3), randf_range(-16, 16))  # flat spin
			boom = 40
		wrecks.append({"n": n, "life": life, "smoke": 0.0, "vy": vy, "spin": spin, "boom": boom})
	else:
		if waves.has(wid):
			waves[wid] = -1000
		n.queue_free()


## Shot-down enemies tumble, trail smoke, then blow up.
func _move_wrecks(delta: float) -> void:
	for w in wrecks.duplicate():
		var n: Node3D = w["n"]
		n.rotation += (w["spin"] as Vector3) * delta
		n.position.y += float(w["vy"]) * delta
		w["vy"] = float(w["vy"]) - 25.0 * delta
		if mode != "allrange":
			n.position.z += 6.0 * delta
		w["smoke"] = float(w["smoke"]) - delta
		if float(w["smoke"]) <= 0.0:
			w["smoke"] = 0.12
			Util.burst(self, n.global_position, Color(0.25, 0.25, 0.28), 4, 0.3)
		w["life"] = float(w["life"]) - delta
		if float(w["life"]) <= 0.0:
			Util.burst(self, n.global_position, Color(1.0, 0.55, 0.1), int(w["boom"]))
			_sfx("boom")
			wrecks.erase(w)
			n.queue_free()


## `back` is how far behind the ship a shot may be before it is culled: shots from fighters on your tail start there.
func _enemy_shot(from: Vector3, to: Vector3, back := 15.0) -> void:
	var s := Util.box(Vector3(0.4, 0.4, 0.4), Color(1.0, 0.5, 0.1))
	add_child(s)
	s.global_position = from
	shots.append({"n": s, "v": (to - from).normalized() * cfg["shot_speed"], "reflected": false, "back": back})


func _nearest_enemy(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var cands: Array = foes.duplicate()
	if not boss.is_empty():
		cands.append(boss)
	for t in cands:
		var d := from.distance_to(t["n"].global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _move_shots(delta: float) -> void:
	var sp := ship.global_position
	for s in shots.duplicate():
		var n: MeshInstance3D = s["n"]
		n.position += (s["v"] as Vector3) * delta
		var gone := false
		if s["reflected"]:
			for f in foes.duplicate():
				if n.position.distance_to(f["n"].position) < 2.6:
					_damage_target(f, 2.0)
					gone = true
					break
			if not gone:
				var bt := Bosses.hit_test(self, n.global_position)
				if not bt.is_empty():
					_damage_target(bt, 2.0, n.global_position)
					gone = true
			if _gone(n.global_position, 1.0e9):
				gone = true
		else:
			var d := n.position.distance_to(sp)
			if ship.rolling and d < 3.4:
				# Barrel roll bats the shot back at the nearest enemy.
				s["reflected"] = true
				var tgt := _nearest_enemy(n.position)
				var dir := _rig_forward()
				if not tgt.is_empty():
					dir = (tgt["n"].global_position - n.position).normalized()
				s["v"] = dir * 110.0
				var m: StandardMaterial3D = n.material_override
				m.albedo_color = Color(0.3, 0.9, 1.0)
				_sfx("deflect")
			elif ship.looping:
				pass  # the loop slips under shots
			elif d < 1.9:
				_hurt(cfg["shot_dmg"])
				gone = true
			elif _gone(n.global_position, float(s.get("back", 15.0))):
				gone = true
		if gone:
			shots.erase(s)
			n.queue_free()


# ------------------------------------------------------------------- level hazards

func _spawn_scenery() -> void:
	var trench: bool = cfg.get("trench", false)
	while scenery_z > rig.position.z - 220.0:
		var in_trench := trench and -scenery_z >= float(cfg["trench_from"])
		for side in [-1.0, 1.0]:
			if in_trench:
				_spawn_trench_wall(side)
				continue
			var h := randf_range(10.0, 34.0)
			var p := Util.box(Vector3(5, h, 5), cfg["pillar"],
					Vector3(side * randf_range(52.0, 80.0), -16.5 + h * 0.5, scenery_z))
			add_child(p)
			scenery.append(p)
		# Ground stripes give the eye something to measure speed against.
		for x in [-24.0, 0.0, 24.0]:
			var s := Util.box(Vector3(1.2, 0.1, 10.0), (cfg["ground"] as Color).lightened(0.25),
					Vector3(x, -16.4, scenery_z))
			add_child(s)
			scenery.append(s)
		scenery_z -= 25.0
	for p in scenery.duplicate():
		if p.position.z > rig.position.z + 20.0:
			scenery.erase(p)
			p.queue_free()


## One section of trench wall: a slab with a ledge and a strip of lights, which is what sells the speed.
func _spawn_trench_wall(side: float) -> void:
	var half := float(cfg["trench_half"])
	var c: Color = cfg["pillar"]
	var slab := Util.box(Vector3(8, 50, 26), c, Vector3(side * (half + 4.0), 8.0, scenery_z))
	add_child(slab)
	scenery.append(slab)
	var ledge := Util.box(Vector3(2.4, 1.2, 26), c.lightened(0.12), Vector3(side * (half - 1.0), randf_range(-6.0, 12.0), scenery_z))
	add_child(ledge)
	scenery.append(ledge)
	var light := Util.glow(Util.box(Vector3(0.3, 0.6, 9.0), Color(0.5, 0.9, 1.0), Vector3(side * (half - 0.1), randf_range(-12.0, 16.0), scenery_z)),
			Color(0.4, 0.8, 1.0), 2.0)
	add_child(light)
	scenery.append(light)


## Trench walls scrape: touch one and you lose a little shield and are pushed back in.
func _check_trench() -> void:
	if not cfg.get("trench", false) or -rig.position.z < float(cfg["trench_from"]) + 20.0:
		return
	var limit := float(cfg["trench_half"]) - 2.0
	if absf(ship.position.x) > limit:
		ship.position.x = signf(ship.position.x) * limit
		if iframes <= 0.0:
			Util.burst(self, ship.global_position + Vector3(signf(ship.position.x) * 2.0, 0, 0), Color(1.0, 0.8, 0.3), 14, 0.7)
			_hurt(8.0)


func _spawn_obstacles(gap_mult := 1.0, kinds: Array = []) -> void:
	var oc: Dictionary = cfg["obstacles"]
	while next_obs_z > rig.position.z - 240.0:
		# Never drop one in the boss arena.
		if -next_obs_z < cfg["boss_z"] - 150.0:
			var pool: Array = kinds if not kinds.is_empty() else oc["kinds"]
			var kind: String = pool.pick_random()
			obstacles.append(Obstacles.spawn(self, next_obs_z, kind, (cfg["pillar"] as Color).lightened(0.1)))
		next_obs_z -= float(oc["gap"]) * gap_mult * randf_range(0.8, 1.2)
	for o in obstacles.duplicate():
		if o["z"] > rig.position.z + 25.0:
			obstacles.erase(o)
			o["n"].queue_free()


func _check_obstacles() -> void:
	var sp := ship.global_position
	for o in obstacles:
		if mode != "allrange" and absf(float(o["z"]) - sp.z) > 8.0:
			continue
		for b in o["boxes"]:
			if (b as AABB).grow(1.8).has_point(sp):
				if iframes <= 0.0:
					Util.burst(self, sp, Color(1.0, 0.8, 0.3), 18, 0.8)
				_hurt(25.0)
				shake = 1.0
				return


## Asteroid fields: clusters of drifting rocks ahead of the ship.
func _spawn_rocks(mult: float) -> void:
	while next_rock_z > rig.position.z - 240.0:
		if -next_rock_z < cfg["boss_z"] - 100.0:
			for i in randi_range(2, 4):
				var size: int = [1, 1, 2, 2, 3].pick_random()
				var pos := Vector3(randf_range(-ARENA.x, ARENA.x), randf_range(-ARENA.y, ARENA.y),
						next_rock_z + randf_range(-12.0, 12.0))
				_spawn_rock(pos, size)
		next_rock_z -= float(cfg["rocks"]["gap"]) * mult * randf_range(0.8, 1.2)


func _spawn_rock(pos: Vector3, size: int, vel := Vector3.INF) -> Dictionary:
	var n := Obstacles.rock(self, pos, size, cfg["pillar"])
	var v := vel
	if v == Vector3.INF:
		v = Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(2, 9))
	var rk := {"n": n, "size": size, "hp": Obstacles.ROCK_HP[size], "vel": v, "r": Obstacles.ROCK_RADIUS[size],
			"spin": Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))}
	rocks.append(rk)
	return rk


func _move_rocks(delta: float) -> void:
	var sp := ship.global_position
	for rk in rocks.duplicate():
		var n: Node3D = rk["n"]
		n.position += (rk["vel"] as Vector3) * delta
		n.rotation += (rk["spin"] as Vector3) * delta
		if n.global_position.distance_to(sp) < float(rk["r"]) + 1.5:
			if iframes <= 0.0:
				_hurt(12.0 + int(rk["size"]) * 6.0)
				_break_rock(rk, false, false)
		elif _gone(n.global_position, 25.0):
			rocks.erase(rk)
			n.queue_free()


func _hit_rock(rk: Dictionary, dmg: int) -> void:
	rk["hp"] = int(rk["hp"]) - dmg
	if int(rk["hp"]) <= 0:
		_break_rock(rk, true, true)
	else:
		Util.burst(self, rk["n"].global_position, Color(0.8, 0.7, 0.6), 5, 0.5)


## Big rocks split into two smaller ones that fly apart.
func _break_rock(rk: Dictionary, by_player: bool, allow_split: bool) -> void:
	rocks.erase(rk)
	var n: Node3D = rk["n"]
	var size: int = rk["size"]
	var pos := n.global_position
	Util.burst(self, pos, Color(0.7, 0.6, 0.5), 8 + size * 6, 0.8 + size * 0.2)
	if size > 1:
		_sfx("boom")
	if allow_split and size > 1:
		var base: Vector3 = rk["vel"]
		for i in 2:
			var kick := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.3, 0.3)).normalized() * 7.0
			_spawn_rock(pos + kick.normalized() * float(rk["r"]) * 0.6, size - 1, base + kick)
	if by_player:
		score += 20 * size
		if size == 3 and randf() < 0.12:
			_drop_pickup(pos)
	n.queue_free()


## Flight rings: thread the middle to build a combo, miss and it resets.
func _spawn_rings() -> void:
	while next_ring_z > rig.position.z - 240.0:
		if -next_ring_z < cfg["boss_z"] - 100.0:
			var pos := Vector3(randf_range(-16.0, 16.0), randf_range(-8.0, 8.0), next_ring_z)
			rings.append({"n": Obstacles.ring(self, pos), "z": next_ring_z, "done": false, "prev": 1.0e9})
		next_ring_z -= float(cfg["rings_gap"]) * randf_range(0.8, 1.2)


func _move_rings(delta: float) -> void:
	var sp := ship.global_position
	for r in rings.duplicate():
		var n: Node3D = r["n"]
		n.rotation.z += delta * 0.8
		if not r["done"] and float(r["prev"]) > float(r["z"]) and sp.z <= float(r["z"]):
			r["done"] = true
			var off := Vector2(sp.x - n.position.x, sp.y - n.position.y).length()
			if off < 6.0:
				combo += 1
				score += 100 * combo
				gauge = minf(gauge + 0.25, 1.0)
				hud.toast("RING  x%d" % combo)
				_sfx("pick")
				for c in n.get_children():
					Util.glow(c, Color(0.3, 1.0, 0.4), 3.0)
			else:
				if combo > 0:
					hud.toast("COMBO LOST")
				combo = 0
		r["prev"] = sp.z
		if _gone(n.global_position, 25.0):
			rings.erase(r)
			n.queue_free()


# ------------------------------------------------------------------------------ HUD

func _update_hud() -> void:
	var msg := ""
	match state:
		"title":
			msg = "ARWING-LIKE  (working title)\n\nHI SCORE %d\n\nWASD move    aim with the mouse    LMB / SPACE fire\nhold RMB / C lock-on, release to launch    B / MMB smart bomb\nSHIFT boost    CTRL brake    Q / E barrel roll (reflects shots)\nF loop  (U-turn in the dogfight level)    P pause\n\nPress SPACE to start" % maxi(high_score, 0)
		"paused":
			msg = "PAUSED  -  P to resume"
		"dead":
			msg = "GAME OVER  -  R to restart"
		"won":
			var last := level_idx + 1 >= LEVELS.size()
			msg = "LEVEL COMPLETE  -  R for %s" % ("a new run" if last else "the next level")
	var progress := 0
	if mode == "allrange":
		progress = 100 if boss_spawned else clampi(int(float(kills) / float(cfg["quota"]) * 100.0), 0, 100)
	else:
		progress = clampi(int(-rig.position.z / cfg["boss_z"] * 100.0), 0, 100)
	var extra := "WEAPON %d    BOMBS %d" % [weapon, bombs]
	if combo > 1:
		extra += "    COMBO x%d" % combo
	if overdrive_t > 0.0:
		extra += "    OVERDRIVE %.0f" % overdrive_t
	for f in foes:
		if f["mode"] == "tail" and f["n"].global_position.z > ship.global_position.z:
			extra += "    TAIL!"
			break
	if not boss.is_empty() and boss["kind"] == "port":
		extra += "    VENT OPEN - FIRE A TORPEDO (hold RMB, release)" if boss["open"] else "    LOCK THE VENT"
	if mode == "allrange":
		var edge := Vector2(rig.position.x, rig.position.z).length()
		if edge > float(cfg["arena"]) - 30.0:
			extra += "    ARENA EDGE - TURNING BACK"
	hud.update({
		"level": cfg["name"], "score": score, "high": maxi(high_score, score), "progress": progress,
		"hp": maxf(hp, 0.0) / 100.0, "shield": shield / SHIELD_MAX, "gauge": gauge, "locked": gauge_locked,
		"boss": Bosses.ratio(self),
		"extra": extra, "message": msg, "state": state,
	})

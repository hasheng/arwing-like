extends Node
## Procedural chiptune sequencer. Each song is rendered once from a small data table into looping
## stems (bass, drums, arp, lead) that play in sync; the game turns stems up and down with intensity.
## No audio assets and no dependencies: pulse/triangle/noise voices written straight into PCM.

const RATE := 16000
const BARS := 4
const STEPS := 16  # per bar, sixteenth notes
const STEMS := ["bass", "drums", "arp", "lead"]

## root: MIDI note of the tonic. prog: chord root offsets, one per bar. minor picks the third.
const SONGS := {
	"rail": {"bpm": 144, "root": 50, "minor": false, "prog": [0, 9, 5, 7], "bass": "drive", "drums": "four", "lead": "bright", "seed": 11},
	"asteroid": {"bpm": 118, "root": 45, "minor": true, "prog": [0, 8, 3, 10], "bass": "pulse", "drums": "sparse", "lead": "airy", "seed": 23},
	"allrange": {"bpm": 156, "root": 43, "minor": true, "prog": [0, 5, 8, 7], "bass": "run", "drums": "break", "lead": "bright", "seed": 37},
	"boss_rail": {"bpm": 168, "root": 50, "minor": true, "prog": [0, 1, 0, 10], "bass": "run", "drums": "gallop", "lead": "stab", "seed": 41},
	"boss_asteroid": {"bpm": 160, "root": 45, "minor": true, "prog": [0, 3, 8, 7], "bass": "drive", "drums": "gallop", "lead": "stab", "seed": 53},
	"boss_allrange": {"bpm": 176, "root": 43, "minor": true, "prog": [0, 8, 7, 1], "bass": "run", "drums": "gallop", "lead": "stab", "seed": 67},
	"trench": {"bpm": 128, "root": 41, "minor": true, "prog": [0, 0, 8, 7], "bass": "drive", "drums": "four", "lead": "stab", "seed": 71},
	"boss_trench": {"bpm": 152, "root": 41, "minor": true, "prog": [0, 1, 8, 7], "bass": "run", "drums": "gallop", "lead": "stab", "seed": 83},
	"victory": {"bpm": 132, "root": 55, "minor": false, "prog": [0, 5, 7, 0], "bass": "pulse", "drums": "four", "lead": "bright", "seed": 5, "bars": 2},
	"defeat": {"bpm": 70, "root": 45, "minor": true, "prog": [0, 8], "bass": "pulse", "drums": "sparse", "lead": "airy", "seed": 9, "bars": 2},
}

var _players: Dictionary = {}      # stem -> AudioStreamPlayer
var _target_db: Dictionary = {}    # stem -> where its volume is heading
static var _cache: Dictionary = {} # song -> {stem -> AudioStreamWAV}; shared so scene reloads do not re-render
var current := ""
var duck := 0.0                    # extra attenuation in dB (pause, game over)
var speed := 1.0                   # pitch/tempo, nudged by boost and brake
var master_db := -10.0


func _ready() -> void:
	for s in STEMS:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players[s] = p
		_target_db[s] = -80.0


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Render (or fetch) a song's stems.
func render(song: String) -> Dictionary:
	if _cache.has(song):
		return _cache[song]
	var d: Dictionary = SONGS[song]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	var bars: int = d.get("bars", BARS)
	var step_s := 60.0 / float(d["bpm"]) / 4.0
	var frames := int(round(step_s * STEPS * bars * RATE))
	var out: Dictionary = {}
	for s in STEMS:
		var buf := PackedFloat32Array()
		buf.resize(frames)
		match s:
			"bass":
				_bass(buf, d, bars, step_s)
			"drums":
				_drums(buf, d, bars, step_s, rng)
			"arp":
				_arp(buf, d, bars, step_s)
			"lead":
				_lead(buf, d, bars, step_s, rng)
		out[s] = _to_stream(buf)
	_cache[song] = out
	return out


## Switch to a song. Stems whose intensity floor is not met stay silent until set_intensity raises them.
func play_song(song: String, loop := true) -> void:
	if song == current:
		return
	var stems := render(song)
	current = song
	for s in STEMS:
		var p: AudioStreamPlayer = _players[s]
		var w: AudioStreamWAV = stems[s]
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		p.stream = w
		p.volume_db = -80.0
		p.play()
	set_intensity(0.0)


func set_intensity(level: float) -> void:
	# Bass is always on. Each further stem fades in as the action builds.
	_target_db["bass"] = 0.0
	_target_db["arp"] = 0.0 if level >= 0.2 else -80.0
	_target_db["drums"] = 0.0 if level >= 0.45 else -80.0
	_target_db["lead"] = 0.0 if level >= 0.75 else -80.0


func stop() -> void:
	current = ""
	for s in STEMS:
		_players[s].stop()
		_target_db[s] = -80.0


func _process(delta: float) -> void:
	for s in STEMS:
		var p: AudioStreamPlayer = _players[s]
		var want: float = float(_target_db[s])
		if want > -79.0:
			want += master_db - duck
		p.volume_db = move_toward(p.volume_db, want, delta * (60.0 if want < p.volume_db else 70.0))
		p.pitch_scale = lerpf(p.pitch_scale, speed, clampf(delta * 3.0, 0.0, 1.0))


# --------------------------------------------------------------------------- patterns

static func _chord(d: Dictionary, bar: int) -> Array:
	var prog: Array = d["prog"]
	var r: int = int(d["root"]) + int(prog[bar % prog.size()])
	var third := 3 if d["minor"] else 4
	return [r, r + third, r + 7]


static func _bass(buf: PackedFloat32Array, d: Dictionary, bars: int, step_s: float) -> void:
	for bar in bars:
		var root: int = _chord(d, bar)[0] - 24
		for st in STEPS:
			var t0 := (bar * STEPS + st) * step_s
			match d["bass"]:
				"drive":  # eighths, octave hop on the off-beat
					if st % 2 == 0:
						_voice(buf, t0, step_s * 1.8, midi_hz(root + (12 if st % 8 == 6 else 0)), 2, 0.5, 0.5)
				"run":  # relentless sixteenths with a walking fifth
					var walk: Array = [0, 0, 12, 0, 7, 0, 12, 0]
					var n: int = root + int(walk[st % 8])
					_voice(buf, t0, step_s * 0.9, midi_hz(n), 2, 0.5, 0.45)
				_:  # pulse: long root with a push into the next bar
					if st == 0 or st == 10:
						_voice(buf, t0, step_s * 5.0, midi_hz(root), 0, 0.25, 0.5)


static func _drums(buf: PackedFloat32Array, d: Dictionary, bars: int, step_s: float, rng: RandomNumberGenerator) -> void:
	for bar in bars:
		for st in STEPS:
			var t0 := (bar * STEPS + st) * step_s
			var kick := false
			var snare := false
			var hat := false
			match d["drums"]:
				"four":
					kick = st % 4 == 0
					snare = st % 8 == 4
					hat = st % 2 == 0
				"sparse":
					kick = st == 0 or st == 10
					snare = st == 8
					hat = st % 4 == 2
				"break":
					kick = st in [0, 3, 8, 11]
					snare = st % 8 == 4
					hat = true
				_:  # gallop: kick on every pulse with snare fills at the end of each bar
					kick = st % 4 == 0 or st in [3, 7, 11]
					snare = st % 8 == 4 or (bar % 2 == 1 and st >= 12)
					hat = st % 2 == 1
			if kick:
				_kick(buf, t0)
			if snare:
				_noise(buf, t0, 0.13, 0.5, rng, 1)
				_voice(buf, t0, 0.08, 190.0, 1, 0.5, 0.25)
			if hat:
				_noise(buf, t0, 0.04, 0.22, rng, 2)


static func _arp(buf: PackedFloat32Array, d: Dictionary, bars: int, step_s: float) -> void:
	var order := [0, 1, 2, 1, 0, 1, 2, 1] if d["bass"] != "pulse" else [0, 2, 1, 2]
	for bar in bars:
		var ch := _chord(d, bar)
		for st in STEPS:
			var n: int = ch[order[st % order.size()]] + 12 + (12 if st % 8 >= 6 else 0)
			_voice(buf, (bar * STEPS + st) * step_s, step_s * 0.85, midi_hz(n), 0, 0.125, 0.22)


static func _lead(buf: PackedFloat32Array, d: Dictionary, bars: int, step_s: float, rng: RandomNumberGenerator) -> void:
	var scale: Array = [0, 2, 3, 5, 7, 8, 10] if d["minor"] else [0, 2, 4, 5, 7, 9, 11]
	var idx := 4
	var st := 0
	var total := bars * STEPS
	while st < total:
		var bar := st / STEPS
		var ch := _chord(d, bar)
		var len_steps: int = [2, 2, 4, 3, 6][rng.randi() % 5]
		if d["lead"] == "stab":
			len_steps = [1, 1, 2][rng.randi() % 3]
		elif d["lead"] == "airy":
			len_steps = [4, 6, 8][rng.randi() % 3]
		if rng.randf() < 0.18:
			st += len_steps  # rest
			continue
		idx = clampi(idx + rng.randi_range(-2, 2), 0, 9)
		var note: int = int(d["root"]) + 12 + int(ch[0] - d["root"]) + int(scale[idx % 7]) + 12 * (idx / 7)
		# Land chord tones on the strong beats so it always sounds like it belongs.
		if st % 8 == 0:
			note = ch[rng.randi() % 3] + 12
		_voice(buf, st * step_s, len_steps * step_s * 0.95, midi_hz(note), 0, 0.5 if d["lead"] != "airy" else 0.25, 0.3, 0.004 * (1 + int(d["lead"] == "airy") * 8))
		st += len_steps


# ------------------------------------------------------------------------------ voices

## wave: 0 pulse (duty), 1 square-ish with fast drop for snare body, 2 triangle.
static func _voice(buf: PackedFloat32Array, start_s: float, dur_s: float, freq: float, wave: int, duty: float, vol: float, attack_s := 0.004) -> void:
	var i0 := int(start_s * RATE)
	var n := int(dur_s * RATE)
	var size := buf.size()
	var inc := freq / RATE
	var ph := 0.0
	var atk := maxf(attack_s * RATE, 1.0)
	for i in n:
		var idx := (i0 + i) % size  # wrap so tails ring into the loop start
		var x := float(i) / n
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
		var s: float
		if wave == 2:
			s = 4.0 * absf(ph - 0.5) - 1.0
		elif wave == 1:
			s = (1.0 if ph < duty else -1.0) * (1.0 - x)
		else:
			s = 1.0 if ph < duty else -1.0
		var e := minf(float(i) / atk, 1.0) * (1.0 - x)
		buf[idx] += s * vol * e


static func _kick(buf: PackedFloat32Array, start_s: float) -> void:
	var i0 := int(start_s * RATE)
	var n := int(0.16 * RATE)
	var size := buf.size()
	var ph := 0.0
	for i in n:
		var x := float(i) / n
		ph += TAU * lerpf(150.0, 42.0, sqrt(x)) / RATE
		buf[(i0 + i) % size] += sin(ph) * (1.0 - x) * 0.85


## kind 1 snare-ish noise, 2 hat (differenced so the low end drops out).
static func _noise(buf: PackedFloat32Array, start_s: float, dur_s: float, vol: float, rng: RandomNumberGenerator, kind: int) -> void:
	var i0 := int(start_s * RATE)
	var n := int(dur_s * RATE)
	var size := buf.size()
	var prev := 0.0
	for i in n:
		var x := float(i) / n
		var r := rng.randf() * 2.0 - 1.0
		var s := r - prev if kind == 2 else r
		prev = r
		buf[(i0 + i) % size] += s * vol * (1.0 - x) * (1.0 - x)


static func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 14000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_end = buf.size()
	return w

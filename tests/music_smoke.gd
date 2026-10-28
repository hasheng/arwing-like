extends SceneTree
## Headless smoke test for the music sequencer: every song renders, loops, is audible and clip-free.

const Music = preload("res://music.gd")


func _peak(w: AudioStreamWAV) -> int:
	var peak := 0
	for i in range(0, w.data.size() / 2, 7):
		peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
	return peak


func _initialize() -> void:
	var mus := Music.new()
	root.add_child(mus)
	await process_frame
	var t0 := Time.get_ticks_msec()
	for song in Music.SONGS:
		var stems: Dictionary = mus.render(song)
		var d: Dictionary = Music.SONGS[song]
		var bars: int = d.get("bars", Music.BARS)
		var want := int(round(60.0 / float(d["bpm"]) / 4.0 * Music.STEPS * bars * Music.RATE))
		var lens := {}
		for s in Music.STEMS:
			var w: AudioStreamWAV = stems[s]
			assert(w.data.size() == want * 2, "%s/%s length off" % [song, s])
			lens[w.data.size()] = true
			var p := _peak(w)
			assert(p > 800, "%s/%s is silent (peak %d)" % [song, s, p])
			assert(p < 32000, "%s/%s clips (peak %d)" % [song, s, p])
		assert(lens.size() == 1, "%s stems differ in length, they would drift apart" % song)
	print("rendered %d songs in %d ms" % [Music.SONGS.size(), Time.get_ticks_msec() - t0])

	# Rendering is deterministic: the same song twice gives byte-identical stems.
	var again := Music.new()
	root.add_child(again)
	var a: AudioStreamWAV = mus.render("rail")["lead"]
	var b: AudioStreamWAV = again.render("rail")["lead"]
	assert(a.data == b.data, "render is not deterministic")

	# Playback: bass is on at once, other stems arrive with intensity, and a song change keeps them in sync.
	mus.play_song("rail")
	await process_frame
	assert(mus._players["bass"].playing, "bass not playing")
	assert(mus._players["drums"].volume_db < -60.0, "drums should be silent at intensity 0")
	mus.set_intensity(1.0)
	mus._process(5.0)  # fades are time-based; headless frames are far shorter than real ones
	for s in Music.STEMS:
		assert(mus._players[s].playing and mus._players[s].volume_db > -20.0, "%s not audible at full intensity" % s)
	mus.duck = 12.0
	mus._process(5.0)
	assert(mus._players["bass"].volume_db < -12.0, "duck did not lower the music")
	mus.duck = 0.0
	mus.play_song("boss_rail")
	assert(mus.current == "boss_rail", "song did not switch")
	mus.stop()
	assert(not mus._players["bass"].playing, "stop did not stop")
	print("MUSIC SMOKE OK")
	quit()

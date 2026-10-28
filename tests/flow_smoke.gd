extends SceneTree
## Headless smoke test for title -> play -> pause flow and high-score persistence.

func _initialize() -> void:
	var script = load("res://main.gd")
	script.started = false
	script.level_idx = 0
	script.carry_score = 0
	script.high_score = -1
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	assert(m.state == "title", "should start on title")
	var z0: float = m.rig.position.z
	await physics_frame
	assert(m.rig.position.z == z0, "rig moved on title screen")
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	assert(m.state == "play" and script.started, "fire did not start the game")
	Input.action_press("pause")
	await physics_frame
	await physics_frame
	Input.action_release("pause")
	assert(m.state == "paused", "pause failed")
	var zp: float = m.rig.position.z
	await physics_frame
	assert(m.rig.position.z == zp, "rig moved while paused")
	m.state = "play"
	m.score = 123456789
	m._end_run("dead")
	assert(script.high_score == 123456789, "high score not updated")
	assert(m._load_high() == 123456789, "high score not persisted")
	DirAccess.remove_absolute(script.SAVE_PATH)  # leave no test score behind
	print("FLOW SMOKE OK")
	quit()

extends SceneTree

var output_directory: String = ""


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
	if output_directory == "":
		output_directory = ProjectSettings.globalize_path("res://test-results/journey-window-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output_directory)
	call_deferred("_play")


func _play() -> void:
	var witness: Dictionary = load("res://tools/journey_runner.gd").new().run()
	if not witness.ok:
		print("FAIL: witness ", witness.reason)
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = output_directory + "/saves"
	root.add_child(game)
	game.start_new_game()
	var driver = load("res://tests/test_game.gd").new()
	for action in witness.actions:
		if action.kind == "wait":
			for _i in range(roundi(action.seconds / 0.1)):
				game._process(0.1)
			continue
		game.select_tool(action.kind)
		if action.kind in ["root", "vine"]:
			if not game.service.state.nodes.has(action.target):
				_fail("Missing input target", action)
				return
			var origin: Vector2 = game.service.state.nodes[action.target].pos
			driver._drag(game, game.world.to_screen(origin), game.world.to_screen(origin + action.direction))
		else:
			var position: Vector2
			if action.kind == "leaf":
				position = game.service.state.nodes[action.target].pos
			else:
				var edge: Dictionary = game.service.state.edges[action.target]
				position = load("res://scripts/core/support_solver.gd").arc_midpoint(edge.points, edge.length)
			var before: int = game.service.state.revision
			_click(game, game.world.to_screen(position))
			if game.service.state.revision == before:
				_click(game, game.world.to_screen(position))
		if not game.service.state.nodes.has(action.node) or game.service.state.nodes[action.node].pos.distance_to(action.position) > 0.01:
			_fail("Mouse replay diverged from shared command geometry", action)
			return
		for _i in range(7):
			game._process(0.1)
		await process_frame
	for _i in range(55):
		game._process(0.1)
	await process_frame
	await RenderingServer.frame_post_draw
	if not game.service.state.won or not game.service.state.validate().is_empty():
		_fail("Full window replay did not win with a valid plant", {})
		return
	if not _capture(game, "ending.png"):
		return
	game.resume_game()
	await process_frame
	await RenderingServer.frame_post_draw
	if not _capture(game, "whole-plant.png"):
		return
	var saved: Dictionary = game.save_progress()
	var loaded: Dictionary = game.saves.load_latest()
	if not saved.ok or not loaded.ok or not loaded.state.won:
		_fail("Completed chapter did not reload", {})
		return
	var metrics: Dictionary = game.service.metrics()
	var report: Dictionary = {"won": true, "actions": load("res://scripts/core/save_service.gd")._encode(witness.actions),
		"simulated_seconds": float(game.service.state.tick) * 0.1, "edges": game.service.state.edges.size(),
		"leaves": game.service.state.leaves.size(), "energy": game.service.state.energy,
		"supply": metrics.water.q, "demand": metrics.water.demand, "risk": metrics.support.max_risk,
		"income": metrics.income, "saved_generation": saved.generation, "reloaded_won": loaded.state.won}
	var report_path: String = output_directory + "/journey-report.json"
	if FileAccess.file_exists(report_path):
		_fail("Evidence target already exists", {})
		return
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("INPUT_JOURNEY won=true edges=%d leaves=%d q=%.0f demand=%.2f risk=%.3f reloaded=true" % [report.edges, report.leaves, report.supply, report.demand, report.risk])
	print("JOURNEY_EVIDENCE ", output_directory)
	quit()


func _click(game, position: Vector2) -> void:
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = position
	game._unhandled_input(click)
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	click.position = position
	game._unhandled_input(click)


func _capture(game, filename: String) -> bool:
	var path: String = output_directory + "/" + filename
	if FileAccess.file_exists(path):
		_fail("Capture target already exists", {})
		return false
	var error: int = game.get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		_fail("Cannot write screenshot", {"error": error})
		return false
	return true


func _fail(message: String, details: Dictionary) -> void:
	print("FAIL: ", message, " ", details)
	quit(1)

extends SceneTree

var output: String = ""

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	call_deferred("_play")


func _play() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/opening-saves-%d" % Time.get_ticks_usec()
	root.add_child(game)
	game.start_new_game()
	var driver = load("res://tests/test_game.gd").new()
	for _i in range(2):
		var start: Vector2 = game.service.state.nodes[game.selected_node].pos
		driver._drag(game, game.world.to_screen(start), game.world.to_screen(start + Vector2(0, -0.8)))
		await create_timer(0.65).timeout
	game.selected_node = 1
	game.select_tool("vine")
	for degree in [90.0, 60.0, 0.0]:
		var start: Vector2 = game.service.state.nodes[game.selected_node].pos
		driver._drag(game, game.world.to_screen(start), game.world.to_screen(start + Vector2.from_angle(deg_to_rad(degree))))
		await create_timer(0.65).timeout
	game.select_tool("leaf")
	var click = InputEventMouseButton.new()
	click.position = game.world.to_screen(game.service.state.nodes[game.selected_node].pos)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	await create_timer(0.65).timeout
	var metrics: Dictionary = game.service.metrics()
	print("INPUT_OPENING edges=", game.service.state.edges.size(), " leaves=", game.service.state.leaves.size(), " income=", metrics.income)
	if game.service.state.edges.size() != 5 or game.service.state.leaves.size() != 1 or metrics.income < 0.95:
		quit(1)
		return
	if output != "":
		await RenderingServer.frame_post_draw
		var error: int = game.get_viewport().get_texture().get_image().save_png(output)
		print("CAPTURE_RESULT ", error, " ", output)
		quit(error)
	else:
		quit()

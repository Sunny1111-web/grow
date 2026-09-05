extends SceneTree

var directory: String = ""


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-dir="):
			directory = argument.trim_prefix("--save-dir=")
	if directory == "":
		directory = "res://test-results/close-saves-%d" % Time.get_ticks_usec()
	call_deferred("_close_probe")


func _close_probe() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = directory
	root.add_child(game)
	game.start_new_game()
	game.service.state.energy = 23.5
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	print("CLOSE_SAVE_DIR ", directory)

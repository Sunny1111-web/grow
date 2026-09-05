extends RefCounted


func run(t) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	t.check(scene.has_method("start_new_game"), "Main scene exposes playable game controller")
	if not scene.has_method("start_new_game"):
		scene.free()
		return
	t.root.add_child(scene)
	scene.start_new_game()
	t.check(scene.service.state.nodes.size() == 1, "New game creates single seed")
	t.check(scene.selected_tool == "root", "Opening tool is root")
	var point: Vector2 = scene.world.to_screen(Vector2(2, -0.8))
	_drag(scene, point, point + Vector2(5, 5))
	t.near(scene.service.state.energy, 30.0, 0.0001, "Less than12px gesture is selection only")
	_drag(scene, point, scene.world.to_screen(Vector2(2, -1.6)))
	t.check(scene.service.state.edges.size() == 1, "Mouse drag grows a root through command service")
	t.near(scene.service.state.energy, 26.0, 0.0001, "Mouse growth pays correct cost")
	t.check(scene.sim.frozen.has("animation"), "Growth animation freezes simulation")
	scene.select_tool("vine")
	t.check(scene.selected_tool == "vine", "Toolbar selects vine")
	var sense_down = InputEventKey.new()
	sense_down.keycode = KEY_SPACE
	sense_down.pressed = true
	scene._unhandled_input(sense_down)
	scene.show_pause()
	var sense_up = InputEventKey.new()
	sense_up.keycode = KEY_SPACE
	sense_up.pressed = false
	scene._unhandled_input(sense_up)
	t.check(scene.sim.frozen.has("menu"), "Pause menu freezes simulation")
	scene.resume_game()
	t.check(not scene.sim.frozen.has("menu"), "Resume removes only menu freeze")
	t.check(not scene.sim.frozen.has("sense"), "Releasing sense during menu cannot trap game paused")
	scene.free()


func _drag(scene, from: Vector2, to: Vector2) -> void:
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	scene._unhandled_input(down)
	var motion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	scene._unhandled_input(motion)
	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	scene._unhandled_input(up)

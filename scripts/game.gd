extends Node2D

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Saves = preload("res://scripts/core/save_service.gd")
const Simulation = preload("res://scripts/core/simulation.gd")
const World = preload("res://scripts/view/world_view.gd")
const Hud = preload("res://scripts/view/hud.gd")

var service
var saves
var save_directory: String = "user://saves/chapter1"
var load_status: Dictionary = {}
var commands_since_save: int = 0
var sim
var world
var hud
var selected_tool: String = "root"
var selected_node: int = 1
var selected_edge: int = 0
var proposal: Dictionary = {}
var sensing: bool = false
var pruning: bool = false
var dragging: bool = false
var panning: bool = false
var press_position: Vector2 = Vector2.ZERO
var cursor_position: Vector2 = Vector2.ZERO
var animation_remaining: float = 0.0
var growing_edge: int = 0
var command_serial: int = 0
var started: bool = false
var _victory_shown: bool = false
var _rescue_shown: bool = false
var memory_remaining: float = 0.0
var ending_elapsed: float = -1.0
var _events_seen: int = 0
var _ending_from_camera: Vector2 = Vector2.ZERO
var _ending_from_scale: float = 80.0
var _ending_target: Dictionary = {}
var _capture_path: String = ""
var _capture_frames: int = 0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
	if _capture_path != "":
		save_directory = "res://test-results/capture-saves-%d" % Time.get_ticks_usec()
	saves = Saves.new(save_directory)
	load_status = saves.load_latest()
	service = Commands.new(Model.create(), Level.new())
	sim = Simulation.new(service)
	world = World.new()
	world.game = self
	add_child(world)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	sim.set_frozen("menu", true)
	hud.show_title()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		if argument == "--autostart":
			start_new_game()


func start_new_game() -> void:
	_activate_state(Model.create())
	hud.set_message("从种子向下拖出两段根，寻找裂缝深处的水。按住空格感知湿润方向。")
	save_progress()


func continue_game() -> void:
	load_status = saves.load_latest()
	if not load_status.ok:
		hud.set_message(load_status.reason)
		return
	_activate_state(load_status.state)
	hud.set_message(load_status.reason if load_status.recovered else objective())


func _activate_state(plant) -> void:
	service = Commands.new(plant, Level.new())
	sim = Simulation.new(service)
	selected_node = 1
	selected_edge = 0
	selected_tool = "root" if service.env.water_contacts(plant).is_empty() else "vine"
	proposal = {}
	animation_remaining = 0.0
	started = true
	_victory_shown = plant.won
	_rescue_shown = false
	sensing = false
	pruning = false
	dragging = false
	panning = false
	commands_since_save = 0
	memory_remaining = 0.0
	ending_elapsed = -1.0
	_events_seen = plant.events.size()
	world.camera = Vector2(6.5, 1.0)
	world.unit_scale = 80.0
	if plant.won:
		var framing: Dictionary = world.growth_framing()
		world.camera = framing.camera
		world.unit_scale = framing.scale
	hud.close_modal()


func save_progress(manual: bool = false) -> Dictionary:
	if not started:
		return {"ok": true, "reason": "尚未开始游戏"}
	var result: Dictionary = saves.save(service.state)
	if result.ok:
		commands_since_save = 0
	if manual or not result.ok:
		hud.set_message(result.reason)
	return result


func request_quit() -> void:
	var result: Dictionary = save_progress()
	if result.ok:
		get_tree().quit()
	else:
		hud.set_message(result.reason + "。窗口已保留，可重试保存。")


func _process(delta: float) -> void:
	if sim == null:
		return
	if animation_remaining > 0.0:
		animation_remaining = maxf(0.0, animation_remaining - delta)
		sim.set_frozen("animation", animation_remaining > 0.0)
	if started:
		sim.advance(delta, Input.is_key_pressed(KEY_F), selected_cost())
		if sim.needs_rescue and not _rescue_shown:
			_rescue_shown = true
			show_rescue()
		if service.state.won and not _victory_shown:
			_begin_ending()
	_present_events()
	_update_presentation(delta)
	hud.refresh()
	world.queue_redraw()
	if _capture_path != "":
		_capture_frames += 1
		if _capture_frames == 8:
			_capture.call_deferred()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var picture = get_viewport().get_texture().get_image()
	var error: int = picture.save_png(_capture_path)
	print("CAPTURE_RESULT ", error, " ", _capture_path)
	get_tree().quit(error)


func _notification(what: int) -> void:
	if sim == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_preview()
		sensing = false
		pruning = false
		panning = false
		sim.set_frozen("sense", false)
		sim.set_frozen("focus", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		sim.set_frozen("focus", false)


func _unhandled_input(event: InputEvent) -> void:
	if not started or sim.frozen.has("menu"):
		return
	if event is InputEventKey:
		if event.keycode == KEY_SPACE:
			sensing = event.pressed
			sim.set_frozen("sense", sensing)
			return
		if event.keycode == KEY_SHIFT:
			pruning = event.pressed
			if not pruning:
				cancel_preview()
			return
		if not event.pressed or event.echo:
			return
		match event.keycode:
			KEY_1: select_tool("root")
			KEY_2: select_tool("vine")
			KEY_3: select_tool("leaf")
			KEY_4: select_tool("reinforce")
			KEY_ESCAPE:
				if not proposal.is_empty() or dragging:
					cancel_preview()
				else:
					show_pause()
			KEY_F5:
				save_progress(true)
			KEY_HOME:
				world.camera = service.state.nodes.get(selected_node, service.state.nodes[1]).pos
			KEY_TAB:
				_cycle_selection()
		return
	if event is InputEventMouseMotion:
		cursor_position = event.position
		if panning:
			world.camera += Vector2(-event.relative.x, event.relative.y) / world.unit_scale
			world.clamp_camera()
		elif dragging:
			_update_drag(event.position)
		elif pruning:
			_preview_prune(event.position)
		return
	if not event is InputEventMouseButton:
		return
	cursor_position = event.position
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		world.zoom_at(event.position, 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_preview()
		return
	if event.button_index != MOUSE_BUTTON_LEFT or animation_remaining > 0.0:
		return
	if pruning:
		if event.pressed:
			_preview_prune(event.position)
			finish_command()
		return
	if event.pressed:
		var hit: Dictionary = world.pick(event.position, selected_tool)
		if hit.is_empty():
			cancel_preview()
			return
		var node: int = hit.node
		var edge: int = hit.get("edge", 0)
		if selected_tool in ["leaf", "reinforce"]:
			var target: int = node if selected_tool == "leaf" else edge
			if proposal.get("target", -1) == target and proposal.get("kind", "") == selected_tool:
				finish_command()
			else:
				selected_node = node
				selected_edge = edge
				proposal = service.preview(selected_tool, target)
				sim.set_frozen("preview", true)
		else:
			selected_node = node
			selected_edge = edge
			press_position = event.position
			dragging = true
			sim.set_frozen("preview", true)
	else:
		if dragging:
			_update_drag(event.position)
			dragging = false
			if press_position.distance_to(event.position) >= 12.0:
				finish_command()
			else:
				cancel_preview()


func _update_drag(point: Vector2) -> void:
	if point.distance_to(press_position) < 12.0:
		proposal = {}
		return
	var direction: Vector2 = world.from_screen(point) - service.state.nodes[selected_node].pos
	proposal = service.preview(selected_tool, selected_node, direction)


func _preview_prune(point: Vector2) -> void:
	var hit: Dictionary = world.pick(point, "prune")
	if hit.is_empty():
		proposal = {}
		return
	var kind: String = "prune_leaf" if hit.get("leaf", 0) != 0 else "prune_edge"
	var target: int = hit.get("leaf", 0) if kind == "prune_leaf" else hit.get("edge", 0)
	proposal = service.preview(kind, target)
	sim.set_frozen("preview", true)


func select_tool(tool: String) -> void:
	cancel_preview()
	selected_tool = tool
	if tool in ["leaf", "reinforce"]:
		var target: int = selected_node if tool == "leaf" else selected_edge
		proposal = service.preview(tool, target)
		sim.set_frozen("preview", true)


func finish_command() -> void:
	if proposal.is_empty():
		cancel_preview()
		return
	command_serial += 1
	var old_income: float = sim.metrics.ordinary_income
	var result: Dictionary = service.commit(proposal, "%d-%d" % [Time.get_ticks_usec(), command_serial])
	if result.ok:
		sim.metrics = service.metrics()
		selected_node = result.node if service.state.nodes.has(result.node) else 1
		selected_edge = result.edge
		growing_edge = result.edge
		animation_remaining = 0.6
		sim.set_frozen("animation", true)
		if result.kind == "rescue":
			sim.needs_rescue = false
			sim.set_frozen("rescue_hint", false)
			_rescue_shown = false
			world.camera = Vector2(6.5, 1.0)
			hud.set_message("应急子叶开始供能。18 能量足够长出三段藤和一片普通叶。")
		else:
			hud.set_message(objective())
		world.ensure_visible(service.state.nodes[selected_node].pos)
		commands_since_save += 1
		if result.kind == "rescue" or commands_since_save >= 10 or (old_income < 0.05 and sim.metrics.ordinary_income >= 0.05):
			save_progress()
	else:
		hud.set_message(result.reason)
	cancel_preview()
	sim.metrics = service.metrics()


func cancel_preview() -> void:
	proposal = {}
	dragging = false
	sim.set_frozen("preview", false)


func show_pause() -> void:
	cancel_preview()
	sensing = false
	pruning = false
	sim.set_frozen("sense", false)
	sim.set_frozen("menu", true)
	hud.show_pause()


func resume_game() -> void:
	hud.close_modal()
	if sim.needs_rescue:
		sim.acknowledge_rescue_hint()
	sim.set_frozen("menu", false)
	sim.set_frozen("ending", false)
	ending_elapsed = -1.0


func show_rescue() -> void:
	cancel_preview()
	sim.set_frozen("menu", true)
	hud.show_rescue()


func confirm_rescue() -> void:
	proposal = service.preview("rescue", 1)
	finish_command()
	resume_game()


func selected_cost() -> float:
	return {"root": 4.0, "vine": 5.0, "leaf": 3.0, "reinforce": 6.0}.get(selected_tool, 5.0)


func objective() -> String:
	if service.env.water_contacts(service.state).is_empty():
		return "先让根接到水。空格感知方向，选种子后向下拖出根。"
	if sim.metrics.get("ordinary_income", 0.0) < 0.05:
		return "选回种子，按 2 长藤：向上穿过裂缝，再向右攀上椅座；按 3 长叶。"
	if service.state.won:
		return "你留下的每一道枝与伤痕，都成为通往光的路径。"
	return "沿椅子、桌沿和管道寻找支点。向右上方的窗外生长，必要时强化或修剪。"


func _cycle_selection() -> void:
	var hits: Array = world.pick_all(cursor_position, selected_tool)
	if hits.is_empty():
		return
	var index: int = 0
	for i in range(hits.size()):
		if hits[i].node == selected_node:
			index = (i + 1) % hits.size()
	selected_node = hits[index].node
	selected_edge = hits[index].get("edge", 0)
	if selected_tool in ["leaf", "reinforce"]:
		select_tool(selected_tool)


func return_to_title() -> void:
	var saved: Dictionary = save_progress()
	if not saved.ok:
		return
	cancel_preview()
	started = false
	ending_elapsed = -1.0
	sim.set_frozen("ending", false)
	sim.set_frozen("menu", true)
	load_status = saves.load_latest()
	hud.show_title()


func _begin_ending() -> void:
	_victory_shown = true
	cancel_preview()
	sim.set_frozen("ending", true)
	ending_elapsed = 0.0
	_ending_from_camera = world.camera
	_ending_from_scale = world.unit_scale
	_ending_target = world.growth_framing()
	save_progress()


func _present_events() -> void:
	var events: Array = service.state.events
	for index in range(_events_seen, events.size()):
		var event: Dictionary = events[index]
		if event.type == "memory":
			memory_remaining = event.duration
			sim.set_frozen("memory", true)
			hud.set_message(event.text)
			save_progress()
		elif event.type == "teaching" and memory_remaining <= 0.0:
			hud.set_message(event.text)
	_events_seen = events.size()


func _update_presentation(delta: float) -> void:
	if memory_remaining > 0.0:
		memory_remaining = maxf(0.0, memory_remaining - delta)
		if memory_remaining <= 0.0:
			sim.set_frozen("memory", false)
			hud.set_message(objective())
	if ending_elapsed >= 0.0 and ending_elapsed < 2.0:
		ending_elapsed = minf(2.0, ending_elapsed + delta)
		var fraction: float = ending_elapsed / 2.0
		var eased: float = fraction * fraction * (3.0 - 2.0 * fraction)
		world.camera = _ending_from_camera.lerp(_ending_target.camera, eased)
		world.unit_scale = lerpf(_ending_from_scale, _ending_target.scale, eased)
		if ending_elapsed >= 2.0:
			sim.set_frozen("menu", true)
			hud.show_victory()

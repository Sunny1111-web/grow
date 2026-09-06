extends Node2D

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Saves = preload("res://scripts/core/save_service.gd")
const Simulation = preload("res://scripts/core/simulation.gd")
const Levels = preload("res://scripts/core/levels.gd")
const Guide = preload("res://scripts/core/guide.gd")
const World = preload("res://scripts/view/world_view.gd")
const Hud = preload("res://scripts/view/hud.gd")
const GameAudio = preload("res://scripts/view/audio.gd")

var service
var saves
var level_id: String = Levels.APARTMENT
var save_root: String = "user://saves"
# 兼容旧测试入口：启动前注入save_directory时，把它作为独立测试档案根。
var save_directory: String = Levels.save_dir_for(Levels.APARTMENT)
var load_status: Dictionary = {}
var commands_since_save: int = 0
var sim
var world
var hud
var audio
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
var _history_merged_announced: bool = false
# 引导与消息优先级：事件/引导文案持有期间，低优先级文案不覆盖。
var guide_message: String = ""
var guide_active: bool = false
var message_hold: float = 0.0
var idle_time: float = 0.0
var _guide_helped: bool = false
var _guide_last_step: int = -1
var guide_flash_text: String = ""
var guide_flash_time: float = 0.0
# 设置（经 audio 的 ConfigFile 持久化）：界面缩放、感知切换、低动态。
var ui_scale: float = 1.0
var sensing_toggle: bool = false
var low_motion: bool = false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
	if _capture_path != "":
		save_root = "res://test-results/capture-saves-%d" % Time.get_ticks_usec()
	elif save_root == "user://saves" and save_directory != Levels.save_dir_for(Levels.APARTMENT):
		save_root = save_directory
	save_directory = chapter_save_dir(level_id)
	audio = GameAudio.new()
	add_child(audio)
	_load_game_settings()
	saves = Saves.new(save_directory, level_id)
	load_status = saves.load_latest()
	service = Commands.new(Model.create(), Levels.env_for(level_id))
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


func _load_game_settings() -> void:
	ui_scale = clampf(audio.setting("ui", "ui_scale", 1.0), 1.0, 1.6)
	sensing_toggle = audio.setting("ui", "sensing_toggle", false)
	low_motion = audio.setting("ui", "low_motion", false)


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, 1.0, 1.6)
	audio.set_setting("ui", "ui_scale", ui_scale)
	hud.apply_settings()


func set_sensing_toggle(enabled: bool) -> void:
	sensing_toggle = enabled
	audio.set_setting("ui", "sensing_toggle", enabled)


func set_low_motion(enabled: bool) -> void:
	low_motion = enabled
	audio.set_setting("ui", "low_motion", enabled)


func chapter_save_dir(id: String) -> String:
	return Levels.save_dir_for(id, save_root)


func chapter_status(id: String) -> Dictionary:
	if Levels.get_definition(id).is_empty():
		return {"ok": false, "found": false, "reason": "未知章节", "future_version": false}
	return Saves.new(chapter_save_dir(id), id).load_latest()


func is_chapter_unlocked(id: String) -> bool:
	return Levels.is_unlocked(id, save_root)


func next_chapter() -> String:
	for definition in Levels.ordered():
		if definition.unlock_after == level_id and is_chapter_unlocked(definition.id):
			return definition.id
	return ""


func open_next_chapter() -> void:
	var target: String = next_chapter()
	if target == "":
		return
	var status: Dictionary = chapter_status(target)
	if status.get("found", false):
		continue_game(target)
	else:
		start_new_game(target)


func start_new_game(target_level: String = "") -> void:
	_switch_level(level_id if target_level == "" else target_level, true)


func continue_game(target_level: String = "") -> void:
	_switch_level(level_id if target_level == "" else target_level, false)


func _chapter_error(reason: String) -> void:
	hud.set_message(reason)
	if hud.modal != null:
		hud.show_chapter_error(reason)


# 先验证目标和存档，成功后才一起替换章节/环境/状态/存档服务。
func _switch_level(target_level: String, fresh: bool) -> void:
	if Levels.get_definition(target_level).is_empty():
		_chapter_error("没有这个章节，当前生长已保留。")
		return
	if not is_chapter_unlocked(target_level):
		_chapter_error("先完成前一关，才能进入新的章节。")
		return
	var target_saves = Saves.new(chapter_save_dir(target_level), target_level)
	var status: Dictionary = target_saves.load_latest()
	if status.get("future_version", false) or (status.get("found", false) and not status.ok):
		_chapter_error(status.reason)
		return
	if not fresh and not status.ok:
		_chapter_error("这一章还没有可继续的进度，请选择开始。")
		return
	# 切换到另一章前保存当前现场；同章继续必须读取旧代，不能先覆盖它。
	if started and target_level != level_id:
		var current_saved: Dictionary = save_progress()
		if not current_saved.ok:
			return
	var plant = Model.create() if fresh else status.state
	if fresh and target_level != Levels.APARTMENT:
		plant.guide = {"step": 5, "skipped": true, "helped": false}
	if fresh:
		var saved: Dictionary = target_saves.save(plant)
		if not saved.ok:
			_chapter_error(saved.reason)
			return
	level_id = target_level
	save_directory = chapter_save_dir(level_id)
	saves = target_saves
	load_status = status
	_activate_state(plant, Levels.env_for(level_id))
	if fresh:
		hud.set_message(objective())
		message_hold = 6.0
	else:
		hud.set_message(status.reason if status.get("recovered", false) else objective())


func notice_history_merged(batched_count: int) -> void:
	if _history_merged_announced:
		return
	_history_merged_announced = true
	hud.set_message("旧痕迹已合并显示；%d 段历史仍完整保留在档案中。" % batched_count)


func _activate_state(plant, env = null) -> void:
	service = Commands.new(plant, env if env != null else Levels.env_for(level_id))
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
	_history_merged_announced = false
	message_hold = 0.0
	guide_message = ""
	guide_active = false
	_guide_helped = false
	_guide_last_step = -1
	guide_flash_text = ""
	guide_flash_time = 0.0
	hud.hide_guide()
	idle_time = 0.0
	world.camera = Vector2(6.5, 1.0)
	world.unit_scale = 80.0
	if plant.won:
		var framing: Dictionary = world.growth_framing()
		world.camera = framing.camera
		world.unit_scale = framing.scale
	hud.close_modal()
	hud.refresh_chapter_title()


func save_progress(manual: bool = false) -> Dictionary:
	if not started:
		return {"ok": true, "reason": "尚未开始游戏"}
	var result: Dictionary = saves.save(service.state)
	if result.ok:
		commands_since_save = 0
		if service.state.won:
			Levels.record_completion(level_id, save_root)
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
	message_hold = maxf(0.0, message_hold - delta)
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
	_update_guide(delta)
	_present_events()
	_update_presentation(delta)
	hud.refresh()
	if _capture_path != "":
		_capture_frames += 1
		if _capture_frames == 8:
			_capture.call_deferred()


# 引导卡驱动：步进时给出强调反馈；「长时间无进展」追加帮助进卡内。
# 事件文案持有期不覆盖（message_hold 管底部消息，引导卡独立显示）。
func _update_guide(delta: float) -> void:
	if not started or sim.frozen.has("menu"):
		return
	var result: Dictionary = Guide.evaluate(self)
	guide_active = result.active
	guide_message = result.message
	_guide_helped = service.state.guide.get("helped", false)
	if guide_flash_time > 0.0:
		guide_flash_time = maxf(0.0, guide_flash_time - delta)
	var step: int = result.step
	# 完成反馈只在本局真实引导过时出现：第二关新档 guide.step=5 不应闪现教学卡。
	if step != _guide_last_step and step > _guide_last_step and _guide_last_step >= 0 and Guide.STEP_FLASH.has(step):
		guide_flash_text = str(Guide.STEP_FLASH[step])
		guide_flash_time = 2.2 if step < Guide.STEPS.size() else 3.2
	_guide_last_step = step
	if guide_active:
		idle_time += delta
		var shown: String = guide_message
		var highlighted := false
		if guide_flash_time > 0.0 and guide_flash_text != "":
			shown = guide_flash_text
			highlighted = true
		elif idle_time >= Guide.IDLE_HELP_SECONDS and not _guide_helped:
			var help: String = Guide.request_help(self)
			if help != "":
				shown = shown + "\n" + help
		hud.set_guide(shown, step, Guide.STEPS.size(), highlighted)
	elif guide_flash_time > 0.0 and guide_flash_text != "":
		# 教学完成：反馈语短暂驻留后收起引导卡。
		hud.set_guide(guide_flash_text, Guide.STEPS.size(), Guide.STEPS.size(), true)
	else:
		hud.hide_guide()
		if not guide_message.is_empty() or idle_time > 0.0:
			guide_message = ""
			idle_time = 0.0


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
	# 结尾运镜期间不接受任何交互输入：避免 Esc/空格打断或遗留冻结。
	if ending_elapsed >= 0.0:
		return
	if event is InputEventKey:
		if event.keycode == KEY_SPACE:
			if event.echo:
				return
			if sensing_toggle:
				if event.pressed:
					toggle_sensing()
			else:
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
	idle_time = 0.0
	var old_income: float = sim.metrics.ordinary_income
	var result: Dictionary = service.commit(proposal, "%d-%d" % [Time.get_ticks_usec(), command_serial])
	if result.ok:
		sim.metrics = service.metrics()
		match result.kind:
			"root", "vine", "reinforce":
				audio.play("grow")
			"leaf":
				audio.play("leaf")
			"prune_edge", "prune_leaf":
				audio.play("prune")
			"rescue":
				audio.play("rescue")
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


# 感知模式的切换形态（设置里可选）：按住空格 或 点击/空格切换。
func toggle_sensing() -> void:
	sensing = not sensing
	sim.set_frozen("sense", sensing)
	if not sensing:
		world.queue_redraw()


func show_pause() -> void:
	cancel_preview()
	_release_transient_modes()
	sim.set_frozen("menu", true)
	hud.show_pause()


func resume_game() -> void:
	hud.close_modal()
	_release_transient_modes()
	if sim.needs_rescue:
		sim.acknowledge_rescue_hint()
	sim.set_frozen("menu", false)
	sim.set_frozen("ending", false)
	ending_elapsed = -1.0


func show_rescue() -> void:
	cancel_preview()
	_release_transient_modes()
	sim.set_frozen("menu", true)
	hud.show_rescue()


# 打开任何模态前清掉感知/修剪等瞬态模式：
# 按住的空格在模态冻结下收不到释放事件，否则会永久卡在感知暂停。
func _release_transient_modes() -> void:
	sensing = false
	pruning = false
	panning = false
	dragging = false
	sim.set_frozen("sense", false)


func replay_guide_hint() -> void:
	resume_game()
	var message: String = Guide.replay_message(self)
	message_hold = 8.0
	hud.set_message(message)


func skip_guide() -> void:
	Guide.skip(self)
	guide_active = false
	guide_message = ""
	resume_game()
	hud.set_message("已跳过引导。随时可在菜单里重看提示。")
	message_hold = 6.0


func confirm_rescue() -> void:
	proposal = service.preview("rescue", 1)
	finish_command()
	resume_game()


func selected_cost() -> float:
	return {"root": 4.0, "vine": 5.0, "leaf": 3.0, "reinforce": 6.0}.get(selected_tool, 5.0)


func objective() -> String:
	var text: String = service.env.objective(service.state, sim.metrics)
	if text != "":
		return text
	return "让这株植物继续生长。"


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
	audio.play("victory")
	cancel_preview()
	_release_transient_modes()
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
			message_hold = 6.0
			save_progress()
		elif event.type == "teaching" and memory_remaining <= 0.0:
			hud.set_message(event.text)
			message_hold = 7.0
			if event.get("id", "") == "tutorial_water":
				audio.play("water")
			# 教学检查点：接水、首次攀附、W2 后立即落盘，读档后不重播也不丢进度。
			if event.get("id", "") in ["tutorial_water", "tutorial_anchor", "tutorial_w2"]:
				save_progress()
		elif event.type == "rescue_hint":
			# 危机提示本身是检查点：把干渴计时与提示状态存下来。
			message_hold = 7.0
			save_progress()
		elif event.type in ["drought", "overload", "leaf_drought"]:
			audio.play("snap")
			message_hold = 6.0
			_explain_crisis(event)
	_events_seen = events.size()


# 危机解释：真实缺水或承重断裂发生时，讲清原因而不是只报事件名。
func _explain_crisis(event: Dictionary) -> void:
	match event.type:
		"drought":
			hud.set_message("一段枝干渴枯萎了：它的供水 r 降到 0 以下太久。修剪低效支路，或把根接向更近的水源。")
		"overload":
			hud.set_message("一段藤被自身重量压断了：悬空负载超过承受极限。强化成枝（4）或先攀上支点再伸展。")
		"leaf_drought":
			hud.set_message("一片叶干枯脱落了：水分没有送到这里。前方路径的耗水可能大于供给。")


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

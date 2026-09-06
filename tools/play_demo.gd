extends SceneTree

# 现场演示模式：真实时间回放约35秒的游戏流程，供手动录屏（Win+G / OBS）。
# 用法: godot --path <工程> --script res://tools/play_demo.gd
# 时间线: 5s准备(此时可开始录屏) -> 第一章20s(接水/攀附/长叶/拉远) -> 阳台9s -> 5s收尾。
# 控制台会在可开始录屏与演示结束时各打印一条 ">>" 提示。

var game: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# ---------- 第一章：开局（准备期，可开始录屏） ----------
	game = load("res://scenes/main.tscn").instantiate()
	game.save_root = "res://test-results/play-demo/saves"
	root.add_child(game)
	await process_frame
	game.start_new_game("apartment")
	DisplayServer.window_set_position(Vector2i(0, 0))
	await process_frame
	DisplayServer.window_move_to_foreground()
	print(">> 准备：5秒后开始演示，现在可以开始录屏")
	await _sleep(5.0)
	print(">> 演示开始：第一章接水")
	# 两段根接到水（世界-y向下）。
	await _drag(_world(_seed_pos()), _world(_seed_pos() + Vector2(0.0, -0.85)), 0.9)
	await _until(func(): return game.service.state.edges.size() > 0, 3.0)
	await _sleep(0.8)
	await _drag(_world(_seed_pos() + Vector2(0.0, -0.85)), _world(_seed_pos() + Vector2(0.0, -1.7)), 0.9)
	await _until(func(): return not game.service.env.water_contacts(game.service.state).is_empty(), 3.0)
	await _sleep(1.0)
	print(">> 长藤与攀附")
	game.select_tool("vine")
	await _drag(_world(_seed_pos()), _world(_seed_pos() + Vector2(0.0, 1.0)), 1.0)
	await _until(func(): return game.service.state.edges.size() >= 3, 3.0)
	await _drag(_world(_tip_pos()), _world(_tip_pos() + Vector2(0.5, 0.87)), 1.0)
	await _until(func(): return game.service.state.edges.size() >= 4, 3.0)
	await _sleep(0.6)
	print(">> 长叶供能")
	game.select_tool("leaf")
	var leaf_target: int = _top_node_id()
	await _click(leaf_target)
	await _sleep(0.4)
	await _click(leaf_target)
	await _sleep(3.5)
	print(">> 继续生长，拉远视角")
	game.select_tool("vine")
	await _drag(_world(_tip_pos()), _world(_tip_pos() + Vector2(0.95, 0.2)), 0.9)
	await _sleep(1.2)
	game.world.unit_scale = 58.0
	game.world.clamp_camera()
	await _sleep(2.8)
	# ---------- 第二章：阳台 ----------
	print(">> 第二章：断裂的阳台")
	game.queue_free()
	await process_frame
	var completed = load("res://scripts/core/plant_state.gd").create()
	completed.won = true
	load("res://scripts/core/save_service.gd").new("res://test-results/play-demo/saves/chapter1", "apartment").save(completed)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_root = "res://test-results/play-demo/saves"
	root.add_child(game)
	await process_frame
	game.start_new_game("balcony")
	game.world.ensure_visible(game.service.state.nodes[game.service.state.seed_id].pos)
	await _sleep(2.2)
	game.select_tool("vine")
	var balcony_seed: Vector2 = game.service.state.nodes[game.service.state.seed_id].pos
	await _drag(_world(balcony_seed), _world(balcony_seed + Vector2(0.0, 1.05)), 0.9)
	await _until(func(): return game.service.state.edges.size() > 0, 3.0)
	await _sleep(0.7)
	await _drag(_world(_top_node_pos()), _world(_top_node_pos() + Vector2(0.35, 0.94)), 0.9)
	await _until(func(): return game.service.state.edges.size() >= 2, 3.0)
	await _sleep(0.7)
	await _drag(_world(_top_node_pos()), _world(_top_node_pos() + Vector2(0.95, 0.32)), 0.9)
	await _sleep(3.0)
	print(">> 演示结束（5秒后自动关闭，可停止录屏）")
	await _sleep(5.0)
	quit(0)


func _world(position: Vector2) -> Vector2:
	return game.world.to_screen(position)


func _seed_pos() -> Vector2:
	return game.service.state.nodes[game.service.state.seed_id].pos


func _tip_pos() -> Vector2:
	return _top_node_pos()


func _top_node_pos() -> Vector2:
	return game.service.state.nodes[_top_node_id()].pos


func _top_node_id() -> int:
	var best: int = game.service.state.seed_id
	var best_y: float = -100.0
	for node in game.service.state.nodes.values():
		if node.emergency:
			continue
		if node.pos.y > best_y:
			best_y = node.pos.y
			best = node.id
	return best


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


# 轮询条件直到成立或超时（不失败，仅继续，保证演示不中断）。
func _until(condition: Callable, timeout: float) -> void:
	var deadline: float = Time.get_ticks_msec() + timeout * 1000.0
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await create_timer(0.1).timeout


func _drag(from: Vector2, to: Vector2, seconds: float) -> void:
	# 等待可能的生长动画结束。
	var deadline: float = Time.get_ticks_msec() + 3000.0
	while game.animation_remaining > 0.0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	game._unhandled_input(down)
	var steps: int = maxi(6, roundi(seconds * 30.0))
	for i in range(1, steps + 1):
		await create_timer(seconds / steps)
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(i) / float(steps))
		motion.relative = to - from
		game._unhandled_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	game._unhandled_input(up)


func _click(target: int) -> void:
	var position: Vector2 = game.world.to_screen(game.service.state.nodes[target].pos)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = position
	game._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = position
	game._unhandled_input(up)

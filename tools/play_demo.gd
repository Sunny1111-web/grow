extends SceneTree

# 现场演示模式：真实时间通关第一章，供手动录屏（Win+G / OBS）。
# 用法: godot --path <工程> --script res://tools/play_demo.gd
# 时间线: 准备期(快速推演到窗外前最后一个路标，此时可开始录屏)
#         -> 真实拖拽走完最后一段(带实时预览) -> 窗外健康足水3秒判定
#         -> 结局运镜 -> 通关卡(停留后自动关闭)。
# 控制台在可开始录屏与演示结束时各打印一条 ">>" 提示。

const WINDOW_TARGET: Vector2 = Vector2(16.8, 5.9)

var game: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_root = "res://test-results/play-demo/saves"
	root.add_child(game)
	await process_frame
	game.start_new_game("apartment")
	DisplayServer.window_set_position(Vector2i(0, 0))
	await process_frame
	DisplayServer.window_move_to_foreground()
	# ---------- 准备期：快速推演到窗外前最后一个路标（模拟暂停） ----------
	print(">> 正在布置第一关终盘…")
	game.sim.set_frozen("menu", true)
	var runner = load("res://tools/journey_runner.gd").new()
	runner.stop_before_last_waypoint = true
	var witness: Dictionary = runner.run()
	if not witness.ok:
		print(">> 布置失败：", witness.reason)
		quit(1)
		return
	# 接管推演出的世界与模拟（植物已长到最后一处支点，仅剩窗外一段）。
	game.service = runner.service
	game.sim = runner.sim
	game.selected_tool = "vine"
	print(">> 可开始录屏：第一关终盘，将真实拖拽走完窗外最后一段并通关")
	await _sleep(3.0)
	# ---------- 录屏段：真实拖拽走向窗外并通关 ----------
	game.sim.set_frozen("menu", false)
	await _sleep(0.5)
	if not await _walk_shoot_live(WINDOW_TARGET):
		print(">> 终盘走位失败，演示提前结束")
		await _sleep(3.0)
		quit(1)
		return
	print(">> 等待窗外通关判定…")
	var deadline: float = Time.get_ticks_msec() + 15000.0
	while not game.service.state.won and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	if not game.service.state.won:
		print(">> 未触发通关判定，演示提前结束")
		await _sleep(3.0)
		quit(1)
		return
	print(">> 通关！结局运镜与通关卡展示中")
	await _sleep(9.0)
	print(">> 演示结束（3秒后自动关闭，可停止录屏）")
	await _sleep(3.0)
	quit(0)


# 真实拖拽版走位：与旅程回放器同款的方向评分（风险作惩罚而非拒绝），
# 用鼠标拖拽提交，画面上可见预览曲线随拖拽生长。
func _walk_shoot_live(destination: Vector2) -> bool:
	for _segment in range(8):
		var origin: Vector2 = game.service.state.nodes[_top_node_id()].pos
		if origin.distance_to(destination) < 0.62 or game.service.state.won:
			return true
		var best: Dictionary = _best_growth_live("vine", _top_node_id(), destination)
		if best.is_empty():
			if not _reinforce_live():
				print(">> 走位失败：无合法方向且无法强化")
				return false
			best = _best_growth_live("vine", _top_node_id(), destination)
			if best.is_empty():
				print(">> 走位失败：强化后依然无合法方向")
				return false
		await _drag(_world(origin), _world(origin + best.direction * 1.0), 1.0)
		await _until(func(): return game.animation_remaining <= 0.0, 3.0)
		var tip_now: Vector2 = game.service.state.nodes[_top_node_id()].pos
		var risk: float = game.service.metrics().support.max_risk
		print(">> 走位段：末端 %s 距目标 %.2f 风险 %.2f E %.1f" % [tip_now, tip_now.distance_to(destination), risk, game.service.state.energy])
		if game.service.state.won:
			return true
	return game.service.state.nodes[_top_node_id()].pos.distance_to(destination) < 0.62


func _best_growth_live(kind: String, node: int, target: Vector2) -> Dictionary:
	var origin: Vector2 = game.service.state.nodes[node].pos
	var desired: float = (target - origin).angle()
	var best: Dictionary = {}
	var score: float = 1000000.0
	for offset in range(-55, 56, 5):
		var direction: Vector2 = Vector2.from_angle(desired + deg_to_rad(offset))
		var proposal: Dictionary = game.service.preview(kind, node, direction)
		if not proposal.ok:
			continue
		var endpoint: Vector2 = proposal.points.back()
		if endpoint.distance_to(target) > origin.distance_to(target) - 0.04:
			continue
		var value: float = endpoint.distance_to(target)
		value += maxf(0.0, proposal.metrics.support.max_risk - 0.9) * 0.5
		if not proposal.candidate.nodes[proposal.node].anchor.is_empty():
			value -= 0.15
		if value < score:
			score = value
			best = {"proposal": proposal, "direction": direction}
	return best


func _reinforce_live() -> bool:
	var before: float = game.service.metrics().support.max_risk
	var best: Dictionary = {}
	var best_risk: float = 1000000.0
	for edge in game.service.state.edges.values():
		if edge.kind != "vine":
			continue
		var proposal: Dictionary = game.service.preview("reinforce", edge.id)
		if proposal.ok and proposal.metrics.support.max_risk < best_risk:
			best_risk = proposal.metrics.support.max_risk
			best = proposal
	if best.is_empty() or best_risk >= before - 0.000001:
		return false
	return game.service.commit(best, "demo-reinforce").ok


func _world(position: Vector2) -> Vector2:
	return game.world.to_screen(position)


func _seed_pos() -> Vector2:
	return game.service.state.nodes[game.service.state.seed_id].pos


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

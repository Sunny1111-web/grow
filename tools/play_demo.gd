extends SceneTree

# 现场演示模式：全屏、真实时间，从种子一路玩到通关第一章，供手动录屏。
# 用法: godot --path <工程> --script res://tools/play_demo.gd
# 所有生长都是真实鼠标拖拽/点击（画面带实时预览曲线）；能量等待即真实等待。
# 控制台在各阶段打印 ">>" 提示；启动后有5秒准备期供开始录屏。

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
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await process_frame
	await process_frame
	DisplayServer.window_move_to_foreground()
	game.audio.set_volume("Master", 0.9)
	game.audio.set_volume("Ambience", 0.8)
	game.audio.set_volume("SFX", 0.8)
	print(">> 准备：5秒后开始演示，现在可以开始录屏")
	await _sleep(5.0)
	print(">> 演示开始：两段根接到裂缝深处的水")
	# ---------- 开局：两根接水 ----------
	await _drag(_world(_seed_pos()), _world(_seed_pos() + Vector2(0.0, -0.85)), 1.0)
	await _until(func(): return game.service.state.edges.size() > 0, 3.0)
	await _sleep(0.6)
	await _drag(_world(_seed_pos() + Vector2(0.0, -0.85)), _world(_seed_pos() + Vector2(0.0, -1.7)), 1.0)
	await _until(func(): return not game.service.env.water_contacts(game.service.state).is_empty(), 3.0)
	await _sleep(1.0)
	print(">> 三段藤攀上椅座，长叶供能")
	game.select_tool("vine")
	await _drag(_world(_seed_pos()), _world(_seed_pos() + Vector2(0.0, 1.0)), 1.0)
	await _until(func(): return game.service.state.edges.size() >= 3, 3.0)
	await _drag(_world(_tip_pos()), _world(_tip_pos() + Vector2(0.5, 0.87)), 1.0)
	await _until(func(): return game.service.state.edges.size() >= 4, 3.0)
	# 第三段藤沿椅座水平铺进晨光区（0.6强度），弱光区(0.2)长叶收入太低。
	await _drag(_world(_tip_pos()), _world(_tip_pos() + Vector2(1.0, 0.05)), 1.0)
	await _until(func(): return game.service.state.edges.size() >= 5, 3.0)
	await _sleep(0.5)
	game.select_tool("leaf")
	var leaf_target: int = _top_node_id()
	await _click(leaf_target)
	await _sleep(0.4)
	await _click(leaf_target)
	await _sleep(2.5)
	# ---------- 完整旅程：根须探到第二水源，藤蔓走向窗外 ----------
	print(">> 根须探向第二水源（时间会自然流逝，等待能量也是玩法）")
	if not await _walk_root_live(Vector2(8.0, -2.6)):
		print(">> 根线探路失败，演示提前结束")
		await _sleep(3.0)
		quit(1)
		return
	print(">> 藤蔓沿支点走向窗外")
	for waypoint_index in range(9):
		var waypoint: Vector2 = [Vector2(5.2, 1.04), Vector2(5.6, 2.0), Vector2(6.6, 3.7),
			Vector2(8.7, 3.54), Vector2(10.4, 3.54), Vector2(12.46, 4.7),
			Vector2(12.46, 5.5), Vector2(15.5, 5.9), Vector2(16.8, 5.9)][waypoint_index]
		if not await _walk_shoot_live(waypoint):
			print(">> 走位失败于 ", waypoint, "，演示提前结束")
			await _sleep(3.0)
			quit(1)
			return
	print(">> 等待窗外通关判定…")
	var deadline: float = Time.get_ticks_msec() + 20000.0
	while not game.service.state.won and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	if not game.service.state.won:
		print(">> 未触发通关判定，演示提前结束")
		await _sleep(3.0)
		quit(1)
		return
	print(">> 通关！结局运镜与通关卡展示中")
	await _sleep(10.0)
	print(">> 演示结束（3秒后自动关闭，可停止录屏）")
	await _sleep(3.0)
	quit(0)


# ---------- 真实输入版的旅程逻辑（与 journey_runner 同款决策） ----------

func _walk_root_live(destination: Vector2) -> bool:
	for _segment in range(16):
		if game.service.metrics().water.q >= 20.0:
			return true
		if game.service.state.energy < 30.0:
			if not await _refill_live(30.0):
				return false
		var best: Dictionary = _best_growth_live("root", _deep_node_id(), destination)
		if best.is_empty():
			return false
		await _drag(_world(game.service.state.nodes[_deep_node_id()].pos),
			_world(game.service.state.nodes[_deep_node_id()].pos + best.direction * 1.0), 1.0)
		await _until(func(): return game.animation_remaining <= 0.0, 3.0)
	return game.service.metrics().water.q >= 20.0


func _walk_shoot_live(destination: Vector2) -> bool:
	for _segment in range(8):
		var origin: Vector2 = _tip_pos()
		if origin.distance_to(destination) < 0.62 or game.service.state.won:
			return true
		if game.service.state.energy < 30.0:
			if not await _refill_live(30.0):
				return false
		var best: Dictionary = _best_growth_live("vine", _top_node_id(), destination)
		if best.is_empty():
			if not await _reinforce_live():
				return false
			best = _best_growth_live("vine", _top_node_id(), destination)
			if best.is_empty():
				return false
		await _drag(_world(_tip_pos()), _world(_tip_pos() + best.direction * 1.0), 1.0)
		await _until(func(): return game.animation_remaining <= 0.0, 3.0)
		if _risk_live() > 1.0:
			await _reinforce_live()
		# 收益足够就在新末端长叶。
		var leaf: Dictionary = game.service.preview("leaf", _top_node_id())
		var metrics: Dictionary = game.service.metrics()
		if leaf.ok and leaf.metrics.income - metrics.income >= 0.7 and leaf.metrics.water.demand < leaf.metrics.water.q - 1.0:
			game.select_tool("leaf")
			await _click(_top_node_id())
			await _sleep(0.4)
			await _click(_top_node_id())
			game.select_tool("vine")
			await _sleep(0.6)
		if game.service.state.won:
			return true
	return _tip_pos().distance_to(destination) < 0.62


func _refill_live(target: float) -> bool:
	print(">> 等待能量恢复到 %.0f E…" % target)
	var deadline: float = Time.get_ticks_msec() + 180000.0
	while Time.get_ticks_msec() < deadline:
		var energy: float = game.service.state.energy
		var income: float = game.service.metrics().income
		game.hud.set_message("等待能量恢复 %.1f / %.0f E（光合 +%.2f E/秒）—— 生长的节奏里，等待也是玩法" % [energy, target, income])
		if energy >= target:
			game.hud.set_message("能量充足，继续生长")
			return true
		if income < 0.05:
			game.hud.set_message("光合收入不足，无法继续补充能量")
			return false
		await create_timer(0.5).timeout
	game.hud.set_message("")
	return false


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
		var water_gain: bool = kind == "root" and proposal.metrics.water.q > game.service.metrics().water.q
		if endpoint.distance_to(target) > origin.distance_to(target) - 0.04 and not water_gain:
			continue
		var value: float = endpoint.distance_to(target) - (20.0 if water_gain else 0.0)
		if kind == "vine":
			value += maxf(0.0, proposal.metrics.support.max_risk - 0.9) * 0.5
			if not proposal.candidate.nodes[proposal.node].anchor.is_empty():
				value -= 0.15
		if value < score:
			score = value
			best = {"proposal": proposal, "direction": direction}
	return best


func _reinforce_live() -> bool:
	var before: float = _risk_live()
	var best: Dictionary = {}
	var best_risk: float = 1000000.0
	var best_point: Vector2 = Vector2.ZERO
	var support_solver = load("res://scripts/core/support_solver.gd")
	for edge in game.service.state.edges.values():
		if edge.kind != "vine":
			continue
		var proposal: Dictionary = game.service.preview("reinforce", edge.id)
		if proposal.ok and proposal.metrics.support.max_risk < best_risk:
			best_risk = proposal.metrics.support.max_risk
			best = proposal
			best_point = support_solver.arc_midpoint(edge.points, edge.length)
	if best.is_empty() or best_risk >= before - 0.000001:
		return false
	# 真实强化：选工具后点击该藤中点两次（第一次预览，第二次确认）。
	game.select_tool("reinforce")
	await _click_screen(_world(best_point))
	await _sleep(0.4)
	await _click_screen(_world(best_point))
	await _until(func(): return game.animation_remaining <= 0.0, 3.0)
	game.select_tool("vine")
	await _sleep(0.3)
	return _risk_live() < before + 0.000001


func _risk_live() -> float:
	return game.service.metrics().support.max_risk


func _world(position: Vector2) -> Vector2:
	return game.world.to_screen(position)


func _seed_pos() -> Vector2:
	return game.service.state.nodes[game.service.state.seed_id].pos


func _tip_pos() -> Vector2:
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


func _deep_node_id() -> int:
	var best: int = game.service.state.seed_id
	var best_y: float = 100.0
	for node in game.service.state.nodes.values():
		if node.emergency or node.kind != "root":
			continue
		if node.pos.y < best_y:
			best_y = node.pos.y
			best = node.id
	return best


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _until(condition: Callable, timeout: float) -> void:
	var deadline: float = Time.get_ticks_msec() + timeout * 1000.0
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await create_timer(0.1).timeout


func _drag(from: Vector2, to: Vector2, seconds: float) -> void:
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
	_click_screen(_world(game.service.state.nodes[target].pos))


func _click_screen(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = position
	game._unhandled_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = position
	game._unhandled_input(up)

extends "res://tools/capture_journey.gd"


func _play() -> void:
	var base: String = output_directory
	for route in ["upper", "lower"]:
		output_directory = base + "/" + route
		DirAccess.make_dir_recursive_absolute(output_directory)
		if not await _play_route(route):
			return
	print("INPUT_BALCONY routes=2 won=true reloaded=true")
	print("BALCONY_EVIDENCE ", base)
	quit()


func _play_route(route: String) -> bool:
	var witness: Dictionary = load("res://tools/balcony_runner.gd").new().run(route)
	if not witness.ok:
		_fail("阳台规则回放失败", {"route": route, "reason": witness.reason})
		return false
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_root = output_directory + "/saves"
	# 章节锁定另有测试；此窗口场景用独立第一章完成档作前置，不接触用户进度。
	var completed = load("res://scripts/core/plant_state.gd").create()
	completed.won = true
	var first_save = load("res://scripts/core/save_service.gd").new(game.save_root + "/chapter1", "apartment")
	if not first_save.save(completed).ok:
		_fail("无法建立独立章节前置", {})
		return false
	game.set_process(false)
	root.add_child(game)
	game.start_new_game("balcony")
	if game.service.env.level_id != "balcony":
		_fail("章节入口没有载入阳台", {})
		return false
	var driver = load("res://tests/test_game.gd").new()
	for action in witness.actions:
		if action.kind == "wait":
			if not _advance_ticks(game, roundi(action.seconds * 10.0)):
				return false
			continue
		game.select_tool(action.kind)
		var revision: int = game.service.state.revision
		if action.kind in ["root", "vine"]:
			var origin: Vector2 = game.service.state.nodes[action.target].pos
			driver._drag(game, game.world.to_screen(origin), game.world.to_screen(origin + action.direction))
		else:
			var position: Vector2
			if action.kind == "leaf":
				position = game.service.state.nodes[action.target].pos
			else:
				var edge: Dictionary = game.service.state.edges[action.target]
				position = load("res://scripts/core/support_solver.gd").arc_midpoint(edge.points, edge.length)
			_click(game, game.world.to_screen(position))
			if game.service.state.revision == revision:
				_click(game, game.world.to_screen(position))
		if game.service.state.revision == revision or not game.service.state.nodes.has(action.node) or game.service.state.nodes[action.node].pos.distance_to(action.position) > 0.01:
			_fail("阳台鼠标回放与候选几何不一致", {"route": route, "action": action, "message": game.hud.message_label.text})
			return false
		for _i in range(7):
			game._process(0.1)
		await process_frame
	for _i in range(65):
		game._process(0.1)
	await process_frame
	await RenderingServer.frame_post_draw
	if not game.service.state.won or game.hud.modal == null:
		_fail("阳台窗口未显示通关卡", {"route": route})
		return false
	if not _capture(game, "ending.png"):
		return false
	game.resume_game()
	await process_frame
	await RenderingServer.frame_post_draw
	if not _capture(game, "whole-plant.png"):
		return false
	var energy: float = game.service.state.energy
	var edges: int = game.service.state.edges.size()
	game.return_to_title()
	game.continue_game("balcony")
	if not game.service.state.won or game.service.env.level_id != "balcony" or game.service.state.edges.size() != edges or not is_equal_approx(game.service.state.energy, energy):
		_fail("阳台通关后菜单续档不一致", {"route": route})
		return false
	var report: Dictionary = {"route": route, "won": true, "reloaded_won": game.service.state.won,
		"level_id": game.level_id, "edges": edges, "leaves": game.service.state.leaves.size(),
		"energy": energy, "demand": game.service.metrics().water.demand,
		"risk": game.service.metrics().support.max_risk, "actions": witness.actions.size()}
	var report_path: String = output_directory + "/report.json"
	if FileAccess.file_exists(report_path):
		_fail("证据路径已经存在", {})
		return false
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BALCONY_WINDOW ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	return true


func _advance_ticks(game, count: int) -> bool:
	var target: int = game.service.state.tick + count
	# 动画/记忆允许自然结束，不能把被暂停的帧冒充经济模拟时间。
	for _i in range(count + 200):
		if game.service.state.tick >= target or game.service.state.won:
			return true
		game._process(0.1)
	_fail("阳台等待被意外冻结", {"frozen": game.sim.frozen, "target": target, "tick": game.service.state.tick})
	return false

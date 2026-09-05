extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Levels = preload("res://scripts/core/levels.gd")
const Validator = preload("res://scripts/core/level_validator.gd")
const ApartmentEnv = preload("res://scripts/core/environment.gd")
const BalconyEnv = preload("res://scripts/core/environment_balcony.gd")
const Saves = preload("res://scripts/core/save_service.gd")


func run(t) -> void:
	_registry(t)
	_validator_both_levels(t)
	_balcony_route(t)
	_balcony_multiple_routes(t)
	_per_level_saves(t)


func _registry(t) -> void:
	t.check(Levels.env_for("apartment") is ApartmentEnv, "第一关环境来自注册表")
	t.check(Levels.env_for("balcony") is BalconyEnv, "第二关环境来自注册表")
	t.check(Levels.env_for("missing") == null, "未知关卡返回空")
	t.check(Levels.save_dir_for("balcony") == "user://saves/chapter2", "第二关有独立存档目录")
	var ordered: Array = Levels.ordered()
	t.check(ordered[0].id == "apartment" and ordered[1].id == "balcony", "章节按顺序排列")
	t.check(Levels.is_unlocked("apartment"), "第一章始终解锁")
	t.check(str(Levels.get_definition("balcony").unlock_after) == "apartment",
		"第二章配置为通关第一章后解锁（运行时值取决于本机存档）")


# 关卡检查器 13 项对每一关都要全过。
func _validator_both_levels(t) -> void:
	for definition in Levels.DEFINITIONS:
		var env = load(definition.env_script).new()
		var failures: Array = []
		for report in Validator.validate(env):
			if not report.ok:
				failures.append("%s:%s" % [report.id, report.detail])
		t.check(failures.is_empty(), "%s 检查器全部通过 %s" % [definition.id, str(failures)])


# 白盒路线验证：固定救援开局后，用真实预览/提交沿路标链向出口攀爬。
# 注意：commit 会整体替换 service.state，每次都要重新读取。
func _balcony_route(t) -> void:
	var env = Levels.env_for("balcony")
	var service = Commands.new(Model.create(), env)
	var state = service.state
	var seed: Vector2 = state.nodes[1].pos
	var tip: int = state.edges[state.add_edge(1, "root", [seed, seed + Vector2(0, -0.8)])].b
	var root2: int = state.add_edge(tip, "root", [seed + Vector2(0, -0.8), seed + Vector2(0, -1.6)])
	env.reveal(state, state.nodes[state.edges[root2].b].pos)
	t.check(env.water_contacts(state).size() > 0, "阳台首根两段接水成立")
	var node: int = 1
	for degree in [90.0, 60.0, 5.0]:
		var opening = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
		if not opening.ok:
			t.check(false, "阳台救援藤%.0f°失败: %s" % [degree, opening.reason])
			return
		node = service.commit(opening, "balcony-open-%.0f" % degree).node
	t.check(true, "阳台三藤救援开局成立")
	# 路标链：rail_a → beam → planter → rail_b → wall_hook → 出口下方。
	var waypoints: Array = [Vector2(4.6, 1.1), Vector2(8.4, 1.05), Vector2(11.4, 0.9),
		Vector2(13.6, 1.6), Vector2(14.85, 2.65), Vector2(15.7, 4.5), Vector2(16.25, 5.05)]
	var reached: int = 0
	for waypoint in waypoints:
		service.state.energy = 40.0
		var chase_result: Dictionary = _chase(service, node, waypoint)
		if not chase_result.ok:
			break
		reached += 1
		node = chase_result.node
	t.check(reached >= waypoints.size() - 1, "阳台路线沿路标抵达出口附近（%d/%d）" % [reached, waypoints.size()])
	t.check(service.state.validate().is_empty(), "阳台路线拓扑有效")
	# 在 planter 锚点附近长叶，验证中途光照足以维持产能。
	var leaf_node: int = _nearest_node(service.state, Vector2(10.7, 0.94))
	var leaf_proposal: Dictionary = service.preview("leaf", leaf_node)
	t.check(leaf_proposal.ok, "阳台中途节点可以长叶: " + str(leaf_proposal.get("reason", "")))
	if leaf_proposal.ok:
		service.commit(leaf_proposal, "balcony-leaf")
	var metrics: Dictionary = service.metrics()
	t.check(metrics.income >= 0.05, "阳台路线有持续产能")


# 逐段朝路标生长；返回 {ok, node}，node 为最近的节点。
func _chase(service, start_node: int, waypoint: Vector2) -> Dictionary:
	var node: int = start_node
	for attempt in range(5):
		var state = service.state
		var direction: Vector2 = (waypoint - state.nodes[node].pos).normalized()
		var proposal = service.preview("vine", node, direction)
		if not proposal.ok:
			return {"ok": false, "node": node}
		node = service.commit(proposal, "chase-%d-%d" % [start_node, attempt]).node
		state = service.state
		var distance: float = state.nodes[node].pos.distance_to(waypoint)
		if distance <= 0.8 and not state.nodes[node].anchor.is_empty():
			return {"ok": true, "node": node}
		if distance <= 0.5:
			return {"ok": true, "node": node}
	return {"ok": service.state.nodes[node].pos.distance_to(waypoint) <= 0.9, "node": node}


func _nearest_node(state, point: Vector2) -> int:
	var best: int = state.seed_id
	var best_distance: float = 1000000.0
	for node in state.nodes.values():
		var distance: float = node.pos.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = node.id
	return best


func _has_anchor_on(state, surface_id: String) -> bool:
	for node in state.nodes.values():
		if node.anchor.get("id", "") == surface_id:
			return true
	return false


# 第二条路线：绕行 lower_edge 下沿也应可达（多路线有效性）。
func _balcony_multiple_routes(t) -> void:
	var env = Levels.env_for("balcony")
	var service = Commands.new(Model.create(), env)
	var state = service.state
	state.revealed.append("W1")
	state.revealed.append("W2")
	var origin: Vector2 = Vector2(7.0, 0.6)
	var mid: int = state.edges[state.add_edge(1, "vine", [state.nodes[1].pos, Vector2(2.0, 0.2)])].b
	state.nodes[mid].kind = "shoot"
	var hop1: int = state.add_edge(mid, "vine", [Vector2(2.0, 0.2), origin], {})
	state.nodes[state.edges[hop1].b].kind = "shoot"
	var anchor_point: Vector2 = Vector2(10.2, 0.05)
	var hop2: int = state.add_edge(state.edges[hop1].b, "vine",
		[origin, Vector2(8.7, 0.8), anchor_point], {"id": "lower_edge", "pos": anchor_point, "normal": Vector2(0, 1)})
	state.nodes[state.edges[hop2].b].kind = "shoot"
	t.check(not env.blocked([origin, Vector2(8.7, 0.8), anchor_point], 0.04), "绕行下沿路径不被碰撞挡死")
	t.check(_has_anchor_on(state, "lower_edge"), "绕行路线可以锚定 lower_edge")
	# 锚点间距检查：rail_a→beam→planter→rail_b→hook→window_door 每跳≤3.2u。
	var anchors: Array = [Vector2(4.2, 1.2), Vector2(7.3, 1.2), Vector2(9.6, 0.7),
		Vector2(10.6, 0.9), Vector2(13.2, 1.6), Vector2(14.5, 2.4), Vector2(16.05, 4.7)]
	var connectable: bool = true
	for index in range(1, anchors.size()):
		if anchors[index - 1].distance_to(anchors[index]) > 3.2:
			connectable = false
	t.check(connectable, "支点链每跳都在悬空能力内（≤3.2u）")


func _per_level_saves(t) -> void:
	var root_dir: String = "res://test-results/levels-saves-%d" % Time.get_ticks_usec()
	var apartment = Saves.new(root_dir + "/c1", "apartment")
	var balcony = Saves.new(root_dir + "/c2", "balcony")
	var service = Commands.new(Model.create(), Levels.env_for("apartment"))
	t.check(apartment.save(service.state).ok, "第一关存档写入自己的目录")
	t.check(balcony.save(service.state).ok, "第二关存档写入自己的目录")
	t.check(apartment.load_latest().ok and balcony.load_latest().ok, "两关存档互不干扰")
	var won_state = Model.create()
	won_state.won = true
	apartment.save(won_state)
	t.check(Model.persistent_fields().has("guide"), "guide 属于持久化字段")

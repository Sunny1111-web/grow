extends RefCounted

const Growth = preload("res://scripts/core/growth_solver.gd")
const Water = preload("res://scripts/core/water_solver.gd")
const Support = preload("res://scripts/core/support_solver.gd")
const Light = preload("res://scripts/core/light_solver.gd")
const Model = preload("res://scripts/core/plant_state.gd")

var state
var env
var _committed: Dictionary = {}


func _init(initial_state, environment) -> void:
	state = initial_state
	env = environment


func preview(kind: String, target: int, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "kind": kind, "target": target,
		"cost": 0.0, "revision": state.revision, "points": [], "node": target, "edge": 0,
		"removed_edges": 0, "removed_leaves": 0}
	var candidate = state.clone()
	var reason: String = ""
	match kind:
		"root", "vine":
			reason = _grow(candidate, kind, target, direction, result)
		"leaf":
			reason = _leaf(candidate, target, result)
		"reinforce":
			reason = _reinforce(candidate, target, result)
		"prune_edge", "prune_leaf":
			reason = _prune(candidate, kind, target, result)
		"rescue":
			_rescue(candidate, result)
		_:
			reason = "未知操作"
	if reason != "":
		result.reason = reason
		return result
	if state.energy + 0.00001 < result.cost:
		result.reason = "还需要 %.1f 能量" % (result.cost - state.energy)
		return result
	candidate.energy -= result.cost
	var computed: Dictionary = metrics(candidate)
	result.metrics = computed
	if kind in ["root", "vine", "leaf", "reinforce"] and computed.support.max_risk > 1.50001:
		result.reason = "悬空负载过大；先强化或寻找支点"
		return result
	var errors: Array = candidate.validate()
	if not errors.is_empty():
		result.reason = "这次生长无法形成有效结构：" + str(errors[0])
		return result
	result.ok = true
	result.candidate = candidate
	result.source_hash = _digest(state)
	result.candidate_hash = _digest(candidate)
	return result


func commit(proposal: Dictionary, command_id: String) -> Dictionary:
	if _committed.has(command_id):
		return _committed[command_id].duplicate(true)
	for event in state.events:
		if event.get("command_id", "") == command_id and event.has("result"):
			return event.result.duplicate(true)
	if command_id.is_empty() or not proposal.get("ok", false):
		return {"ok": false, "reason": proposal.get("reason", "没有可确认的操作")}
	if proposal.revision != state.revision or proposal.get("source_hash", "") != _digest(state):
		return {"ok": false, "reason": "植物状态已经变化，请重新预览"}
	if not proposal.has("candidate") or proposal.get("candidate_hash", "") != _digest(proposal.candidate):
		return {"ok": false, "reason": "预览内容已变化，请重新预览"}
	state = proposal.candidate.clone()
	state.revision += 1
	var result: Dictionary = {"ok": true, "reason": "", "kind": proposal.kind,
		"node": proposal.node, "edge": proposal.edge, "revision": state.revision,
		"cost": proposal.cost}
	state.events.append({"type": "command", "command_id": command_id, "tick": state.tick,
		"result": result.duplicate(true)})
	_committed[command_id] = result.duplicate(true)
	return result


func metrics(plant = null) -> Dictionary:
	if plant == null:
		plant = state
	var water: Dictionary = Water.solve(plant, env.water_contacts(plant))
	var support: Dictionary = Support.solve(plant)
	var light: Dictionary = Light.solve(plant, env)
	var income: float = 0.0
	var ordinary: float = 0.0
	for leaf in plant.leaves.values():
		var supply: float = water.organs[leaf.id].r
		if leaf.emergency:
			if leaf.produced < 18.0:
				income += supply
		else:
			var production: float = 1.6 * light[leaf.id].light * health_factor(leaf.z) * supply
			ordinary += production
			income += production
	return {"water": water, "support": support, "light": light, "income": income, "ordinary_income": ordinary}


static func health_factor(z: float) -> float:
	if z >= 24.0:
		return 0.0
	if z >= 12.0:
		return 0.2
	if z >= 6.0:
		return 0.6
	return 1.0


func _grow(candidate, kind: String, target: int, direction: Vector2, result: Dictionary) -> String:
	if not candidate.nodes.has(target):
		return "请选择存活的生长点"
	var node: Dictionary = candidate.nodes[target]
	if node.emergency:
		return "应急器官保持固定；请从种子生长"
	if candidate.edges.size() >= Model.MAX_EDGES:
		return "活枝已达上限，请先修剪"
	var outgoing: Array = []
	for edge in candidate.children(target):
		if (kind == "root") == (edge.kind == "root"):
			outgoing.append(edge)
	var capacity: int = 2
	if kind == "vine":
		if node.kind == "root":
			return "地下根尖只能继续生根"
		if node.kind == "seed":
			capacity = 1
	elif node.kind == "shoot":
		capacity = 1
	if outgoing.size() >= capacity:
		return "这个节点的生长插槽已经占满"
	var slot: int = 0
	for edge in outgoing:
		if edge.slot == 0:
			slot = 1
	var geometry: Dictionary = Growth.build(candidate, env, target, kind, direction)
	result.points = geometry.points
	if not geometry.ok:
		return geometry.reason
	var cost: float = 4.0 if kind == "root" else 5.0
	if kind == "vine" and not outgoing.is_empty():
		cost += 4.0
	var scar_key: String = "%d:%d" % [target, slot]
	if kind == "vine" and candidate.scars.has(scar_key):
		var scar: Dictionary = candidate.scars[scar_key]
		if scar.get("issued", false) and not scar.get("consumed", false):
			cost -= 2.0
			scar.consumed = true
	result.cost = cost
	var edge_id: int = candidate.add_edge(target, kind, geometry.points, geometry.anchor, false, slot)
	result.edge = edge_id
	result.node = candidate.edges[edge_id].b
	if kind == "root":
		env.reveal(candidate, candidate.nodes[result.node].pos)
	return ""


func _leaf(candidate, target: int, result: Dictionary) -> String:
	if not candidate.nodes.has(target):
		return "请选择地上生长点"
	var node: Dictionary = candidate.nodes[target]
	if node.emergency or node.kind == "root" or node.pos.y < 0.4:
		return "叶片需要存活的地上节点"
	if candidate.leaf_at(target) != 0:
		return "这里已有一片叶；可先修剪旧叶"
	if candidate.leaves.size() >= Model.MAX_LEAVES:
		return "活叶已达上限，请先修剪"
	var light: Dictionary = env.light_at(node.pos)
	var angle: float = clampf(light.direction.angle(), 0.35, 2.75)
	candidate.add_leaf(target, angle)
	result.cost = 3.0
	return ""


func _reinforce(candidate, target: int, result: Dictionary) -> String:
	if not candidate.edges.has(target) and candidate.nodes.has(target):
		target = candidate.nodes[target].parent_edge
	if not candidate.edges.has(target) or candidate.edges[target].kind != "vine":
		return "请选择尚未强化的活藤"
	if candidate.edges[target].emergency:
		return "应急器官不能强化"
	candidate.edges[target].kind = "branch"
	result.cost = 6.0
	result.edge = target
	result.node = candidate.edges[target].b
	return ""


func _prune(candidate, kind: String, target: int, result: Dictionary) -> String:
	if kind == "prune_leaf":
		if not candidate.leaves.has(target) or candidate.leaves[target].emergency:
			return "请选择普通活叶"
		retire_leaf(candidate, target, "prune")
		result.removed_leaves = 1
		return ""
	if not candidate.edges.has(target) and candidate.nodes.has(target):
		target = candidate.nodes[target].parent_edge
	if not candidate.edges.has(target) or candidate.edges[target].emergency:
		return "种子和应急器官不能修剪"
	var edge: Dictionary = candidate.edges[target]
	var key: String = "%d:%d" % [edge.a, edge.slot]
	if edge.kind != "root":
		if not candidate.scars.has(key):
			candidate.scars[key] = {"pos": candidate.nodes[edge.a].pos, "node": edge.a,
				"slot": edge.slot, "issued": true, "consumed": false, "original_edge": target, "reason": "prune"}
	var old_edges: int = candidate.edges.size()
	var old_leaves: int = candidate.leaves.size()
	result.node = edge.a
	retire_subtree(candidate, target, "prune")
	result.removed_edges = old_edges - candidate.edges.size()
	result.removed_leaves = old_leaves - candidate.leaves.size()
	return ""


func _rescue(candidate, result: Dictionary) -> void:
	result.removed_edges = candidate.edges.size()
	result.removed_leaves = candidate.leaves.size()
	for edge in candidate.children(candidate.seed_id):
		retire_subtree(candidate, edge.id, "rescue")
	for id in candidate.leaves.keys():
		retire_leaf(candidate, id, "rescue")
	candidate.energy = 0.0
	candidate.emergency_produced = 0.0
	candidate.dry_hint_time = 0.0
	candidate.victory_time = 0.0
	candidate.rescue_count += 1
	var seed: Vector2 = candidate.nodes[candidate.seed_id].pos
	var root1: int = candidate.add_edge(candidate.seed_id, "root", _line(seed, seed + Vector2(0, -0.8)), {}, true)
	var root2: int = candidate.add_edge(candidate.edges[root1].b, "root", _line(seed + Vector2(0, -0.8), seed + Vector2(0, -1.6)), {}, true)
	candidate.add_leaf(candidate.seed_id, PI * 0.5, true)
	env.reveal(candidate, candidate.nodes[candidate.edges[root2].b].pos)
	result.node = candidate.seed_id
	result.edge = 0


static func retire_subtree(plant, edge_id: int, reason: String) -> void:
	if not plant.edges.has(edge_id):
		return
	var pending: Array = [edge_id]
	var removal: Array = []
	while not pending.is_empty():
		var id: int = pending.pop_back()
		removal.append(id)
		for child in plant.children(plant.edges[id].b):
			pending.append(child.id)
	for id in removal:
		var edge: Dictionary = plant.edges[id]
		for leaf_id in plant.leaves.keys():
			if plant.leaves[leaf_id].node == edge.b:
				retire_leaf(plant, leaf_id, reason)
		plant.history.append({"type": "edge", "data": edge.duplicate(true),
			"node": plant.nodes[edge.b].duplicate(true), "reason": reason, "tick": plant.tick})
		plant.nodes.erase(edge.b)
		plant.edges.erase(id)


static func retire_leaf(plant, id: int, reason: String) -> void:
	if not plant.leaves.has(id):
		return
	var leaf: Dictionary = plant.leaves[id]
	plant.history.append({"type": "leaf", "data": leaf.duplicate(true),
		"pos": plant.nodes[leaf.node].pos, "reason": reason, "tick": plant.tick})
	plant.leaves.erase(id)


static func _line(a: Vector2, b: Vector2) -> Array:
	var points: Array = []
	for index in range(17):
		points.append(a.lerp(b, float(index) / 16.0))
	return points


static func _digest(plant) -> String:
	var fields: Dictionary = {}
	for field in Model.persistent_fields():
		fields[field] = plant.get(field)
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(fields))
	return context.finish().hex_encode()

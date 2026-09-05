extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const Service = preload("res://scripts/core/command_service.gd")


func run(t) -> void:
	_repeated_rescue_route(t)
	_full_capacity_rescue(t)
	_scar_persistence(t)
	_random_command_topology(t)
	_cap_feedback(t)


# 多次退守后固定18E恢复路线每次都必须成立；救援形态固定，不累计器官。
# 注意：commit会用candidate.clone()替换service.state，必须始终读service.state。
func _repeated_rescue_route(t) -> void:
	var service = Service.new(Model.create(), Level.new())
	for round in range(5):
		var rescue = service.preview("rescue", 1)
		t.check(service.commit(rescue, "round%d-rescue" % round).ok, "第%d次退守提交" % round)
		t.check(service.state.edges.size() == 2 and service.state.leaves.size() == 1,
			"第%d次退守后固定2根1叶" % round)
		service.state.energy = 18.0
		var node: int = service.state.seed_id
		var failure: String = ""
		for degree in [90.0, 60.0, 5.0]:
			var proposal = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
			if not proposal.ok:
				failure = "藤%.0f°预览: %s" % [degree, proposal.reason]
			elif not service.commit(proposal, "round%d-vine%.0f" % [round, degree]).ok:
				failure = "藤%.0f°提交失败" % degree
			node = proposal.get("node", node)
		if failure == "":
			var leaf = service.preview("leaf", node)
			if not leaf.ok:
				failure = "叶预览: " + leaf.reason
			elif not service.commit(leaf, "round%d-leaf" % round).ok:
				failure = "叶提交失败"
		t.check(failure == "", "第%d次退守后18E路线3藤1叶成立: %s" % [round, failure])
		t.check(service.metrics().income > 0.05, "第%d次恢复后产能为正" % round)
		t.check(service.state.validate().is_empty(), "第%d次恢复拓扑有效" % round)
	t.check(service.state.rescue_count == 5, "退守计数累计5次")


# 400边100叶满上限退守清空全部活体并恢复固定器官。
func _full_capacity_rescue(t) -> void:
	var state = Model.create()
	var seed: Vector2 = state.nodes[1].pos
	var node: int = state.edges[state.add_edge(1, "root", [seed, seed + Vector2(0, -0.8)])].b
	state.add_edge(node, "root", [seed + Vector2(0, -0.8), seed + Vector2(0, -1.6)])
	var tip: int = 1
	for index in range(398):
		var origin: Vector2 = state.nodes[tip].pos
		tip = state.edges[state.add_edge(tip, "vine", [origin, origin + Vector2(0.01, 0.01)],
			{"id": "perf"})].b
		if index % 4 == 0:
			state.add_leaf(tip)
	t.check(state.edges.size() == 400 and state.leaves.size() == 100, "压力株为400边100叶")
	var service = Service.new(state, Level.new())
	var rescue = service.preview("rescue", 1)
	t.check(rescue.ok and rescue.removed_edges == 400 and rescue.removed_leaves == 100,
		"满上限退守预告全部移除")
	t.check(service.commit(rescue, "cap-rescue").ok, "满上限退守提交")
	t.check(service.state.edges.size() == 2 and service.state.leaves.size() == 1, "满上限退守恢复固定器官")
	t.check(service.state.history.size() == 500, "400边100叶全部进入历史")
	t.check(service.state.rescue_count == 1, "退守计数为1")
	t.check(service.state.validate().is_empty(), "满上限退守后拓扑有效")
	t.check(service.commit(service.preview("rescue", 1), "cap-rescue-2").ok
		and service.state.edges.size() == 2 and service.state.leaves.size() == 1, "再次退守不累计器官")


# 修剪产生的同槽权益随不可变世代存读保留，再生仍享受一次减免。
func _scar_persistence(t) -> void:
	var directory: String = "res://test-results/scar-saves-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var saves = load("res://scripts/core/save_service.gd").new(directory)
	var state = Model.create(Vector2(3.5, 1.5))
	var env = Level.new()
	env.obstacles = []
	var edge: int = state.add_edge(1, "vine", [Vector2(3.5, 1.5), Vector2(4.5, 1.5)], {"id": "chair_seat"})
	var node: int = state.edges[edge].b
	var service = Service.new(state, env)
	var first = service.preview("vine", node, Vector2(1, 0))
	var outgoing: int = service.commit(first, "s1").edge
	service.commit(service.preview("vine", node, Vector2(0, 1)), "s2")
	service.commit(service.preview("prune_edge", outgoing), "s3")
	t.check(not service.state.scars.is_empty(), "修剪产生伤痕权益")
	var saved: Dictionary = saves.save(service.state)
	t.check(saved.ok, "伤痕世代保存: " + saved.reason)
	if not saved.ok:
		return
	var loaded: Dictionary = saves.load_latest()
	t.check(loaded.ok, "伤痕世代加载: " + loaded.reason)
	if not loaded.ok:
		return
	var restored = Service.new(loaded.state, Level.new())
	t.check(restored.state.scars.size() == service.state.scars.size(), "伤痕数量存读一致")
	var regrow = restored.preview("vine", node, Vector2.RIGHT)
	t.check(regrow.ok and absf(regrow.cost - 7.0) < 0.0001,
		"同槽权益存读后再生仍为7E: ok=%s cost=%.2f %s" % [regrow.ok, regrow.cost, regrow.reason])
	t.check(restored.commit(regrow, "s4").ok, "权益再生提交")
	var again = restored.preview("vine", node, Vector2.RIGHT)
	t.check(not again.ok or absf(again.cost - 7.0) > 0.0001, "权益只用一次")


# 固定种子1000步随机命令/修剪；预览通过则提交必须成功，拓扑始终有效。
func _random_command_topology(t) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 20260905
	var service = Service.new(Model.create(), Level.new())
	var kinds: Array[String] = ["root", "vine", "leaf", "reinforce", "prune_edge", "prune_leaf"]
	var serial: int = 0
	var committed: int = 0
	for step in range(1000):
		if service.state.energy < 20.0:
			service.state.energy = 40.0
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var proposal: Dictionary
		match kind:
			"root", "vine":
				var nodes: Array = service.state.nodes.keys()
				var target: int = nodes[rng.randi_range(0, nodes.size() - 1)]
				proposal = service.preview(kind, target, Vector2.from_angle(rng.randf_range(-PI, PI)))
			"leaf":
				var nodes: Array = service.state.nodes.keys()
				proposal = service.preview("leaf", nodes[rng.randi_range(0, nodes.size() - 1)])
			"reinforce":
				if service.state.edges.is_empty():
					continue
				var ids: Array = service.state.edges.keys()
				proposal = service.preview("reinforce", ids[rng.randi_range(0, ids.size() - 1)])
			"prune_edge":
				if service.state.edges.is_empty():
					continue
				var ids: Array = service.state.edges.keys()
				proposal = service.preview("prune_edge", ids[rng.randi_range(0, ids.size() - 1)])
			_:
				if service.state.leaves.is_empty():
					continue
				var ids: Array = service.state.leaves.keys()
				proposal = service.preview("prune_leaf", ids[rng.randi_range(0, ids.size() - 1)])
		if not proposal.ok:
			continue
		serial += 1
		var result: Dictionary = service.commit(proposal, "random-%d" % serial)
		t.check(result.ok, "第%d步预览通过后提交成功: %s (%s)" % [step, kind, result.reason])
		if not result.ok:
			return
		committed += 1
		if step % 50 == 49:
			var errors: Array = service.state.validate()
			t.check(errors.is_empty(), "第%d步后拓扑有效: %s" % [step + 1, str(errors[0]) if not errors.is_empty() else ""])
			if not errors.is_empty():
				return
			t.check(service.state.edges.size() <= 400 and service.state.leaves.size() <= 100,
				"第%d步后器官不超上限" % (step + 1))
			t.check(service.state.energy >= 0.0 and service.state.energy <= 40.0,
				"第%d步后能量在区间内" % (step + 1))
	t.check(committed > 0, "随机序列产生真实提交(%d次)" % committed)
	print("RANDOM_TOPOLOGY steps=1000 committed=%d edges=%d leaves=%d" %
		[committed, service.state.edges.size(), service.state.leaves.size()])


# 上限提示与所有层级子树移除。
func _cap_feedback(t) -> void:
	var state = Model.create()
	var tip: int = 1
	var nodes: Array[int] = [1]
	for index in range(400):
		var origin: Vector2 = state.nodes[tip].pos
		tip = state.edges[state.add_edge(tip, "vine", [origin, origin + Vector2(0.01, 0.01)],
			{"id": "perf"})].b
		nodes.append(tip)
	for index in range(100):
		state.add_leaf(nodes[index * 4 + 1])
	var service = Service.new(state, Level.new())
	var root_preview = service.preview("root", 1, Vector2(0, -1))
	t.check(not root_preview.ok and root_preview.reason.contains("上限"), "400边后根提示上限")
	var vine_preview = service.preview("vine", tip, Vector2(0.01, 0.01))
	t.check(not vine_preview.ok and vine_preview.reason.contains("上限"), "400边后藤提示上限")
	# nodes[122]为地上(y≈0.42)且未占叶位的节点；上限提示优先于位置检查。
	var leaf_preview = service.preview("leaf", nodes[122])
	t.check(not leaf_preview.ok and leaf_preview.reason.contains("上限"), "100叶后叶提示上限")
	# 三层嵌套：剪中间层时下游两个层级全部移除。
	var tree = Model.create(Vector2(3.5, 1.5))
	var empty_env = Level.new()
	empty_env.obstacles = []
	var trunk: int = tree.edges[tree.add_edge(1, "vine", [Vector2(3.5, 1.5), Vector2(4.5, 1.5)], {"id": "chair_seat"})].b
	var middle: int = tree.add_edge(trunk, "vine", [Vector2(4.5, 1.5), Vector2(5.5, 1.5)])
	var branch_node: int = tree.edges[middle].b
	tree.add_edge(branch_node, "vine", [Vector2(5.5, 1.5), Vector2(6.5, 1.5)])
	tree.add_leaf(branch_node)
	var layered = Service.new(tree, empty_env)
	var prune = layered.preview("prune_edge", middle)
	t.check(prune.ok and prune.removed_edges == 2 and prune.removed_leaves == 1,
		"剪中间层移除全部下游层级")
	t.check(layered.commit(prune, "layer-cut").ok, "层级修剪提交")
	t.check(layered.state.edges.size() == 1 and layered.state.leaves.is_empty(), "层级修剪后仅留主干")
	t.check(layered.state.history.size() == 3, "两条边与一片叶全部进入历史")

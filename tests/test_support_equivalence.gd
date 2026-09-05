extends RefCounted

const State = preload("res://scripts/core/plant_state.gd")
const Support = preload("res://scripts/core/support_solver.gd")
const Reference = preload("res://tests/fixtures/reference_support.gd")
const EPS: float = 0.000001
const SAMPLES: int = 24
var max_difference: Dictionary = {"distance": 0.0, "moment": 0.0, "risk": 0.0}


func run(t) -> void:
	_small_differential(t)
	_anchor_and_root_boundaries(t)
	_folded_chain_and_ties(t)
	print("SUPPORT_EQUIVALENCE max_distance_delta=%.12f max_moment_delta=%.12f max_risk_delta=%.12f" % [max_difference.distance, max_difference.moment, max_difference.risk])
	_worst_chain_performance(t)


func _compare(t, state, label: String) -> void:
	var before = state.clone()
	var expected: Dictionary = Reference.solve(state)
	var actual: Dictionary = Support.solve(state)
	t.check(actual.organs.keys() == expected.organs.keys(), label + " 输出器官集合及顺序相同")
	t.near(actual.max_risk, expected.max_risk, EPS, label + " 最大风险等价")
	for id in expected.organs:
		for field in ["distance", "moment", "risk"]:
			max_difference[field] = maxf(max_difference[field], absf(actual.organs[id][field] - expected.organs[id][field]))
			t.near(actual.organs[id][field], expected.organs[id][field], EPS,
				"%s edge=%d %s" % [label, id, field])
	t.check(state.nodes == before.nodes and state.edges == before.edges and state.leaves == before.leaves,
		label + " 纯求解不修改事实状态")


func _small_differential(t) -> void:
	for fixture in range(48):
		var rng = RandomNumberGenerator.new()
		rng.seed = 712367 + fixture * 101
		var state = State.create(Vector2(-0.125, 0.25))
		var nodes: Array[int] = [1]
		for index in range(48):
			var parent: int = nodes[rng.randi_range(0, nodes.size() - 1)]
			# Every fourth fixture also exercises a deeper winding chain.
			if fixture % 4 == 0 and index % 9 != 0:
				parent = nodes.back()
			var origin: Vector2 = state.nodes[parent].pos
			var angle: float = rng.randf_range(-PI, PI)
			var direction: Vector2 = Vector2.from_angle(angle)
			var endpoint: Vector2 = origin + direction * rng.randf_range(0.15, 0.7)
			var bend: Vector2 = origin.lerp(endpoint, rng.randf_range(0.15, 0.8)) + direction.orthogonal() * rng.randf_range(-0.35, 0.35)
			var kind: String = "branch" if index % 3 == 0 else "vine"
			if index % 13 == 0:
				kind = "root"
			var anchor: Dictionary = {}
			if rng.randf() < 0.15:
				anchor = {"id": "fixture", "pos": endpoint, "normal": Vector2.UP}
			var edge: int = state.add_edge(parent, kind, [origin, bend, endpoint], anchor)
			var node: int = state.edges[edge].b
			nodes.append(node)
			if index % 3 == 0:
				state.add_leaf(node, angle, index % 15 == 0)
		state.add_leaf(1)
		state.add_leaf(1, 0.0, true)
		_compare(t, state, "固定随机种子%d" % rng.seed)


func _anchor_and_root_boundaries(t) -> void:
	var state = State.create(Vector2(12, -8))
	var node: int = 1
	for index in range(32):
		var origin: Vector2 = state.nodes[node].pos
		var endpoint: Vector2 = origin + Vector2(-0.375 if index % 2 == 0 else 0.25, -0.25 if index % 3 == 0 else 0.125)
		var anchor: Dictionary = {"id": "anchor"} if index in [3, 4, 10, 30] else {}
		var kind: String = "root" if index in [6, 18] else ("branch" if index % 2 == 0 else "vine")
		var edge: int = state.add_edge(node, kind, [origin, origin + Vector2(0.25, 0.375), endpoint], anchor)
		node = state.edges[edge].b
		state.add_leaf(node)
		state.add_leaf(node, 0.0, true)
	_compare(t, state, "多锚点/根截断/折返曲线/上下左右负载")
	_compare(t, State.create(), "空株")


func _folded_chain_and_ties(t) -> void:
	var state = State.create(Vector2.ZERO)
	var node: int = 1
	for index in range(64):
		var origin: Vector2 = state.nodes[node].pos
		# Binary-exact coordinates isolate signed absolute moments from rounding;
		# zero components exercise loads exactly on a queried x/y coordinate.
		var offset: Vector2 = [Vector2(0.5, 0), Vector2(-0.75, 0.125), Vector2(0, -0.25), Vector2(0.25, 0.125)][index % 4]
		var edge: int = state.add_edge(node, "branch" if index % 5 == 0 else "vine",
			[origin, origin + Vector2(0.125, -0.125), origin + offset])
		node = state.edges[edge].b
		if index % 4 == 0:
			state.add_leaf(node)
	_compare(t, state, "64边无锚折返链及坐标相等")
	for edge in state.edges.values():
		state.nodes[edge.b].anchor = {"id": "all-anchored"}
	_compare(t, state, "全部远端锚定无悬空负载")


func _worst_chain_performance(t) -> void:
	var state = State.create(Vector2.ZERO)
	state.add_edge(1, "root", [Vector2.ZERO, Vector2(0, -0.8)])
	var node: int = 1
	for index in range(399):
		var origin: Vector2 = state.nodes[node].pos
		var edge: int = state.add_edge(node, "vine", [origin, origin + Vector2(0.01, 0.01)])
		node = state.edges[edge].b
		if index % 4 == 0:
			state.add_leaf(node)
	for _warmup in range(3):
		Support.solve(state)
	var samples: Array[int] = []
	var actual: Dictionary = {}
	for _sample in range(SAMPLES):
		var begin: int = Time.get_ticks_usec()
		actual = Support.solve(state)
		samples.append(Time.get_ticks_usec() - begin)
	samples.sort()
	var p95: int = samples[ceili(SAMPLES * 0.95) - 1]
	t.check(state.edges.size() == 400 and state.leaves.size() == 100, "性能样本覆盖400边100叶")
	t.check(actual.organs.size() == 399, "性能求解覆盖所有399地上边")
	t.check(p95 < 10000, "支撑长链p95必须低于10ms；actual=%dus" % p95)
	print("SUPPORT_PERFORMANCE samples=%d edges=400 leaves=100 min_us=%d median_us=%d p95_us=%d max_us=%d" %
		[SAMPLES, samples[0], samples[SAMPLES / 2], p95, samples[-1]])

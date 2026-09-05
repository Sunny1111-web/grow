extends RefCounted

const EPS = 0.0001
var water
var support
var light

class FixtureState:
	extends RefCounted
	var nodes: Dictionary = {1: {"id": 1, "pos": Vector2.ZERO, "parent_edge": 0, "kind": "seed", "anchor": {}, "emergency": false}}
	var edges: Dictionary = {}
	var leaves: Dictionary = {}
	var history: Array = []
	var seed_id: int = 1
	var next_id: int = 2
	func add_edge(a: int, kind: String, points: Array, anchor: Dictionary = {}, emergency: bool = false, slot: int = 0) -> int:
		var edge_id: int = next_id
		var node_id: int = next_id + 1
		next_id += 2
		var length: float = 0.0
		for i in range(1, points.size()):
			length += points[i - 1].distance_to(points[i])
		edges[edge_id] = {"id": edge_id, "a": a, "b": node_id, "kind": kind, "length": length, "points": points, "z": 0.0, "bend": 0.0, "emergency": emergency, "slot": slot}
		nodes[node_id] = {"id": node_id, "pos": points[-1], "parent_edge": edge_id, "kind": "root" if kind == "root" else "shoot", "anchor": anchor, "emergency": emergency}
		return edge_id
	func add_leaf(node: int, angle: float = 0.0, emergency: bool = false) -> int:
		var leaf_id: int = next_id
		next_id += 1
		leaves[leaf_id] = {"id": leaf_id, "node": node, "angle": angle, "z": 0.0, "emergency": emergency, "produced": 0.0}
		return leaf_id
	func children(node: int, kind: String = "") -> Array:
		var result: Array = []
		for edge in edges.values():
			if edge.a == node and (kind == "" or edge.kind == kind):
				result.append(edge)
		result.sort_custom(func(a, b): return a.id < b.id)
		return result

class LightEnvironment:
	extends RefCounted
	var intensity: float = 1.0
	var direction: Vector2 = Vector2(0, 1)
	var wall: bool = false
	var all_wall: bool = false
	var distance: float = 64.0
	var wall_y: float = 1000.0
	var queries: Array = []
	func light_at(_point: Vector2) -> Dictionary:
		return {"intensity": intensity, "direction": direction, "id": "fixture", "distance": distance}
	func ray_blocked(from: Vector2, to: Vector2) -> bool:
		queries.append([from, to])
		return all_wall or (wall and from.x > 0.05) or (from.y < wall_y and to.y >= wall_y)

func run(t) -> void:
	var paths: Array = ["res://scripts/core/water_solver.gd", "res://scripts/core/support_solver.gd", "res://scripts/core/light_solver.gd"]
	var present: bool = true
	for path in paths:
		t.check(FileAccess.file_exists(path), "求解器存在: " + path)
		present = present and FileAccess.file_exists(path)
	if not present:
		return
	water = load(paths[0])
	support = load(paths[1])
	light = load(paths[2])
	if water == null or support == null or light == null:
		t.check(false, "求解器脚本可加载")
		return
	_water_hand_calculation(t)
	_water_connections_and_extremes(t)
	_support_hand_calculation(t)
	_support_curves_and_extremes(t)
	_light_samples_and_layers(t)
	_light_extremes(t)
	_performance(t)

func _edge(state, a: int, kind: String, delta: Vector2, anchor: Dictionary = {}) -> int:
	return state.add_edge(a, kind, [state.nodes[a].pos, state.nodes[a].pos + delta], anchor)

func _access(node: int, q: float = 12.0, id: String = "W1") -> Dictionary:
	return {"node": node, "access_id": id, "aquifer_id": "shared", "q": q}

func _water_hand_calculation(t) -> void:
	var state = FixtureState.new()
	var r1: int = _edge(state, 1, "root", Vector2(0, -0.8))
	var r2: int = _edge(state, state.edges[r1].b, "root", Vector2(0, -0.8))
	var branch: int = _edge(state, 1, "branch", Vector2(1, 0))
	var split: int = state.edges[branch].b
	var seed_leaf: int = state.add_leaf(1)
	var split_leaf: int = state.add_leaf(split)
	var far: Array = []
	var second: Array = []
	var vines: Array = []
	for side in [-1.0, 1.0]:
		var node: int = split
		for depth in range(3):
			var vine: int = _edge(state, node, "vine", Vector2(side, 0))
			vines.append(vine)
			node = state.edges[vine].b
			var leaf: int = state.add_leaf(node)
			if depth == 2:
				far.append(leaf)
			if depth == 1:
				second.append(leaf)
	var sources: Array = [_access(state.edges[r2].b)]
	var result = water.solve(state, sources)
	t.near(result.q, 12.0, EPS, "手算Q=12")
	t.near(result.demand, 13.5537, EPS, "手算源端总需水13.5537")
	t.near(result.spent, 12.0, EPS, "预算全部使用且守恒")
	t.near(result.organs[r2].resistance, 0.032, EPS, "近水根中点阻力")
	t.near(result.organs[r1].resistance, 0.096, EPS, "上行水到近种子根中点")
	t.near(result.organs[branch].resistance, 0.153, EPS, "强化枝中点阻力")
	t.near(result.organs[seed_leaf].resistance, 0.128, EPS, "根向父节点双向运输")
	t.near(result.organs[split_leaf].resistance, 0.328, EPS, "挂在分叉节点的叶加一次.15")
	for index in range(vines.size()):
		t.near(result.organs[vines[index]].resistance, 0.388 + (index % 3) * 0.12, EPS, "分叉后藤中点阻力")
	far.sort()
	t.near(result.organs[far[0]].r, 0.849451999, EPS, "并列远叶按永久ID先者r=.84945")
	t.near(result.organs[far[1]].r, 0.0, EPS, "第二远叶无水")
	var total_base: float = 0.0
	var conserved: float = 0.0
	for organ in result.organs.values():
		total_base += organ.base
		conserved += organ.delivered * (1.0 + organ.resistance)
	t.near(total_base, 9.3, EPS, "基础需水9.30")
	t.near(conserved, result.spent, EPS, "实得加运输损耗等于源端花费")
	state.history.append(state.leaves[far[1]].duplicate(true))
	state.leaves.erase(far[1])
	result = water.solve(state, sources)
	t.near(result.demand, 12.2033, EPS, "剪掉无水叶仍然欠水")
	t.near(result.organs[far[0]].r, 0.849451999, EPS, "一次小修剪不会凭空恢复远叶")
	state.history.append(state.leaves[second[0]].duplicate(true))
	state.leaves.erase(second[0])
	result = water.solve(state, sources)
	t.near(result.demand, 10.9489, EPS, "第二次修剪需求10.9489")
	for organ in result.organs.values():
		t.near(organ.r, 1.0, EPS, "修剪足够后所有器官足水")

func _water_connections_and_extremes(t) -> void:
	var state = FixtureState.new()
	var a: int = _edge(state, 1, "root", Vector2(0, -0.8))
	var b: int = _edge(state, state.edges[a].b, "root", Vector2(0, -0.8))
	var c: int = _edge(state, state.edges[a].b, "root", Vector2(0.8, 0))
	var leaf: int = state.add_leaf(1)
	var sources: Array = []
	for i in range(5):
		sources.append(_access(state.edges[b].b, 12.0, "W1_%d" % i))
	var result = water.solve(state, sources)
	t.near(result.q, 12.0, EPS, "同一W1重复接触5次不复制Q")
	t.near(result.organs[c].resistance, 0.096, EPS, "根分裂不收地上分叉损耗")
	sources.append(_access(state.edges[c].b, 20.0, "W2"))
	result = water.solve(state, sources)
	t.near(result.q, 20.0, EPS, "W1和W2同层取最大20")
	t.near(result.organs[c].resistance, 0.032, EPS, "中继根选择较近接点")
	result = water.solve(state, [_access(state.edges[b].b), _access(99999, 100.0, "stale")])
	t.near(result.q, 12.0, EPS, "失活接入点不能供水")
	result = water.solve(state, [])
	for organ in result.organs.values():
		t.near(organ.r, 0.0, EPS, "无水全部缺水")
		t.check(is_finite(organ.resistance) and is_finite(organ.demand), "无水输出保持有限数")
	var emergency: int = state.add_leaf(1, 0.0, true)
	result = water.solve(state, [_access(state.edges[b].b)])
	t.near(result.organs[emergency].base, 0.2, EPS, "应急子叶需水.2")
	state.leaves[emergency].produced = 18.0
	result = water.solve(state, [_access(state.edges[b].b)])
	t.near(result.organs[emergency].demand, 0.0, EPS, "应急子叶18E后停止维护")
	result = water.solve(state, [_access(state.edges[b].b, 0.01)])
	t.near(result.spent, 0.01, EPS, "极低Q不透支预算")
	t.near(result.organs[leaf].r, 0.0, EPS, "网络组织优先于普通叶")
	t.check(water.solve(FixtureState.new(), []).organs.is_empty(), "空株无器官")

func _support_hand_calculation(t) -> void:
	var state = FixtureState.new()
	var first: int = _edge(state, 1, "vine", Vector2(1, 0))
	var second: int = _edge(state, state.edges[first].b, "vine", Vector2(1, 0))
	var third: int = _edge(state, state.edges[second].b, "vine", Vector2(1, 0))
	state.add_leaf(state.edges[third].b)
	var result = support.solve(state)
	t.near(result.organs[first].distance, 3.0, EPS, "水平三藤悬空D=3")
	t.near(result.organs[first].moment, 1.975, EPS, "手算三藤一叶M=1.975")
	t.near(result.organs[first].risk, 1.975 / 1.2, EPS, "三藤末叶风险超过1.5")
	state.edges[first].kind = "branch"
	result = support.solve(state)
	t.near(result.organs[first].moment, 2.095, EPS, "强化重量上升后M=2.095")
	t.near(result.organs[first].risk, 0.75, EPS, "强化首枝风险=.75")
	t.near(result.organs[second].moment, 1.075, EPS, "第二藤弯矩1.075")
	t.near(result.organs[second].risk, 1.075 / 1.2, EPS, "第二藤风险约.896")
	state.nodes[state.edges[second].b].anchor = {"id": "wall", "pos": Vector2(2, 0), "normal": Vector2(0, 1)}
	result = support.solve(state)
	t.near(result.organs[first].distance, 1.0, EPS, "锚点截断祖先悬空长度")
	t.near(result.organs[first].moment, 0.27, EPS, "锚点隔离支承边及远端叶负载")
	t.near(result.organs[second].risk, 0.0, EPS, "远端锚定边由环境全支承")
	t.near(result.organs[third].moment, 0.425, EPS, "锚点之后重新计算悬空区")

func _support_curves_and_extremes(t) -> void:
	var state = FixtureState.new()
	var edge: int = state.add_edge(1, "vine", [Vector2.ZERO, Vector2(0, 1), Vector2(3, 1)])
	var result = support.solve(state)
	t.near(result.organs[edge].distance, 4.0, EPS, "悬空长度使用折线弧长")
	t.near(result.organs[edge].moment, 1.35, EPS, "重量位置取弧长中点(1,1)")
	var root: int = _edge(state, 1, "root", Vector2(100, -100))
	state.add_leaf(1, 0.0, true)
	var changed = support.solve(state)
	t.check(not changed.organs.has(root), "根不参与结构")
	t.near(changed.organs[edge].moment, result.organs[edge].moment, EPS, "应急叶由种子独立固定")
	var empty = support.solve(FixtureState.new())
	t.near(empty.max_risk, 0.0, EPS, "空株风险为零")
	t.check(empty.organs.is_empty(), "空株没有支承边输出")

func _leaf_center(state, center: Vector2, angle: float = 0.0, emergency: bool = false) -> int:
	var node: int = state.next_id
	state.next_id += 1
	state.nodes[node] = {"id": node, "pos": center - Vector2.from_angle(angle) * 0.16, "parent_edge": 0, "kind": "shoot", "anchor": {}, "emergency": emergency}
	return state.add_leaf(node, angle, emergency)

func _light_samples_and_layers(t) -> void:
	var state = FixtureState.new()
	var target: int = _leaf_center(state, Vector2.ZERO)
	var env = LightEnvironment.new()
	var result = light.solve(state, env)
	t.near(result[target].light, 1.0, EPS, "自身叶轮廓不挡自身三射线")
	t.check(env.queries.size() == 3, "每片普通叶恰好三个固定采样点")
	var sample_x: Array = []
	for query in env.queries:
		sample_x.append(query[0].x)
		t.check(query[1].is_finite(), "光射线端点是有限坐标")
	sample_x.sort()
	t.near(sample_x[0], -0.1, EPS, "叶长轴负侧样本")
	t.near(sample_x[1], 0.0, EPS, "叶心样本")
	t.near(sample_x[2], 0.1, EPS, "叶长轴正侧样本")
	_leaf_center(state, Vector2(0, 1))
	result = light.solve(state, env)
	t.near(result[target].transmission, 0.5, EPS, "同一叶进出两交点只衰减一次")
	_leaf_center(state, Vector2(0, 2))
	result = light.solve(state, env)
	t.near(result[target].light, 0.25, EPS, "两片不同叶产生两层.5")
	env.all_wall = true
	result = light.solve(state, env)
	t.near(result[target].light, 0.0, EPS, "建筑遮挡射线归零")
	state = FixtureState.new()
	target = _leaf_center(state, Vector2.ZERO)
	_leaf_center(state, Vector2(-0.14, 1), PI / 2.0)
	env = LightEnvironment.new()
	env.intensity = 0.6
	env.wall = true
	result = light.solve(state, env)
	t.near(result[target].transmission, 0.5, EPS, "三个样本透射1/.5/0平均.5")
	t.near(result[target].light, 0.3, EPS, "规格光照手算L=.6×.5=.3")

func _light_extremes(t) -> void:
	var state = FixtureState.new()
	var target: int = _leaf_center(state, Vector2.ZERO)
	var env = LightEnvironment.new()
	_leaf_center(state, Vector2(0, -1))
	var result = light.solve(state, env)
	t.near(result[target].light, 1.0, EPS, "叶背后轮廓不挡指向光源射线")
	env.distance = 2.0
	env.wall_y = 3.0
	result = light.solve(state, env)
	t.near(result[target].light, 1.0, EPS, "局部光源背后的墙不会遮挡反射光")
	env.intensity = 0.0
	result = light.solve(state, env)
	t.near(result[target].light, 0.0, EPS, "零强度不产光")
	var emergency: int = _leaf_center(state, Vector2(0, 2), 0.0, true)
	env.all_wall = true
	result = light.solve(state, env)
	t.near(result[emergency].light, 1.0, EPS, "应急子叶使用独立安全光")
	t.check(light.solve(FixtureState.new(), env).is_empty(), "空株无光输出")

func _performance(t) -> void:
	var state = FixtureState.new()
	var source: int = _edge(state, 1, "root", Vector2(0, -0.8))
	var node: int = 1
	for i in range(399):
		var edge: int = _edge(state, node, "vine", Vector2(0.01, 0.01))
		node = state.edges[edge].b
		if i % 4 == 0:
			state.add_leaf(node)
	var env = LightEnvironment.new()
	var begin: int = Time.get_ticks_usec()
	var water_result = water.solve(state, [_access(state.edges[source].b)])
	var water_us: int = Time.get_ticks_usec() - begin
	begin = Time.get_ticks_usec()
	var support_result = support.solve(state)
	var support_us: int = Time.get_ticks_usec() - begin
	begin = Time.get_ticks_usec()
	var light_result = light.solve(state, env)
	var light_us: int = Time.get_ticks_usec() - begin
	t.check(water_result.organs.size() == 500, "上限水求解覆盖400边100叶")
	t.check(support_result.organs.size() == 399, "上限结构求解覆盖399地上边")
	t.check(light_result.size() == 100, "上限光求解覆盖100叶")
	t.check(water_us + support_us + light_us < 2000000, "上限求解须在2秒内结束（冒烟门槛，不是p95性能验收）")
	print("SOLVERS_STRESS_US water=%d support=%d light=%d total=%d" % [water_us, support_us, light_us, water_us + support_us + light_us])

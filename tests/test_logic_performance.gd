extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Service = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")
const SAMPLES: int = 40
const LOGIC_BUDGET_US: int = 3000
const FULL_SOLVE_BUDGET_US: int = 8000
const CACHE_BUDGET_US: int = 500


func run(t) -> void:
	_steady_step(t)
	_full_solve(t)
	_cache_reuse(t)
	_preview_path(t)


# 400活边、100活叶且两根接入W1的压力株。链条按(0.01,0.01)延伸，
# 与test_solvers冒烟株同构，但经由真实服务与环境驱动。
func _stress_plant() -> Array:
	var service = Service.new(Model.create(), Level.new())
	# 供水充足避免干旱连锁修剪；压力测量针对求解成本，不针对死亡路径。
	service.env.waters[0].q = 400.0
	var state = service.state
	var seed: Vector2 = state.nodes[1].pos
	var node: int = state.edges[state.add_edge(1, "root", [seed, seed + Vector2(0, -0.8)])].b
	state.add_edge(node, "root", [seed + Vector2(0, -0.8), seed + Vector2(0, -1.6)])
	var tip: int = 1
	for index in range(398):
		var origin: Vector2 = state.nodes[tip].pos
		# 锚定避免悬空链在结构求解下逐级断裂；求解成本不受锚点分布影响。
		tip = state.edges[state.add_edge(tip, "vine", [origin, origin + Vector2(0.01, 0.01)],
			{"id": "perf"})].b
		if index % 4 == 0:
			state.add_leaf(tip)
	return [service, state]


func _steady_step(t) -> void:
	var built: Array = _stress_plant()
	var service = built[0]
	var state = built[1]
	t.check(state.edges.size() == 400 and state.leaves.size() == 100, "压力株为400边100叶")
	var sim = load("res://scripts/core/simulation.gd").new(service)
	for _warmup in range(10):
		sim.step(0.1)
	var samples: Array[int] = []
	for _sample in range(SAMPLES):
		var begin: int = Time.get_ticks_usec()
		sim.step(0.1)
		samples.append(Time.get_ticks_usec() - begin)
	samples.sort()
	var p95: int = samples[ceili(SAMPLES * 0.95) - 1]
	t.check(state.edges.size() == 400 and state.leaves.size() == 100, "稳态逻辑步不损失器官")
	t.check(p95 <= LOGIC_BUDGET_US, "稳态10Hz逻辑步p95≤3ms；actual=%dus median=%dus max=%dus" %
		[p95, samples[SAMPLES / 2], samples[-1]])
	print("LOGIC_STEP_PERFORMANCE samples=%d median_us=%d p95_us=%d max_us=%d" %
		[SAMPLES, samples[SAMPLES / 2], p95, samples[-1]])


func _full_solve(t) -> void:
	var built: Array = _stress_plant()
	var service = built[0]
	var state = built[1]
	# 先在等价株上预热脚本路径，再以微小拓扑变化强制逐次全量求解采样。
	# 与TDD「完整预览求解p95≤8ms」同一工作集；命令提交后首个逻辑步属于此类。
	var warm = Service.new(state.clone(), service.env)
	warm.metrics()
	var samples: Array[int] = []
	for _sample in range(24):
		var leaf: int = state.leaves.keys()[0]
		Service.retire_leaf(state, leaf, "perf")
		state.add_leaf(1)
		var begin: int = Time.get_ticks_usec()
		var metrics: Dictionary = service.metrics()
		samples.append(Time.get_ticks_usec() - begin)
		t.check(metrics.water.organs.size() == 500 and metrics.support.organs.size() == 398
			and metrics.light.size() == 100, "全量求解覆盖所有器官")
	samples.sort()
	var p95: int = samples[ceili(24 * 0.95) - 1]
	t.check(p95 <= FULL_SOLVE_BUDGET_US, "拓扑变化后的全量求解p95≤8ms；actual=%dus median=%dus" %
		[p95, samples[samples.size() / 2]])
	print("FULL_SOLVE_PERFORMANCE samples=24 median_us=%d p95_us=%d max_us=%d" %
		[samples[samples.size() / 2], p95, samples[-1]])


func _cache_reuse(t) -> void:
	var built: Array = _stress_plant()
	var service = built[0]
	var first: Dictionary = service.metrics()
	var begin: int = Time.get_ticks_usec()
	var second: Dictionary = service.metrics()
	var elapsed: int = Time.get_ticks_usec() - begin
	t.check(elapsed <= CACHE_BUDGET_US, "拓扑未变时重复求解命中缓存≤0.5ms；actual=%dus" % elapsed)
	t.check(second.water.q == first.water.q and second.support.max_risk == first.support.max_risk,
		"缓存返回相同的水量与结构风险")
	t.near(second.income, first.income, 0.0000001, "缓存返回相同产能")
	print("METRICS_CACHE_PERFORMANCE us=%d" % elapsed)


# 完整预览路径：clone→候选全量求解→validate→指纹。与 TDD
# 「完整预览 p95≤8ms」同一压力工作集；修正采样口径：在测试内对
# 真实 service.preview 采样（与编辑器 debug 同口径），不再依赖
# 导出包内的人工采集。压力株已满100叶上限，故用强化预览采样
# （覆盖 clone+全量求解+validate+指纹，与生长预览同路径）。
func _preview_path(t) -> void:
	var built: Array = _stress_plant()
	var service = built[0]
	var state = built[1]
	service.metrics()
	var vines: Array = []
	for edge in state.edges.values():
		if edge.kind == "vine":
			vines.append(edge.id)
	t.check(vines.size() >= 24, "压力株存在足够的可强化藤")
	var warm: Dictionary = service.preview("reinforce", vines[0])
	t.check(warm.ok, "预览预热成功: " + str(warm.get("reason", "")))
	for index in range(6):
		service.preview("reinforce", vines[index])
	var samples: Array[int] = []
	for index in range(40):
		var target: int = vines[index % vines.size()]
		var begin: int = Time.get_ticks_usec()
		var proposal: Dictionary = service.preview("reinforce", target)
		samples.append(Time.get_ticks_usec() - begin)
		t.check(proposal.ok, "预览样本%d成功" % index)
		t.check(proposal.metrics.water.organs.size() == state.edges.size() + state.leaves.size(),
			"预览指标覆盖候选全部器官")
		t.check(proposal.candidate.edges[target].kind == "branch", "预览候选完成强化改写")
	samples.sort()
	var p95: int = samples[ceili(samples.size() * 0.95) - 1]
	t.check(p95 <= FULL_SOLVE_BUDGET_US, "完整预览路径p95≤8ms；actual=%dus median=%dus max=%dus" %
		[p95, samples[samples.size() / 2], samples[-1]])
	print("PREVIEW_PATH_PERFORMANCE samples=%d median_us=%d p95_us=%d max_us=%d" %
		[samples.size(), samples[samples.size() / 2], p95, samples[-1]])

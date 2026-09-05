extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")
const Simulation = preload("res://scripts/core/simulation.gd")


func run(t) -> void:
	_clone_isolation(t)
	_candidate_mutation_rejected(t)
	_stale_preview_rejected(t)
	_commit_semantics(t)


func _clone_isolation(t) -> void:
	var service = Commands.new(Model.create(), Level.new())
	var candidate = service.state.clone()
	# 嵌套 anchor 字典必须与原状态隔离：改候选不能泄漏回当前植物。
	candidate.nodes[1].anchor["id"] = "hacked"
	candidate.nodes[1].anchor["pos"] = Vector2(99, 99)
	t.check(service.state.nodes[1].anchor.is_empty(), "候选的锚点改动不泄漏回当前植物")
	candidate.energy = 0.0
	t.near(service.state.energy, 30.0, 0.000001, "候选能量隔离")
	candidate.nodes[1].pos = Vector2(-50, -50)
	t.check(service.state.nodes[1].pos == Vector2(2, -0.8), "候选节点位置隔离")
	# 预览返回的候选同样隔离：预览后的直接改写不能进入提交。
	var preview: Dictionary = service.preview("leaf", 1)
	t.check(not preview.ok, "种子上不能直接长叶（sanity）")
	var grow: Dictionary = service.preview("vine", 1, Vector2(0, 1))
	t.check(grow.ok, "藤预览可用")
	grow.candidate.energy = 40.0
	grow.candidate.nodes[grow.node].pos = Vector2(123, 456)
	var commit: Dictionary = service.commit(grow, "mutated")
	t.check(not commit.ok, "预览后被改写的候选拒绝提交")
	t.check(service.state.edges.is_empty(), "被拒提交不影响当前植物")


func _candidate_mutation_rejected(t) -> void:
	var service = Commands.new(Model.create(), Level.new())
	# 提交时校验候选指纹：改能量/结构规模/事件数都会被拒绝。
	var proposal: Dictionary = service.preview("vine", 1, Vector2(0, 1))
	proposal.candidate.energy += 5.0
	t.check(not service.commit(proposal, "energy-mutated").ok, "候选能量被改后提交拒绝")
	proposal = service.preview("vine", 1, Vector2(0, 1))
	proposal.candidate.next_id += 2
	t.check(not service.commit(proposal, "nextid-mutated").ok, "候选ID水位被改后提交拒绝")
	proposal = service.preview("vine", 1, Vector2(0, 1))
	proposal.candidate.events.append({"type": "fake"})
	t.check(not service.commit(proposal, "events-mutated").ok, "候选事件被追加后提交拒绝")


func _stale_preview_rejected(t) -> void:
	var service = Commands.new(Model.create(), Level.new())
	var sim = Simulation.new(service)
	var proposal: Dictionary = service.preview("vine", 1, Vector2(0, 1))
	t.check(proposal.ok, "预览成功")
	# 预览期间模拟推进（revision/tick/能量变化）→ 提交必须失败。
	sim.step(0.1)
	t.check(not service.commit(proposal, "stale").ok, "模拟推进后旧预览拒绝提交")
	t.check(service.state.edges.is_empty(), "过期提交不改变拓扑")
	# revision 相同但内容不同（直接改能量不推进 revision）→ 源摘要拒绝。
	proposal = service.preview("vine", 1, Vector2(0, 1))
	service.state.energy -= 1.0
	t.check(not service.commit(proposal, "content-drift").ok, "源状态内容漂移后预览拒绝提交")
	service.state.energy += 1.0
	t.check(service.commit(service.preview("vine", 1, Vector2(0, 1)), "fresh").ok, "重新预览后提交成功")


func _commit_semantics(t) -> void:
	var service = Commands.new(Model.create(), Level.new())
	var proposal: Dictionary = service.preview("vine", 1, Vector2(0, 1))
	var before = service.state
	var result: Dictionary = service.commit(proposal, "commit-once")
	t.check(result.ok, "提交成功")
	t.check(service.state != before, "提交后状态替换为新对象")
	t.check(before.edges.is_empty(), "旧引用保持提交前的内容")
	t.check(service.commit(proposal, "commit-once").ok, "同一命令ID幂等返回")
	t.check(service.state.edges.size() == 1, "幂等提交不重复生长")

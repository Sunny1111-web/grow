extends RefCounted

func run(t) -> void:
	for configuration in [["upper", 0], ["lower", 0], ["upper", 2], ["lower", 2]]:
		var route: String = configuration[0]
		var result = load("res://tools/balcony_runner.gd").new().run(route, configuration[1])
		t.check(result.ok, "阳台真实路线 " + route + ": " + result.reason)
		if result.ok:
			t.check(result.state.won, "实际胜利条件成立")
			t.check(result.q == 20.0, "真实根接到W2")
			t.check(result.state.validate().is_empty(), "拓扑合法")
			t.check(result.state.rescue_count == configuration[1], "真实退守次数")
			var lower_anchor: bool = false
			for node in result.state.nodes.values():
				lower_anchor = lower_anchor or node.anchor.get("id", "") == "lower_edge"
			t.check(lower_anchor == (route == "lower"), "上下路线经过不同支点")
			_replay(t, result)
			print("BALCONY route=%s actions=%d seconds=%.1f" % [route,result.actions.size(),result.seconds])


# 重放只消费可供窗口操作的指令，能量只能由生产与命令成本变化。
func _replay(t, witness: Dictionary) -> void:
	var model = load("res://scripts/core/plant_state.gd")
	var service = load("res://scripts/core/command_service.gd").new(model.create(), load("res://scripts/core/environment_balcony.gd").new())
	var sim = load("res://scripts/core/simulation.gd").new(service)
	var serial: int = 0
	for action in witness.actions:
		if action.kind == "wait":
			for _tick in range(roundi(action.seconds * 10.0)):
				sim.step(0.1)
		else:
			var proposal = service.preview(action.kind, action.target, action.direction)
			var result = service.commit(proposal, "replay%d" % serial)
			serial += 1
			if not result.ok:
				t.check(false, "动作重放失败：" + result.reason)
				return
	t.check(service.state.won, "纯动作重放也达到实际胜利")
	t.check(is_equal_approx(service.state.energy, witness.state.energy), "重放能量与证据一致")

extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment_balcony.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Simulation = preload("res://scripts/core/simulation.gd")

var service
var sim
var actions: Array = []
var seconds: float = 0.0
var reason: String = ""
var serial: int = 0
var shoot: int = 1
var root_tip: int = 1


func run(route: String = "upper", rescues: int = 0) -> Dictionary:
	service = Commands.new(Model.create(), Level.new())
	sim = Simulation.new(service)
	if route not in ["upper", "lower"]:
		reason = "未知路线：" + route
		return _report(false)
	if rescues > 0:
		for _attempt in range(rescues):
			if not _commit(service.preview("rescue", 1)).ok or not _refill(18.0):
				return _report(false)
		root_tip = 1
	else:
		for _i in range(2):
			var result = _commit(service.preview("root", root_tip, Vector2(0, -1)), Vector2(0, -1))
			if not result.ok:
				return _report(false)
			root_tip = result.node
	for degree in [90.0, 60.0, 0.0]:
		var direction: Vector2 = Vector2.from_angle(deg_to_rad(degree))
		var result = _commit(service.preview("vine", shoot, direction), direction)
		if not result.ok:
			return _report(false)
		shoot = result.node
	if not _commit(service.preview("leaf", shoot)).ok:
		return _report(false)
	# Extra root access is earned through growth; no direct state changes or free E.
	if not _walk_root(Vector2(8.55, -2.7)):
		return _report(false)
	var waypoints: Array = [Vector2(4.8,1.14), Vector2(7.6,1.1), Vector2(9.4,0.78)]
	if route == "lower":
		waypoints += [Vector2(10.4,0.04), Vector2(11.4,0.04), Vector2(12.4,0.04), Vector2(13.6,1.64)]
	else:
		waypoints += [Vector2(10.7,0.94), Vector2(12.0,0.94), Vector2(13.6,1.64)]
	waypoints += [Vector2(14.8,2.7), Vector2(15.7,4.8), Vector2(16.6,5.1)]
	for waypoint in waypoints:
		if not _walk_shoot(waypoint):
			return _report(false)
	if not _stabilize():
		return _report(false)
	for _i in range(31):
		sim.step(0.1)
		seconds += 0.1
	actions.append({"kind": "wait", "seconds": 3.1})
	if not service.state.won:
		reason = "当前藤端未满足窗外健康足水三秒：" + str(service.state.nodes.get(shoot))
	return _report(service.state.won)


func _walk_root(destination: Vector2) -> bool:
	for _i in range(16):
		if service.metrics().water.q >= 20.0:
			return true
		if not _refill(30.0):
			return false
		var best: Dictionary = _best_growth("root", root_tip, destination)
		if best.is_empty():
			reason = "地下路线无法继续到W2：" + str(service.state.nodes[root_tip].pos)
			return false
		var result: Dictionary = _commit(best.proposal, best.direction)
		if not result.ok:
			return false
		root_tip = result.node
	reason = "W2 root route exceeded16 segments"
	return false


func _walk_shoot(destination: Vector2) -> bool:
	for _i in range(8):
		var origin: Vector2 = service.state.nodes[shoot].pos
		if origin.distance_to(destination) < 0.62:
			return true
		if not _stabilize() or not _refill(35.0):
			return false
		var best: Dictionary = _best_growth("vine", shoot, destination)
		if best.is_empty():
			# A stronger existing trunk may make an otherwise unsupported span legal.
			if not _reinforce_best(true):
				reason = "地上路线在 %s 无法朝 %s 继续：%s" % [origin, destination, reason]
				return false
			best = _best_growth("vine", shoot, destination)
		if best.is_empty():
			reason = "强化后依然没有合法方向：%s → %s" % [origin, destination]
			return false
		var result: Dictionary = _commit(best.proposal, best.direction)
		if not result.ok:
			return false
		shoot = result.node
		if not _stabilize():
			return false
		var leaf: Dictionary = service.preview("leaf", shoot)
		var metrics: Dictionary = service.metrics()
		if leaf.ok and leaf.metrics.income - metrics.income >= 0.7 and leaf.metrics.water.demand < leaf.metrics.water.q - 1.0 and leaf.metrics.support.max_risk <= 1.0:
			if not _commit(leaf).ok:
				return false
	reason = "目标点没有在8段内抵达：" + str(destination)
	return false


func _best_growth(kind: String, node: int, target: Vector2) -> Dictionary:
	var origin: Vector2 = service.state.nodes[node].pos
	var desired: float = (target - origin).angle()
	var best: Dictionary = {}
	var score: float = 1000000.0
	for offset in range(-55, 56, 5):
		var direction: Vector2 = Vector2.from_angle(desired + deg_to_rad(offset))
		var proposal: Dictionary = service.preview(kind, node, direction)
		if not proposal.ok:
			continue
		var endpoint: Vector2 = proposal.points.back()
		var water_gain: bool = kind == "root" and proposal.metrics.water.q > service.metrics().water.q
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


func _stabilize() -> bool:
	for _i in range(12):
		if service.metrics().support.max_risk <= 1.00001:
			return true
		if not _reinforce_best(false):
			return false
	reason = "未能稳定悬空网络"
	return false


func _reinforce_best(force: bool) -> bool:
	var before: float = service.metrics().support.max_risk
	var best: Dictionary = {}
	var best_risk: float = 1000000.0
	for edge in service.state.edges.values():
		if edge.kind != "vine":
			continue
		var proposal: Dictionary = service.preview("reinforce", edge.id)
		if proposal.ok and proposal.metrics.support.max_risk < best_risk:
			best_risk = proposal.metrics.support.max_risk
			best = proposal
	if best.is_empty() or (not force and best_risk >= before - 0.000001):
		reason = "当前结构没有可改善风险的强化，风险 %.3f，E %.2f" % [before, service.state.energy]
		return false
	return _commit(best).ok


func _refill(target: float) -> bool:
	var waited: float = 0.0
	for _i in range(1200):
		if service.state.energy >= target:
			if waited > 0.0:
				actions.append({"kind": "wait", "seconds": waited})
			return true
		if service.metrics().income < 0.05:
			reason = "缺少可持续收入，不能补充能量"
			return false
		sim.step(0.1)
		seconds += 0.1
		waited += 0.1
	reason = "等待能量超过120模拟秒"
	return false


func _commit(proposal: Dictionary, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	serial += 1
	var result: Dictionary = service.commit(proposal, "journey%d" % serial)
	if not result.ok:
		reason = result.reason
		return result
	actions.append({"kind": proposal.kind, "target": proposal.target, "direction": direction,
		"node": result.node, "energy": service.state.energy, "position": service.state.nodes[result.node].pos,
		"anchor": service.state.nodes[result.node].anchor.get("id", ""),
		"risk": service.metrics().support.max_risk})
	return result


func _report(ok: bool) -> Dictionary:
	if not ok:
		print("JOURNEY_STOP ", reason)
		for action in actions.slice(maxi(0, actions.size() - 8)):
			print("JOURNEY_LAST ", action)
	var metrics: Dictionary = service.metrics()
	return {"ok": ok, "reason": reason, "state": service.state, "actions": actions,
		"service": service, "sim": sim, "simulated_seconds": seconds, "seconds": seconds, "q": metrics.water.q, "income": metrics.income}

extends RefCounted

const Commands = preload("res://scripts/core/command_service.gd")
const Narrative = preload("res://scripts/core/narrative.gd")
const STEP: float = 0.1

var service
var metrics: Dictionary = {}
var frozen: Dictionary = {}
var accumulator: float = 0.0
var fast_cancelled: bool = false
var needs_rescue: bool = false
var rescue_hint_acknowledged: bool = false
var last_events: Array = []


func _init(command_service) -> void:
	service = command_service
	metrics = service.metrics()


func set_frozen(reason: String, enabled: bool) -> void:
	if enabled:
		frozen[reason] = true
		accumulator = 0.0
	else:
		frozen.erase(reason)


func advance(real_dt: float, fast: bool = false, target_cost: float = 5.0) -> void:
	if not fast:
		fast_cancelled = false
	if not frozen.is_empty():
		return
	metrics = service.metrics()
	if fast and (service.state.energy >= target_cost or _has_danger()):
		fast_cancelled = true
	var multiplier: float = 3.0 if fast and not fast_cancelled else 1.0
	accumulator += clampf(real_dt, 0.0, 0.25) * multiplier
	while accumulator + 0.0000001 >= STEP:
		accumulator -= STEP
		step(STEP)
		if not frozen.is_empty():
			accumulator = 0.0
			break
		if fast and (service.state.energy >= target_cost or _has_danger()):
			fast_cancelled = true
			accumulator = minf(accumulator, STEP * 0.999)
			break


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	var state = service.state
	last_events = []
	metrics = service.metrics()
	var energy_delta: float = 0.0
	var deaths: Array = []
	var breaks: Array = []
	for edge in state.edges.values():
		var supply: float = metrics.water.organs[edge.id].r
		edge.z = update_drought(edge.z, supply, dt)
		if edge.z + 0.000001 >= 24.0:
			deaths.append(edge.id)
		if metrics.support.organs.has(edge.id):
			var risk: float = metrics.support.organs[edge.id].risk
			edge.bend = maxf(0.0, edge.bend + ((risk - 1.0) if risk > 1.0 else -2.0) * dt)
			if edge.bend + 0.000001 >= 2.0:
				breaks.append(edge.id)
	var dead_leaves: Array = []
	for leaf in state.leaves.values():
		var supply: float = metrics.water.organs[leaf.id].r
		leaf.z = update_drought(leaf.z, supply, dt)
		if leaf.z + 0.000001 >= 24.0:
			dead_leaves.append(leaf.id)
		if leaf.emergency:
			var produced: float = minf(maxf(0.0, 18.0 - leaf.produced), supply * dt)
			leaf.produced += produced
			state.emergency_produced = leaf.produced
			energy_delta += produced
		else:
			energy_delta += 1.6 * metrics.light[leaf.id].light * Commands.health_factor(leaf.z) * supply * dt
	state.energy = minf(40.0, state.energy + energy_delta)
	deaths.sort()
	breaks.sort()
	for id in deaths:
		if state.edges.has(id):
			Commands.retire_subtree(state, id, "drought")
			_record("drought", id)
	for id in breaks:
		if state.edges.has(id):
			Commands.retire_subtree(state, id, "overload")
			_record("overload", id)
	for id in dead_leaves:
		if state.leaves.has(id):
			Commands.retire_leaf(state, id, "drought")
			_record("leaf_drought", id)
	state.tick += 1
	state.revision += 1
	metrics = service.metrics()
	last_events.append_array(Narrative.evaluate(state, metrics, service.env))
	_update_exit(dt)
	if state.energy < 3.0 and metrics.income < 0.05:
		state.dry_hint_time += dt
	else:
		state.dry_hint_time = 0.0
	if state.dry_hint_time + 0.000001 >= 3.0 and not needs_rescue and not rescue_hint_acknowledged:
		needs_rescue = true
		set_frozen("rescue_hint", true)
		_record("rescue_hint", state.seed_id)
	if metrics.income >= 0.05:
		needs_rescue = false
		rescue_hint_acknowledged = false
		set_frozen("rescue_hint", false)


static func update_drought(z: float, supply: float, dt: float) -> float:
	return maxf(0.0, z + ((1.0 - supply) if supply < 0.95 else -2.0) * dt)


func _has_danger() -> bool:
	if metrics.support.max_risk > 1.0:
		return true
	for edge in service.state.edges.values():
		if edge.z >= 6.0:
			return true
	for leaf in service.state.leaves.values():
		if leaf.z >= 6.0:
			return true
	return false


func _update_exit(dt: float) -> void:
	var state = service.state
	if state.won:
		return
	var reached: bool = false
	for edge in state.edges.values():
		if edge.kind != "root" and edge.z < 6.0 and metrics.water.organs[edge.id].r >= 0.95:
			if service.env.exit_rect.has_point(state.nodes[edge.b].pos):
				reached = true
	state.victory_time = state.victory_time + dt if reached else 0.0
	if state.victory_time + 0.000001 >= 3.0:
		state.won = true
		_record("victory", state.seed_id)


func _record(type: String, id: int) -> void:
	var event: Dictionary = {"type": type, "id": id, "tick": service.state.tick}
	service.state.events.append(event)
	last_events.append(event)


func acknowledge_rescue_hint() -> void:
	needs_rescue = false
	rescue_hint_acknowledged = true
	set_frozen("rescue_hint", false)

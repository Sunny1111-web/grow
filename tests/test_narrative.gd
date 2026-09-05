extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")
const Simulation = preload("res://scripts/core/simulation.gd")


func run(t) -> void:
	var path: String = "res://scripts/core/narrative.gd"
	t.check(ResourceLoader.exists(path), "State-driven teaching and memory exists")
	if not ResourceLoader.exists(path):
		return
	var narrative = load(path)
	var state = Model.create()
	var service = Commands.new(state, Level.new())
	t.check(narrative.evaluate(state, service.metrics(), service.env).is_empty(), "No milestone before actual progress")
	service.commit(service.preview("rescue", 1), "rescue")
	state = service.state
	t.check(narrative.has_event(state, "tutorial_water"), "Actual water contact opens next teaching step")
	var before: int = state.events.size()
	narrative.evaluate(state, service.metrics(), service.env)
	t.check(state.events.size() == before, "Milestone is not repeated")
	var memory_state = Model.create(Vector2(8.0, 0.6))
	memory_state.add_edge(1, "vine", [Vector2(8.0, 0.6), Vector2(8.5, 0.7)], {"id": "table_left"})
	var memory_service = Commands.new(memory_state, Level.new())
	var energy: float = memory_state.energy
	var events: Array = narrative.evaluate(memory_state, memory_service.metrics(), memory_service.env)
	t.check(narrative.has_event(memory_state, "M1"), "Live shoot near watering can triggers optional memory")
	t.near(memory_state.energy, energy, 0.00001, "Memory grants no energy reward")
	t.check(events.any(func(event): return event.type == "memory" and event.duration == 5.0), "Watering memory lasts5 presentation seconds")
	before = memory_state.events.size()
	narrative.evaluate(memory_state, memory_service.metrics(), memory_service.env)
	t.check(memory_state.events.size() == before, "Watering memory is one-time")
	var history_only = Model.create()
	history_only.history.append({"type": "edge", "node": {"pos": Vector2(8.5, 0.6)}})
	var empty_service = Commands.new(history_only, Level.new())
	narrative.evaluate(history_only, empty_service.metrics(), empty_service.env)
	t.check(not narrative.has_event(history_only, "M1"), "Historical outline cannot discover the memory")
	_exit_rules(t)


func _exit_rules(t) -> void:
	var state = Model.create(Vector2(15.9, 6.1))
	var root: int = state.add_edge(1, "root", [Vector2(15.9, 6.1), Vector2(15.9, 5.3)])
	var vine: int = state.add_edge(1, "vine", [Vector2(15.9, 6.1), Vector2(16.9, 6.1)], {"id": "window_frame"})
	var env = Level.new()
	env.waters = [{"id": "W1", "q": 12.0, "aquifer_id": "one", "rect": Rect2(15.8, 5.2, 0.2, 0.2)}]
	var initial = state.clone()
	var sim = Simulation.new(Commands.new(state, env))
	for _i in range(29):
		sim.step(0.1)
	t.check(not state.won, "Ending does not trigger before3simulated seconds")
	sim.set_frozen("sense", true)
	sim.advance(0.2, true)
	t.near(state.victory_time, 2.9, 0.0001, "Paused perception cannot accumulate ending time")
	sim.set_frozen("sense", false)
	sim.step(0.1)
	t.check(state.won, "Healthy watered live tip wins after3seconds")
	var dry_state = initial.clone()
	Commands.retire_subtree(dry_state, root, "prune")
	sim = Simulation.new(Commands.new(dry_state, env))
	for _i in range(31):
		sim.step(0.1)
	t.check(not dry_state.won, "Unwatered tip cannot trigger ending")
	var past_state = initial.clone()
	Commands.retire_subtree(past_state, vine, "prune")
	sim = Simulation.new(Commands.new(past_state, env))
	for _i in range(31):
		sim.step(0.1)
	t.check(not past_state.won, "Past arrival in historical branches cannot win")

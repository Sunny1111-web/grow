extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Service = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")
var Sim


func run(t) -> void:
	t.check(ResourceLoader.exists("res://scripts/core/simulation.gd"), "Fixed simulation exists")
	if not ResourceLoader.exists("res://scripts/core/simulation.gd"):
		return
	Sim = load("res://scripts/core/simulation.gd")
	var service = Service.new(Model.create(), Level.new())
	service.commit(service.preview("rescue", 1), "r")
	var sim = Sim.new(service)
	sim.set_frozen("menu", true)
	sim.set_frozen("preview", true)
	sim.advance(0.2, true)
	t.near(service.state.energy, 0.0, 0.0001, "Frozen energy remains zero")
	t.check(service.state.tick == 0, "Frozen simulation does not tick")
	sim.set_frozen("menu", false)
	sim.advance(0.2)
	t.check(service.state.tick == 0, "Remaining freeze reason still blocks time")
	sim.set_frozen("preview", false)
	sim.advance(0.05)
	t.check(service.state.tick == 0, "Only whole 0.1s simulation steps")
	sim.advance(0.05)
	t.near(service.state.energy, 0.1, 0.0001, "Emergency leaf yields at fixed timestep")
	for _i in range(200):
		sim.step(0.1)
	t.near(service.state.energy, 18.0, 0.0001, "Emergency leaf lifetime capped at18E")
	t.near(service.state.emergency_produced, 18.0, 0.0001, "Lifetime count persists")
	t.near(sim.metrics.income, 0.0, 0.0001, "Dormant emergency leaf stops earning")
	for organ in service.state.leaves.values():
		t.near(sim.metrics.water.organs[organ.id].demand, 0.0, 0.0001, "Dormant cotyledon stops water maintenance")
	var empty = Model.create()
	empty.energy = 0.0
	var hint_sim = Sim.new(Service.new(empty, Level.new()))
	for _i in range(30):
		hint_sim.step(0.1)
	t.check(hint_sim.frozen.has("rescue_hint"), "Stranded seed prompts and pauses")
	t.check(hint_sim.has_method("acknowledge_rescue_hint"), "Recovery prompt can be dismissed without trapping simulation")
	if hint_sim.has_method("acknowledge_rescue_hint"):
		hint_sim.acknowledge_rescue_hint()
		var before: int = empty.tick
		hint_sim.advance(0.2)
		t.check(empty.tick > before and hint_sim.frozen.is_empty(), "Dismissed crisis prompt does not immediately pause again")
	_withering(t)
	_overload(t)
	_fast_and_rescue_route(t)


func _withering(t) -> void:
	var state = Model.create(Vector2(3.5, 1.5))
	var edge: int = state.add_edge(1, "vine", [Vector2(3.5, 1.5), Vector2(4.5, 1.5)], {"id": "chair_seat"})
	var leaf: int = state.add_leaf(state.edges[edge].b)
	var service = Service.new(state, Level.new())
	var sim = Sim.new(service)
	for _i in range(60):
		sim.step(0.1)
	t.near(service.state.leaves[leaf].z, 6.0, 0.0001, "r0 becomes wilted after6 simulated seconds")
	t.near(Service.health_factor(6.0), 0.6, 0.0001, "Wilted income multiplier")
	for _i in range(60):
		sim.step(0.1)
	t.near(service.state.leaves[leaf].z, 12.0, 0.0001, "r0 curls after12 simulated seconds")
	for _i in range(120):
		sim.step(0.1)
	t.check(service.state.edges.is_empty() and service.state.leaves.is_empty(), "Dead upstream tissue disconnects downstream organs")
	t.check(service.state.history.size() == 2, "Natural death preserves both edge and leaf history")
	t.check(service.state.scars.is_empty(), "Natural death cannot issue a side-bud discount")
	t.near(Sim.update_drought(6.0, 1.0, 1.0), 4.0, 0.0001, "Restored supply heals integral at2/sec")
	t.near(Sim.update_drought(0.0, 0.5, 12.0), 6.0, 0.0001, "Half supply needs12sec for first wilt")


func _overload(t) -> void:
	var state = Model.create(Vector2.ZERO)
	var root: int = state.add_edge(1, "root", [Vector2.ZERO, Vector2(0, -0.8)])
	var env = Level.new()
	env.waters = [{"id": "W1", "aquifer_id": "one", "q": 12.0, "rect": Rect2(-0.1, -0.9, 0.2, 0.2)}]
	var node: int = 1
	for _i in range(3):
		var edge: int = state.add_edge(node, "vine", [state.nodes[node].pos, state.nodes[node].pos + Vector2.RIGHT])
		node = state.edges[edge].b
	var service = Service.new(state, env)
	var sim = Sim.new(service)
	for _i in range(79):
		sim.step(0.1)
	t.check(service.state.edges.size() == 4, "risk1.25 remains for first7.9sec")
	sim.step(0.1)
	t.check(service.state.edges.size() == 1 and service.state.edges.has(root), "risk1.25 breaks at8sec, keeps root")
	t.check(service.state.history.size() == 3, "Overload retires subtree exactly once")


func _fast_and_rescue_route(t) -> void:
	var service = Service.new(Model.create(), Level.new())
	service.commit(service.preview("rescue", 1), "rescue")
	var sim = Sim.new(service)
	sim.advance(0.2, true, 5.0)
	t.near(service.state.energy, 0.6, 0.0001, "F accelerates entire simulation3x")
	for _i in range(40):
		sim.advance(0.2, true, 5.0)
	t.check(sim.fast_cancelled, "F latches off once selected cost reached")
	for _i in range(200):
		sim.step(0.1)
	var node: int = 1
	for degree in [90.0, 60.0, 5.0]:
		var proposal = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
		t.check(proposal.ok, "Rescue 18E supports real growth route: " + proposal.reason)
		if not proposal.ok:
			return
		var result = service.commit(proposal, "grow%.0f" % degree)
		node = result.node
	var leaf = service.preview("leaf", node)
	t.check(leaf.ok, "Rescue route reaches a normal leaf: " + leaf.reason)
	service.commit(leaf, "recovered")
	t.near(service.state.energy, 0.0, 0.0001, "Rescue route spends exactly18E")
	t.check(service.metrics().ordinary_income >= 0.95, "Rescue actually restores regular positive production")

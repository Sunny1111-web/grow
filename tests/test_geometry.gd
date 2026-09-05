extends RefCounted


func run(t) -> void:
	var env_path: String = "res://scripts/core/environment.gd"
	var growth_path: String = "res://scripts/core/growth_solver.gd"
	t.check(ResourceLoader.exists(env_path) and ResourceLoader.exists(growth_path), "Geometry implementation exists")
	if not ResourceLoader.exists(env_path) or not ResourceLoader.exists(growth_path):
		return
	var env = load(env_path).new()
	var solver = load(growth_path)
	var model = load("res://scripts/core/plant_state.gd")
	var state = model.create()
	var node: int = 1
	for index in range(2):
		var root: Dictionary = solver.build(state, env, node, "root", Vector2(0, -1))
		t.check(root.ok, "Opening root %d is legal: %s" % [index, root.reason])
		if not root.ok:
			return
		_check_length(t, root.points, 0.8)
		var edge: int = state.add_edge(node, "root", root.points, root.anchor)
		node = state.edges[edge].b
		env.reveal(state, state.nodes[node].pos)
	t.check(not env.water_contacts(state).is_empty(), "Two actual roots reach W1")
	var revision: int = state.revision
	var id_before: int = state.next_id
	var explored_count: int = state.explored.size()
	node = 1
	for degrees in [90.0, 60.0, 0.0]:
		var direction: Vector2 = Vector2.from_angle(deg_to_rad(degrees))
		var first: Dictionary = solver.build(state, env, node, "vine", direction)
		var again: Dictionary = solver.build(state, env, node, "vine", direction)
		t.check(first.ok, "Opening vine %.0f legal: %s" % [degrees, first.reason])
		if not first.ok:
			print("GEOMETRY_REJECTED: ", first)
			return
		t.check(first.points == again.points, "Repeated preview is deterministic")
		_check_length(t, first.points, 1.0)
		var edge: int = state.add_edge(node, "vine", first.points, first.anchor)
		node = state.edges[edge].b
	print("OPENING_ENDPOINT: ", state.nodes[node].pos, " anchor=", state.nodes[node].anchor)
	t.check(env.light_at(state.nodes[node].pos).intensity >= 0.6, "Three vines reach ordinary light")
	t.check(not state.nodes[node].anchor.is_empty(), "Third vine reaches real chair support")
	t.check(state.revision == revision and state.explored.size() == explored_count, "Vine previews do not reveal underground or increment revision")
	t.check(state.next_id == id_before + 6, "Only explicit added edges allocated IDs")
	var support = load("res://scripts/core/support_solver.gd")
	var first_leaf: int = state.add_leaf(node)
	var illumination = load("res://scripts/core/light_solver.gd").solve(state, env)
	t.near(illumination[first_leaf].light, 0.6, 0.0001, "First real leaf receives unblocked reflected light")
	t.check(support.solve(state).max_risk <= 1.0, "Opening leaf stable without reinforcement")
	var isolated = load(env_path).new()
	isolated.obstacles = [{"id": "thin", "rect": Rect2(0.49, -1, 0.03, 2)}]
	t.check(isolated.blocked([Vector2.ZERO, Vector2(1, 0)], 0.04), "Sweep cannot cross 0.03u thin wall")
	t.check(isolated.blocked([Vector2(0, 1.02), Vector2(1, 1.02)], 0.04), "Sweep respects radius at corner")
	t.check(not isolated.blocked([Vector2(0, 1.06), Vector2(1, 1.06)], 0.04), "Sweep allows sufficient clearance")
	isolated.soils = [Rect2(-1, -1, 2, 0.5), Rect2(-1, 0.5, 2, 0.5)]
	t.check(not isolated.root_allowed([Vector2(0, -0.8), Vector2(0, 0.8)]), "Roots cannot skip non-soil gap")
	isolated.lights = [{"id": "weak", "rect": Rect2(-2, -2, 4, 4), "intensity": 0.2, "direction": Vector2.UP},
		{"id": "strong", "rect": Rect2(-1, -1, 2, 2), "intensity": 1.0, "direction": Vector2.UP}]
	t.near(isolated.light_at(Vector2.ZERO).intensity, 1.0, 0.0001, "Overlapping light fixtures take max")
	var near_water = model.create()
	var near_root: int = near_water.add_edge(1, "root", [Vector2(2, -0.8), Vector2(2, -1.6)])
	var near_tip: int = near_water.edges[near_root].b
	env.reveal(near_water, near_water.nodes[near_tip].pos)
	t.check("W1" in near_water.revealed and env.water_contacts(near_water).is_empty(), "Water is visible before physical contact")
	t.check(env.stimulus(near_water, near_water.nodes[near_tip].pos, "root").dot(Vector2(0, -1)) > 0.95, "A revealed but unconnected water source still guides the root")
	var no_hint = model.create(Vector2(0, -3.8))
	t.check(env.stimulus(no_hint, Vector2(0, -3.8), "root") == Vector2.ZERO, "Hidden water outside perception cannot steer roots")
	var reveal_before: int = no_hint.explored.size()
	solver.build(no_hint, env, 1, "root", Vector2.RIGHT)
	t.check(no_hint.explored.size() == reveal_before, "Cancelled root preview reveals nothing")


func _check_length(t, points: Array, target: float) -> void:
	var arc: float = 0.0
	var largest: float = 0.0
	for index in range(1, points.size()):
		var span: float = points[index].distance_to(points[index - 1])
		arc += span
		largest = maxf(largest, span)
	t.near(arc, target, 0.01, "Fixed segment arc length")
	t.check(largest <= 0.05001, "Authority samples at most 0.05u apart")

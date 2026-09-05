extends RefCounted


func run(t) -> void:
	var path: String = "res://scripts/core/plant_state.gd"
	t.check(ResourceLoader.exists(path), "PlantState implementation exists")
	if not ResourceLoader.exists(path):
		return
	var model = load(path)
	var state = model.create()
	t.near(state.energy, 30.0, 0.0001, "New seed starts with 30 energy")
	t.check(state.nodes.size() == 1 and state.seed_id == 1, "Exactly one persistent seed")
	t.check(state.validate().is_empty(), "Initial tree validates")
	var root_points: Array = [Vector2(2, -0.8), Vector2(2, -1.6)]
	var edge_id: int = state.add_edge(1, "root", root_points)
	var endpoint: int = state.edges[edge_id].b
	t.check(state.nodes[endpoint].parent_edge == edge_id, "Child links back to parent edge")
	t.near(state.edges[edge_id].length, 0.8, 0.0001, "Stores actual polyline arc length")
	var vine_id: int = state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.2)])
	var leaf_id: int = state.add_leaf(state.edges[vine_id].b)
	t.check(state.leaf_at(state.edges[vine_id].b) == leaf_id, "Finds leaf at selected growth node")
	t.check(state.children(1).size() == 2 and state.children(1, "root").size() == 1, "Queries typed outgoing edges")
	t.check(state.validate().is_empty(), "Mixed root and shoot tree validates")
	var candidate = state.clone()
	candidate.nodes[endpoint].pos = Vector2.ZERO
	candidate.energy = 1.0
	candidate.events.append({"type": "candidate"})
	t.check(state.nodes[endpoint].pos == Vector2(2, -1.6), "Candidate geometry isolated")
	t.near(state.energy, 30.0, 0.0001, "Candidate economy isolated")
	t.check(state.events.is_empty(), "Candidate history isolated")
	var broken = state.clone()
	broken.edges[edge_id].a = 9999
	t.check(not broken.validate().is_empty(), "Rejects orphaned edge")
	broken = state.clone()
	broken.energy = NAN
	t.check(not broken.validate().is_empty(), "Rejects non-finite energy")
	broken = state.clone()
	broken.nodes[1].parent_edge = edge_id
	t.check(not broken.validate().is_empty(), "Rejects seed cycle")
	broken = state.clone()
	broken.nodes[endpoint].pos.x = INF
	t.check(not broken.validate().is_empty(), "Rejects non-finite positions")

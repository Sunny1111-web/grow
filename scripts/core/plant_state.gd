extends RefCounted

const MAX_EDGES: int = 400
const MAX_LEAVES: int = 100
const ENERGY_CAP: float = 40.0

var energy: float = 30.0
var revision: int = 0
var next_id: int = 2
var tick: int = 0
var seed_id: int = 1
var nodes: Dictionary = {}
var edges: Dictionary = {}
var leaves: Dictionary = {}
var history: Array = []
var scars: Dictionary = {}
var events: Array = []
var explored: Array = []
var revealed: Array = []
var emergency_produced: float = 0.0
var rescue_count: int = 0
var victory_time: float = 0.0
var won: bool = false
var dry_hint_time: float = 0.0


static func create(seed_position: Vector2 = Vector2(2.0, -0.8)):
	var state = load("res://scripts/core/plant_state.gd").new()
	state.nodes[1] = {"id": 1, "pos": seed_position, "parent_edge": 0,
		"kind": "seed", "anchor": {}, "emergency": false}
	return state


func clone():
	var result = get_script().new()
	for field in persistent_fields():
		var value = get(field)
		result.set(field, value.duplicate(true) if value is Dictionary or value is Array else value)
	return result


static func persistent_fields() -> Array:
	return ["energy", "revision", "next_id", "tick", "seed_id", "nodes", "edges", "leaves",
		"history", "scars", "events", "explored", "revealed", "emergency_produced",
		"rescue_count", "victory_time", "won", "dry_hint_time"]


func add_edge(a: int, kind: String, points: Array, anchor: Dictionary = {}, emergency: bool = false, slot: int = 0) -> int:
	var edge_id: int = next_id
	var node_id: int = next_id + 1
	next_id += 2
	var arc: float = 0.0
	for index in range(1, points.size()):
		arc += points[index - 1].distance_to(points[index])
	edges[edge_id] = {"id": edge_id, "a": a, "b": node_id, "kind": kind,
		"length": arc, "points": points.duplicate(true), "z": 0.0, "bend": 0.0,
		"emergency": emergency, "slot": slot}
	nodes[node_id] = {"id": node_id, "pos": points.back(), "parent_edge": edge_id,
		"kind": "root" if kind == "root" else "shoot", "anchor": anchor.duplicate(true),
		"emergency": emergency}
	return edge_id


func add_leaf(node: int, angle: float = 0.8, emergency: bool = false) -> int:
	var leaf_id: int = next_id
	next_id += 1
	leaves[leaf_id] = {"id": leaf_id, "node": node, "angle": angle, "z": 0.0,
		"emergency": emergency, "produced": 0.0}
	return leaf_id


func children(node: int, kind: String = "") -> Array:
	var result: Array = []
	var ids: Array = edges.keys()
	ids.sort()
	for id in ids:
		var edge: Dictionary = edges[id]
		if edge.a == node and (kind == "" or edge.kind == kind):
			result.append(edge)
	return result


func leaf_at(node: int, include_emergency: bool = false) -> int:
	for id in leaves:
		if leaves[id].node == node and (include_emergency or not leaves[id].emergency):
			return id
	return 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(energy) or energy < 0.0 or energy > ENERGY_CAP:
		errors.append("Energy outside finite range [0,40]")
	if revision < 0 or tick < 0 or next_id < 2:
		errors.append("Invalid counters")
	for value in [emergency_produced, victory_time, dry_hint_time]:
		if not is_finite(value) or value < 0.0:
			errors.append("Invalid simulation accumulator")
	if edges.size() > MAX_EDGES or leaves.size() > MAX_LEAVES:
		errors.append("Live organ capacity exceeded")
	if not nodes.has(seed_id) or nodes[seed_id].get("parent_edge", -1) != 0:
		errors.append("Missing or parented seed")
	var used: Dictionary = {}
	for collection in [nodes, edges, leaves]:
		for id in collection:
			if not id is int or id < 1 or id >= next_id or used.has(id) or collection[id].get("id", -1) != id:
				errors.append("Invalid or duplicate persistent ID")
			used[id] = true
	for id in nodes:
		var node: Dictionary = nodes[id]
		if not _finite_position(node.get("pos")):
			errors.append("Invalid node position")
		if node.get("kind", "") not in ["seed", "root", "shoot"]:
			errors.append("Invalid node type")
		if id != seed_id:
			var incoming: int = node.get("parent_edge", 0)
			if not edges.has(incoming) or edges[incoming].get("b", 0) != id:
				errors.append("Node parent mismatch")
	for id in edges:
		var edge: Dictionary = edges[id]
		if not nodes.has(edge.get("a", 0)) or not nodes.has(edge.get("b", 0)):
			errors.append("Orphan edge")
			continue
		if edge.get("kind", "") not in ["root", "vine", "branch"]:
			errors.append("Invalid edge type")
		var points = edge.get("points", [])
		if not points is Array or points.size() < 2:
			errors.append("Missing edge geometry")
			continue
		var arc: float = 0.0
		var valid_points: bool = true
		for point in points:
			if not _finite_position(point):
				valid_points = false
		if not valid_points:
			errors.append("Non-finite edge geometry")
			continue
		for index in range(1, points.size()):
			arc += points[index - 1].distance_to(points[index])
		if arc <= 0.0 or not is_finite(edge.get("length", NAN)) or absf(edge.length - arc) > 0.001:
			errors.append("Edge length does not match geometry")
		if points.front().distance_to(nodes[edge.a].pos) > 0.001 or points.back().distance_to(nodes[edge.b].pos) > 0.001:
			errors.append("Edge endpoints do not match nodes")
		for field in ["z", "bend"]:
			if not is_finite(edge.get(field, NAN)) or edge[field] < 0.0:
				errors.append("Invalid edge accumulator")
	for id in leaves:
		var leaf: Dictionary = leaves[id]
		if not nodes.has(leaf.get("node", 0)):
			errors.append("Orphan leaf")
		for field in ["angle", "z", "produced"]:
			if not is_finite(leaf.get(field, NAN)):
				errors.append("Invalid leaf scalar")
	# Each node's parent chain must reach the seed, not an orphan or cycle.
	for id in nodes:
		var visited: Dictionary = {}
		var current: int = id
		while current != seed_id:
			if visited.has(current) or not nodes.has(current):
				errors.append("Cycle or disconnected component")
				break
			visited[current] = true
			var incoming: int = nodes[current].get("parent_edge", 0)
			if not edges.has(incoming):
				errors.append("Disconnected parent chain")
				break
			current = edges[incoming].get("a", 0)
	return errors


static func _finite_position(value) -> bool:
	return value is Vector2 and is_finite(value.x) and is_finite(value.y)

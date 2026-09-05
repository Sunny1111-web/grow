extends RefCounted


static func solve(state) -> Dictionary:
	var outgoing: Dictionary = {}
	var node_leaves: Dictionary = {}
	var midpoint: Dictionary = {}
	for node in state.nodes:
		outgoing[node] = []
		node_leaves[node] = []
	for edge in state.edges.values():
		if edge.kind != "root":
			outgoing[edge.a].append(edge.id)
			midpoint[edge.id] = arc_midpoint(edge.points, edge.length)
	for leaf in state.leaves.values():
		if not leaf.emergency:
			node_leaves[leaf.node].append(leaf.id)
	var result: Dictionary = {"max_risk": 0.0, "organs": {}}
	for edge in state.edges.values():
		if edge.kind == "root":
			continue
		var origin: Vector2 = state.nodes[edge.a].pos
		var distance: float = 0.0
		var moment: float = 0.0
		var pending: Array = [[edge.id, 0.0]]
		while not pending.is_empty():
			var entry: Array = pending.pop_back()
			var current: Dictionary = state.edges[entry[0]]
			if not state.nodes[current.b].anchor.is_empty():
				continue
			var length_to: float = entry[1] + current.length
			distance = maxf(distance, length_to)
			var weight: float = current.length * (0.45 if current.kind == "branch" else 0.25)
			moment += weight * _lever(origin, midpoint[current.id])
			for _leaf_id in node_leaves[current.b]:
				moment += 0.25 * _lever(origin, state.nodes[current.b].pos)
			for child in outgoing[current.b]:
				pending.append([child, length_to])
		var risk: float = maxf(distance / (4.0 if edge.kind == "branch" else 2.4),
			moment / (3.0 if edge.kind == "branch" else 1.2))
		result.organs[edge.id] = {"risk": risk, "distance": distance, "moment": moment}
		result.max_risk = maxf(result.max_risk, risk)
	return result


static func arc_midpoint(points: Array, length: float) -> Vector2:
	var remaining: float = length * 0.5
	for index in range(1, points.size()):
		var span: float = points[index - 1].distance_to(points[index])
		if remaining <= span:
			return points[index - 1].lerp(points[index], remaining / maxf(span, 0.000001))
		remaining -= span
	return points.back()


static func _lever(origin: Vector2, position: Vector2) -> float:
	var delta: Vector2 = position - origin
	return absf(delta.x) + 0.25 * absf(delta.y) + 0.1

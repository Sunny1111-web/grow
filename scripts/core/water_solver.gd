extends RefCounted

const RESISTANCE = {"root": 0.08, "vine": 0.12, "branch": 0.05}
const NEED = {"root": 0.15, "vine": 0.35, "branch": 0.5}
const PRIORITY = {"root": 0, "branch": 1, "vine": 2, "leaf": 3}
const UNREACHABLE: float = 1000000.0


static func solve(state, accesses: Array) -> Dictionary:
	var graph: Dictionary = {}
	var splits: Dictionary = {}
	for id in state.nodes:
		graph[id] = []
		splits[id] = 0
	for edge in state.edges.values():
		var cost: float = edge.length * RESISTANCE[edge.kind]
		graph[edge.a].append([edge.b, cost])
		graph[edge.b].append([edge.a, cost])
		if edge.kind != "root":
			splits[edge.a] += 1
	var distances: Dictionary = {}
	for id in graph:
		distances[id] = UNREACHABLE
	var queue: Array = []
	var q: float = 0.0
	for access in accesses:
		var node: int = access.node
		if not graph.has(node):
			continue
		q = maxf(q, float(access.q))
		var cost: float = 0.15 if splits[node] >= 2 else 0.0
		if cost < distances[node]:
			distances[node] = cost
			_push(queue, [cost, node])
	while not queue.is_empty():
		var item: Array = _pop(queue)
		var node: int = item[1]
		if item[0] > distances[node]:
			continue
		for neighbor in graph[node]:
			var cost: float = item[0] + neighbor[1] + (0.15 if splits[neighbor[0]] >= 2 else 0.0)
			if cost < distances[neighbor[0]]:
				distances[neighbor[0]] = cost
				_push(queue, [cost, neighbor[0]])
	var ordered: Array = []
	for edge in state.edges.values():
		var half: float = edge.length * RESISTANCE[edge.kind] * 0.5
		var resistance: float = minf(distances[edge.a], distances[edge.b]) + half
		ordered.append({"id": edge.id, "priority": PRIORITY[edge.kind],
			"resistance": resistance, "base": NEED[edge.kind]})
	for leaf in state.leaves.values():
		var need: float = 0.8
		if leaf.emergency:
			need = 0.0 if leaf.produced >= 18.0 else 0.2
		ordered.append({"id": leaf.id, "priority": 3, "resistance": distances[leaf.node], "base": need})
	ordered.sort_custom(func(a, b):
		if a.priority != b.priority:
			return a.priority < b.priority
		if absf(a.resistance - b.resistance) > 0.0000001:
			return a.resistance < b.resistance
		return a.id < b.id)
	var result: Dictionary = {"q": q, "demand": 0.0, "spent": 0.0, "organs": {}}
	var remaining: float = q
	for item in ordered:
		var demand: float = item.base * (1.0 + item.resistance)
		var spent: float = minf(remaining, demand)
		var delivered: float = spent / (1.0 + item.resistance)
		remaining -= spent
		result.demand += demand
		result.spent += spent
		result.organs[item.id] = {"r": delivered / item.base if item.base > 0.0 else 1.0,
			"resistance": item.resistance, "demand": demand, "delivered": delivered,
			"spent": spent, "base": item.base}
	return result


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if heap[parent][0] <= item[0]:
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item


static func _pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last = heap.pop_back()
	if heap.is_empty():
		return result
	var index: int = 0
	while index * 2 + 1 < heap.size():
		var child: int = index * 2 + 1
		if child + 1 < heap.size() and heap[child + 1][0] < heap[child][0]:
			child += 1
		if last[0] <= heap[child][0]:
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result

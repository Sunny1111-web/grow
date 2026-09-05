extends RefCounted


static func solve(state) -> Dictionary:
	var result: Dictionary = {"max_risk": 0.0, "organs": {}}
	var edges: Array[Dictionary] = []
	var edge_index: Dictionary = {}
	var leaf_weights: Dictionary = {}
	for edge in state.edges.values():
		if edge.kind != "root":
			edge_index[edge.id] = edges.size()
			edges.append(edge)
	for leaf in state.leaves.values():
		if not leaf.emergency:
			leaf_weights[leaf.node] = float(leaf_weights.get(leaf.node, 0.0)) + 0.25
	var count: int = edges.size()
	if count == 0:
		return result
	# 节点字段预提取为平行数组，遍历中不再重复Dictionary访问。
	var node_index: Dictionary = {}
	var node_pos: Array[Vector2] = []
	var node_anchored: PackedByteArray = PackedByteArray()
	var node_parent_edge: PackedInt32Array = PackedInt32Array()
	for node_id in state.nodes:
		var node: Dictionary = state.nodes[node_id]
		node_index[node_id] = node_pos.size()
		node_pos.append(node.pos)
		node_anchored.append(int(node.anchor.is_empty()))
		node_parent_edge.append(node.parent_edge)
	# 子节点用尾插sibling链平铺，遍历顺序与按ID递增的Array[Array]完全相同。
	var first_child: PackedInt32Array = PackedInt32Array()
	first_child.resize(count)
	first_child.fill(-1)
	var last_child: PackedInt32Array = PackedInt32Array()
	last_child.resize(count)
	last_child.fill(-1)
	var next_sibling: PackedInt32Array = PackedInt32Array()
	next_sibling.resize(count)
	next_sibling.fill(-1)
	var origins: Array[Vector2] = []
	origins.resize(count)
	var active: PackedByteArray = PackedByteArray()
	active.resize(count)
	var pending: Array[int] = []
	for index in range(count):
		var ia: int = node_index[edges[index].a]
		origins[index] = node_pos[ia]
		active[index] = node_anchored[node_index[edges[index].b]]
		if not active[index]:
			continue
		var parent: int = edge_index.get(node_parent_edge[ia], -1)
		if parent >= 0 and active[parent]:
			if first_child[parent] < 0:
				first_child[parent] = index
			else:
				next_sibling[last_child[parent]] = index
			last_child[parent] = index
		else:
			pending.append(index)

	# An anchor (or an underground root) ends one support region. Within each
	# resulting tree, DFS places every edge's descendant loads in [start, end).
	var starts: PackedInt32Array = PackedInt32Array()
	var ends: PackedInt32Array = PackedInt32Array()
	var distances: PackedFloat64Array = PackedFloat64Array()
	starts.resize(count)
	ends.resize(count)
	distances.resize(count)
	var positions: PackedVector2Array = PackedVector2Array()
	var weights: PackedFloat64Array = PackedFloat64Array()
	while not pending.is_empty():
		var index: int = pending.pop_back()
		if index >= 0:
			var edge: Dictionary = edges[index]
			starts[index] = weights.size()
			positions.append(arc_midpoint(edge.points, edge.length))
			weights.append(edge.length * (0.45 if edge.kind == "branch" else 0.25))
			var leaf_weight: float = leaf_weights.get(edge.b, 0.0)
			if leaf_weight > 0.0:
				positions.append(node_pos[node_index[edge.b]])
				weights.append(leaf_weight)
			pending.append(-index - 1)
			var child: int = first_child[index]
			while child >= 0:
				pending.append(child)
				child = next_sibling[child]
		else:
			index = -index - 1
			ends[index] = weights.size()
			var furthest_child: float = 0.0
			var child: int = first_child[index]
			while child >= 0:
				furthest_child = maxf(furthest_child, distances[child])
				child = next_sibling[child]
			distances[index] = edges[index].length + furthest_child

	var weight_prefix: PackedFloat64Array = PackedFloat64Array()
	weight_prefix.resize(weights.size() + 1)
	for index in range(weights.size()):
		weight_prefix[index + 1] = weight_prefix[index] + weights[index]
	# 排序比较只读分量，一次提取为普通数组供lambda按引用访问。
	var load_x: Array = []
	var load_y: Array = []
	load_x.resize(positions.size())
	load_y.resize(positions.size())
	for index in range(positions.size()):
		load_x[index] = positions[index].x
		load_y[index] = positions[index].y
	var origin_x: Array = []
	var origin_y: Array = []
	origin_x.resize(count)
	origin_y.resize(count)
	for index in range(count):
		origin_x[index] = origins[index].x
		origin_y[index] = origins[index].y
	# 两轴力矩互相独立且只读共享输入，worker线程并行后串行汇总。
	var moments_pair: Array = [PackedFloat64Array(), PackedFloat64Array()]
	var task: int = WorkerThreadPool.add_task(func() -> void:
		moments_pair[0] = _absolute_moments(load_x, origin_x, weights, starts, ends, weight_prefix))
	moments_pair[1] = _absolute_moments(load_y, origin_y, weights, starts, ends, weight_prefix)
	WorkerThreadPool.wait_for_task_completion(task)
	var x_moments: PackedFloat64Array = moments_pair[0]
	var y_moments: PackedFloat64Array = moments_pair[1]
	for index in range(count):
		var edge: Dictionary = edges[index]
		var moment: float = x_moments[index] + 0.25 * y_moments[index] + 0.1 * (weight_prefix[ends[index]] - weight_prefix[starts[index]])
		var risk: float = maxf(distances[index] / (4.0 if edge.kind == "branch" else 2.4),
			moment / (3.0 if edge.kind == "branch" else 1.2))
		result.organs[edge.id] = {"risk": risk, "distance": distances[index], "moment": moment}
		result.max_risk = maxf(result.max_risk, risk)
	return result


# Sort load coordinates and query origins once per axis. Fenwick prefix sums
# select loads left of the origin within each DFS interval. For total W/S and
# left Wl/Sl, sum(weight * abs(coordinate - origin)) = S - origin*W
# + 2*(origin*Wl - Sl). This preserves both signs instead of using a centroid.
static func _absolute_moments(load_coords: Array, origin_coords: Array,
		weights: PackedFloat64Array, starts: PackedInt32Array, ends: PackedInt32Array,
		weight_prefix: PackedFloat64Array) -> PackedFloat64Array:
	var loads: Array[int] = []
	var queries: Array[int] = []
	var weighted_prefix: PackedFloat64Array = PackedFloat64Array()
	weighted_prefix.resize(weights.size() + 1)
	for index in range(weights.size()):
		loads.append(index)
		weighted_prefix[index + 1] = weighted_prefix[index] + weights[index] * load_coords[index]
	for index in range(origin_coords.size()):
		if starts[index] < ends[index]:
			queries.append(index)
	_sort_by_coords(loads, load_coords)
	_sort_by_coords(queries, origin_coords)
	var tree_weight: PackedFloat64Array = PackedFloat64Array()
	var tree_weighted: PackedFloat64Array = PackedFloat64Array()
	tree_weight.resize(weights.size() + 1)
	tree_weighted.resize(weights.size() + 1)
	var moments: PackedFloat64Array = PackedFloat64Array()
	moments.resize(origin_coords.size())
	var cursor: int = 0
	for query in queries:
		var origin: float = origin_coords[query]
		while cursor < loads.size() and load_coords[loads[cursor]] <= origin:
			var load_index: int = loads[cursor]
			var weight: float = weights[load_index]
			var weighted: float = weight * load_coords[load_index]
			var slot: int = load_index + 1
			while slot < tree_weight.size():
				tree_weight[slot] += weight
				tree_weighted[slot] += weighted
				slot += slot & -slot
			cursor += 1
		var start: int = starts[query]
		var end: int = ends[query]
		var total_weight: float = weight_prefix[end] - weight_prefix[start]
		var total_weighted: float = weighted_prefix[end] - weighted_prefix[start]
		var left_weight: float = 0.0
		var left_weighted: float = 0.0
		var slot: int = end
		while slot > 0:
			left_weight += tree_weight[slot]
			left_weighted += tree_weighted[slot]
			slot -= slot & -slot
		slot = start
		while slot > 0:
			left_weight -= tree_weight[slot]
			left_weighted -= tree_weighted[slot]
			slot -= slot & -slot
		moments[query] = maxf(0.0, total_weighted - origin * total_weight + 2.0 * (origin * left_weight - left_weighted))
	return moments


# 迭代快速排序：与sort_custom同为不稳定排序；同坐标元素交换不改变
# Fenwick前缀和与逐query的独立求值，结果保持不变。无Callable逐元素调用。
static func _sort_by_coords(ids: Array, coords: Array) -> void:
	var stack: Array = []
	stack.append(0)
	stack.append(ids.size() - 1)
	while not stack.is_empty():
		var high: int = stack.pop_back()
		var low: int = stack.pop_back()
		if low >= high:
			continue
		var pivot: float = coords[ids[(low + high) / 2]]
		var i: int = low
		var j: int = high
		while i <= j:
			while coords[ids[i]] < pivot:
				i += 1
			while coords[ids[j]] > pivot:
				j -= 1
			if i <= j:
				var swap: int = ids[i]
				ids[i] = ids[j]
				ids[j] = swap
				i += 1
				j -= 1
		if low < j:
			stack.append(low)
			stack.append(j)
		if i < high:
			stack.append(i)
			stack.append(high)


static func arc_midpoint(points: Array, length: float) -> Vector2:
	var remaining: float = length * 0.5
	for index in range(1, points.size()):
		var span: float = points[index - 1].distance_to(points[index])
		if remaining <= span:
			return points[index - 1].lerp(points[index], remaining / maxf(span, 0.000001))
		remaining -= span
	return points.back()

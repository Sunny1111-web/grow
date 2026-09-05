extends RefCounted

# kind编码：0=root、1=vine、2=branch；与原字典常量逐项对应。
const RESISTANCE = [0.08, 0.12, 0.05]
const NEED = [0.15, 0.35, 0.5]
const PRIORITY = [0, 2, 1]
const UNREACHABLE: float = 1000000.0


# 迭代快速排序；比较与排序谓词同序：priority、resistance(1e-7容差)、id。
# sort_custom同样不稳定，而id唯一保证两实现产出同一排列。
static func _sort_organs(order: Array, ids: PackedInt32Array,
		priorities: PackedInt32Array, resistances: PackedFloat64Array) -> void:
	var stack: Array = []
	stack.append(0)
	stack.append(order.size() - 1)
	while not stack.is_empty():
		var high: int = stack.pop_back()
		var low: int = stack.pop_back()
		if low >= high:
			continue
		var middle: int = order[(low + high) / 2]
		var pivot_priority: int = priorities[middle]
		var pivot_resistance: float = resistances[middle]
		var pivot_id: int = ids[middle]
		var i: int = low
		var j: int = high
		while i <= j:
			while true:
				var candidate: int = order[i]
				var priority_delta: int = priorities[candidate] - pivot_priority
				if priority_delta < 0 or (priority_delta == 0 and (
						resistances[candidate] - pivot_resistance < -0.0000001 or (
						absf(resistances[candidate] - pivot_resistance) <= 0.0000001
						and ids[candidate] < pivot_id))):
					i += 1
				else:
					break
			while true:
				var candidate: int = order[j]
				var priority_delta: int = priorities[candidate] - pivot_priority
				if priority_delta > 0 or (priority_delta == 0 and (
						resistances[candidate] - pivot_resistance > 0.0000001 or (
						absf(resistances[candidate] - pivot_resistance) <= 0.0000001
						and ids[candidate] > pivot_id))):
					j -= 1
				else:
					break
			if i <= j:
				var swap: int = order[i]
				order[i] = order[j]
				order[j] = swap
				i += 1
				j -= 1
		if low < j:
			stack.append(low)
			stack.append(j)
		if i < high:
			stack.append(i)
			stack.append(high)


static func solve(state, accesses: Array) -> Dictionary:
	# 节点ID压缩为连续下标，邻接表按CSR平铺，堆用双平铺数组，全程无嵌套装箱。
	var node_ids: Array = state.nodes.keys()
	var node_count: int = node_ids.size()
	var index_of: Dictionary = {}
	for i in range(node_count):
		index_of[node_ids[i]] = i
	var edge_list: Array = state.edges.values()
	var edge_count: int = edge_list.size()
	var splits: PackedInt32Array = PackedInt32Array()
	splits.resize(node_count)
	var degrees: PackedInt32Array = PackedInt32Array()
	degrees.resize(node_count)
	var edge_a: PackedInt32Array = PackedInt32Array()
	var edge_b: PackedInt32Array = PackedInt32Array()
	var edge_code: PackedInt32Array = PackedInt32Array()
	var edge_lengths: PackedFloat64Array = PackedFloat64Array()
	var edge_ids: PackedInt32Array = PackedInt32Array()
	edge_a.resize(edge_count)
	edge_b.resize(edge_count)
	edge_code.resize(edge_count)
	edge_lengths.resize(edge_count)
	edge_ids.resize(edge_count)
	for i in range(edge_count):
		var edge: Dictionary = edge_list[i]
		var ia: int = index_of[edge.a]
		var ib: int = index_of[edge.b]
		var code: int = 0 if edge.kind == "root" else (1 if edge.kind == "vine" else 2)
		degrees[ia] += 1
		degrees[ib] += 1
		if code != 0:
			splits[ia] += 1
		edge_a[i] = ia
		edge_b[i] = ib
		edge_code[i] = code
		edge_lengths[i] = edge.length
		edge_ids[i] = edge.id
	var offsets: PackedInt32Array = PackedInt32Array()
	offsets.resize(node_count + 1)
	for i in range(node_count):
		offsets[i + 1] = offsets[i] + degrees[i]
	var cursor: PackedInt32Array = offsets.duplicate()
	var adj_node: PackedInt32Array = PackedInt32Array()
	adj_node.resize(edge_count * 2)
	var adj_cost: PackedFloat64Array = PackedFloat64Array()
	adj_cost.resize(edge_count * 2)
	for i in range(edge_count):
		var cost: float = edge_lengths[i] * RESISTANCE[edge_code[i]]
		var ia: int = edge_a[i]
		var ib: int = edge_b[i]
		var slot: int = cursor[ia]
		adj_node[slot] = ib
		adj_cost[slot] = cost
		cursor[ia] = slot + 1
		slot = cursor[ib]
		adj_node[slot] = ia
		adj_cost[slot] = cost
		cursor[ib] = slot + 1
	var distances: PackedFloat64Array = PackedFloat64Array()
	distances.resize(node_count)
	distances.fill(UNREACHABLE)
	var heap_cost: PackedFloat64Array = PackedFloat64Array()
	var heap_node: PackedInt32Array = PackedInt32Array()
	var q: float = 0.0
	for access in accesses:
		var node: int = access.node
		if not index_of.has(node):
			continue
		q = maxf(q, float(access.q))
		var idx: int = index_of[node]
		var cost: float = 0.15 if splits[idx] >= 2 else 0.0
		if cost < distances[idx]:
			distances[idx] = cost
			heap_cost.append(cost)
			heap_node.append(idx)
			var child: int = heap_cost.size() - 1
			while child > 0:
				var parent: int = (child - 1) / 2
				if heap_cost[parent] <= heap_cost[child]:
					break
				var swap_cost: float = heap_cost[parent]
				var swap_node: int = heap_node[parent]
				heap_cost[parent] = heap_cost[child]
				heap_node[parent] = heap_node[child]
				heap_cost[child] = swap_cost
				heap_node[child] = swap_node
				child = parent
	while heap_node.size() > 0:
		var base: float = heap_cost[0]
		var node_idx: int = heap_node[0]
		var last_cost: float = heap_cost[heap_cost.size() - 1]
		var last_node: int = heap_node[heap_node.size() - 1]
		heap_cost.remove_at(heap_cost.size() - 1)
		heap_node.remove_at(heap_node.size() - 1)
		if heap_node.size() > 0:
			heap_cost[0] = last_cost
			heap_node[0] = last_node
			var hole: int = 0
			while hole * 2 + 1 < heap_node.size():
				var pick: int = hole * 2 + 1
				if pick + 1 < heap_node.size() and heap_cost[pick + 1] < heap_cost[pick]:
					pick += 1
				if last_cost <= heap_cost[pick]:
					break
				heap_cost[hole] = heap_cost[pick]
				heap_node[hole] = heap_node[pick]
				hole = pick
			heap_cost[hole] = last_cost
			heap_node[hole] = last_node
		if base > distances[node_idx]:
			continue
		for slot in range(offsets[node_idx], offsets[node_idx + 1]):
			var neighbor: int = adj_node[slot]
			var cost: float = base + adj_cost[slot] + (0.15 if splits[neighbor] >= 2 else 0.0)
			if cost < distances[neighbor]:
				distances[neighbor] = cost
				heap_cost.append(cost)
				heap_node.append(neighbor)
				var child: int = heap_cost.size() - 1
				while child > 0:
					var parent: int = (child - 1) / 2
					if heap_cost[parent] <= heap_cost[child]:
						break
					var swap_cost: float = heap_cost[parent]
					var swap_node: int = heap_node[parent]
					heap_cost[parent] = heap_cost[child]
					heap_node[parent] = heap_node[child]
					heap_cost[child] = swap_cost
					heap_node[child] = swap_node
					child = parent
	# kind编码一次完成；平行数组排序避免为500个器官创建中间字典。
	var organ_ids: PackedInt32Array = PackedInt32Array()
	var organ_priority: PackedInt32Array = PackedInt32Array()
	var organ_resistance: PackedFloat64Array = PackedFloat64Array()
	var organ_base: PackedFloat64Array = PackedFloat64Array()
	for i in range(edge_count):
		var code: int = edge_code[i]
		var half: float = edge_lengths[i] * RESISTANCE[code] * 0.5
		var resistance: float = minf(distances[edge_a[i]], distances[edge_b[i]]) + half
		organ_ids.append(edge_ids[i])
		organ_priority.append(PRIORITY[code])
		organ_resistance.append(resistance)
		organ_base.append(NEED[code])
	for leaf in state.leaves.values():
		var need: float = 0.8
		if leaf.emergency:
			need = 0.0 if leaf.produced >= 18.0 else 0.2
		organ_ids.append(leaf.id)
		organ_priority.append(3)
		organ_resistance.append(distances[index_of[leaf.node]])
		organ_base.append(need)
	var order: Array = []
	order.resize(organ_ids.size())
	for i in range(order.size()):
		order[i] = i
	_sort_organs(order, organ_ids, organ_priority, organ_resistance)
	# sort_custom三级比较内联为迭代快排；id唯一使全序确定，结果与
	# (priority, resistance, id)字典序排序完全相同，无Callable逐元素调用。
	var result: Dictionary = {"q": q, "demand": 0.0, "spent": 0.0, "organs": {}}
	var remaining: float = q
	for pick in order:
		var id: int = organ_ids[pick]
		var base_need: float = organ_base[pick]
		var resistance: float = organ_resistance[pick]
		var demand: float = base_need * (1.0 + resistance)
		var spent: float = minf(remaining, demand)
		var delivered: float = spent / (1.0 + resistance)
		remaining -= spent
		result.demand += demand
		result.spent += spent
		result.organs[id] = {"r": delivered / base_need if base_need > 0.0 else 1.0,
			"resistance": resistance, "demand": demand, "delivered": delivered,
			"spent": spent, "base": base_need}
	return result

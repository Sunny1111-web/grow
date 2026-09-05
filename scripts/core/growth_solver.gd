extends RefCounted


static func build(state, env, node_id: int, kind: String, direction: Vector2) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "points": [], "anchor": {}}
	if not state.nodes.has(node_id) or direction.length_squared() < 0.0001:
		result.reason = "请从存活节点拖出一个方向"
		return result
	var start: Vector2 = state.nodes[node_id].pos
	var desired: Vector2 = direction.normalized()
	var stimulus: Vector2 = env.stimulus(state, start, kind)
	var influence: float = 0.22 if kind == "root" else 0.18
	var gravity: float = 0.08 if kind == "root" else 0.06
	var aim: Vector2 = (desired + influence * stimulus + Vector2(0, -gravity)).normalized()
	var limit: float = deg_to_rad(15.0 if kind == "root" else 12.0)
	# The ID is a deterministic candidate seed; no RNG state is consumed by preview.
	var variation: float = deg_to_rad(sin(float(state.next_id * 73 + node_id * 19)) * 3.0)
	var deviation: float = clampf(desired.angle_to(aim) + variation, -limit, limit)
	aim = desired.rotated(deviation)
	var tangent: Vector2 = aim
	var parent_id: int = state.nodes[node_id].parent_edge
	if state.edges.has(parent_id):
		var old: Array = state.edges[parent_id].points
		if old.size() >= 2:
			tangent = ((old[-1] - old[-2]).normalized() * 0.35 + aim * 0.65).normalized()
	var length: float = 0.8 if kind == "root" else 1.0
	var end: Vector2 = start + aim * length
	var p1: Vector2 = start + tangent * length * 0.3
	var p2: Vector2 = end - aim * length * 0.3
	var points: Array = []
	for _iteration in range(3):
		points = _sample(start, p1, p2, end)
		var scale: float = length / _length(points)
		p1 = start + (p1 - start) * scale
		p2 = start + (p2 - start) * scale
		end = start + (end - start) * scale
	points = _sample(start, p1, p2, end)
	if kind != "root":
		var anchor: Dictionary = env.anchor_at(points.back(), aim)
		if not anchor.is_empty():
			var surface_tangent: Vector2 = Vector2(-anchor.normal.y, anchor.normal.x)
			if surface_tangent.dot(aim) < 0.0:
				surface_tangent = -surface_tangent
			var attached: Array = _with_endpoint(start, tangent, surface_tangent, anchor.pos, length)
			if not attached.is_empty() and not env.blocked(attached, 0.04):
				points = attached
				result.anchor = anchor
	result.points = points
	if absf(_length(points) - length) > 0.01:
		result.reason = "这里无法容纳完整的一段生长"
		return result
	if kind == "root":
		if not env.root_allowed(points):
			result.reason = "根需要沿连续土壤或裂缝生长"
			return result
	else:
		if env.blocked(points, 0.04):
			result.reason = "前方有硬障碍，请调整方向"
			return result
	result.ok = true
	return result


static func _with_endpoint(start: Vector2, tangent: Vector2, aim: Vector2, end: Vector2, length: float) -> Array:
	if start.distance_to(end) > length + 0.00001:
		return []
	var low: float = 0.0
	var high: float = length * 0.9
	var points: Array = _sample(start, start + tangent * high, end - aim * high, end)
	if _length(points) < length:
		# 弦长接近段长时首样可能差一点点：延长把手上限再搜一次，
		# 让贴附支点的临界吸附（如阳台栏杆）成立；原有成功路径不受影响。
		low = high
		high = length * 1.35
		points = _sample(start, start + tangent * high, end - aim * high, end)
		if _length(points) < length:
			return []
	for _iteration in range(18):
		var handle: float = (low + high) * 0.5
		points = _sample(start, start + tangent * handle, end - aim * handle, end)
		if _length(points) > length:
			high = handle
		else:
			low = handle
	return points


static func _sample(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Array:
	var points: Array = []
	# Convex control polygon length bounds the Bezier length and sample span.
	var divisions: int = maxi(32, ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / 0.012))
	for index in range(divisions + 1):
		var t: float = float(index) / float(divisions)
		var v: float = 1.0 - t
		points.append(v * v * v * a + 3.0 * v * v * t * b + 3.0 * v * t * t * c + t * t * t * d)
	return points


static func _length(points: Array) -> float:
	var arc: float = 0.0
	for index in range(1, points.size()):
		arc += points[index - 1].distance_to(points[index])
	return arc

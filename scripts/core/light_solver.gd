extends RefCounted

const RAY_LENGTH: float = 64.0
const RADIUS_X: float = 0.2
const RADIUS_Y: float = 0.1
# 垂距超过椭圆长半轴必然不相交；留出裕量避免浮点临界剔除。
const PERPENDICULAR_LIMIT: float = 0.200001


static func solve(state, env) -> Dictionary:
	var shape_ids: Array = []
	var slot_of: Dictionary = {}
	var centers: PackedVector2Array = PackedVector2Array()
	var axes: Array[Vector2] = []
	var angles: PackedFloat64Array = PackedFloat64Array()
	for leaf in state.leaves.values():
		if leaf.z >= 24.0 or (leaf.emergency and leaf.produced >= 18.0):
			continue
		var axis: Vector2 = Vector2.from_angle(leaf.angle)
		slot_of[leaf.id] = shape_ids.size()
		shape_ids.append(leaf.id)
		centers.append(state.nodes[leaf.node].pos + axis * 0.16)
		axes.append(axis)
		angles.append(leaf.angle)
	var count: int = shape_ids.size()
	# 角度三角与所有光源无关，整体预计算一次。
	var cosines: PackedFloat64Array = PackedFloat64Array()
	var sines: PackedFloat64Array = PackedFloat64Array()
	for other in range(count):
		cosines.append(cos(angles[other]))
		sines.append(sin(angles[other]))
	# 真实环境预计算矩形走快速判定；测试替身保持 ray_blocked 调用契约。
	var rects: Array = []
	var fast_blocked: bool = env.get("obstacles") != null
	if fast_blocked:
		for obstacle in env.obstacles:
			rects.append(obstacle.rect.grow(-0.0001))
	var result: Dictionary = {}
	# 同一光源的所有叶共享方向预计算；压力场景100叶通常只落在少数光区。
	var rays_by_fixture: Dictionary = {}
	for leaf in state.leaves.values():
		if leaf.emergency:
			result[leaf.id] = {"light": 1.0, "transmission": 1.0, "intensity": 1.0}
			continue
		var index: int = slot_of.get(leaf.id, -1)
		if index < 0:
			result[leaf.id] = {"light": 0.0, "transmission": 0.0, "intensity": 0.0}
			continue
		var center: Vector2 = centers[index]
		var axis: Vector2 = axes[index]
		var fixture: Dictionary = env.light_at(center)
		var fixture_id = fixture.get("id", "")
		var rays = rays_by_fixture.get(fixture_id)
		if rays == null:
			var direction: Vector2 = fixture.direction.normalized()
			var dx: float = direction.x
			var dy: float = direction.y
			var ray_length: float = clampf(float(fixture.get("distance", RAY_LENGTH)), 0.0, RAY_LENGTH)
			var ray_x: PackedFloat64Array = PackedFloat64Array()
			var ray_y: PackedFloat64Array = PackedFloat64Array()
			ray_x.resize(count)
			ray_y.resize(count)
			for other in range(count):
				ray_x[other] = (dx * cosines[other] + dy * sines[other]) / RADIUS_X
				ray_y[other] = (-dx * sines[other] + dy * cosines[other]) / RADIUS_Y
			rays = {"direction": direction, "dx": dx, "dy": dy,
				"ray_length": ray_length, "ray_x": ray_x, "ray_y": ray_y}
			rays_by_fixture[fixture_id] = rays
		var direction: Vector2 = rays.direction
		var dx: float = rays.dx
		var dy: float = rays.dy
		var ray_length: float = rays.ray_length
		var ray_x: PackedFloat64Array = rays.ray_x
		var ray_y: PackedFloat64Array = rays.ray_y
		var total: float = 0.0
		for offset in [-0.1, 0.0, 0.1]:
			var origin: Vector2 = center + offset * axis
			var transmission: float = 0.0
			var blocked: bool
			if fast_blocked:
				blocked = _segment_blocked(origin, dx, dy, ray_length, rects)
			else:
				blocked = env.ray_blocked(origin, origin + direction * ray_length)
			if not blocked:
				transmission = 1.0
				var ox: float = origin.x
				var oy: float = origin.y
				for other in range(count):
					if other == index:
						continue
					var delta: Vector2 = centers[other] - origin
					if absf(dx * delta.y - dy * delta.x) > PERPENDICULAR_LIMIT:
						continue
					if _ellipse_hit(ox, oy, centers[other].x, centers[other].y,
							ray_x[other], ray_y[other], cosines[other], sines[other], ray_length):
						transmission *= 0.5
			total += transmission
		var mean: float = total / 3.0
		result[leaf.id] = {"light": fixture.intensity * mean,
			"transmission": mean, "intensity": fixture.intensity}
	return result


# 等价于 Environment.blocked([origin, origin + direction * ray_length], 0.0)：
# 任一矩形与线段相交即遮挡，slab 判定与 segment_interval 相同。
static func _segment_blocked(origin: Vector2, dx: float, dy: float,
		ray_length: float, rects: Array) -> bool:
	var fx: float = origin.x
	var fy: float = origin.y
	var tx: float = fx + dx * ray_length
	var ty: float = fy + dy * ray_length
	var seg_x: float = tx - fx
	var seg_y: float = ty - fy
	for rect in rects:
		var low: float = 0.0
		var high: float = 1.0
		var active: bool = true
		var position: Vector2 = rect.position
		var size: Vector2 = rect.size
		if absf(seg_x) < 0.0000001:
			if fx < position.x or fx > position.x + size.x:
				active = false
		else:
			var s0: float = (position.x - fx) / seg_x
			var s1: float = (position.x + size.x - fx) / seg_x
			low = maxf(low, minf(s0, s1))
			high = minf(high, maxf(s0, s1))
		if active and absf(seg_y) < 0.0000001:
			if fy < position.y or fy > position.y + size.y:
				active = false
		elif active:
			var t0: float = (position.y - fy) / seg_y
			var t1: float = (position.y + size.y - fy) / seg_y
			low = maxf(low, minf(t0, t1))
			high = minf(high, maxf(t0, t1))
		if active and low <= high:
			return true
	return false


# 与 _intersects 相同的椭圆-射线判定；起点在调用侧以三角分量展开。
static func _ellipse_hit(ox: float, oy: float, cx: float, cy: float,
		ray_x: float, ray_y: float, cosine: float, sine: float, ray_length: float) -> bool:
	var rel_x: float = ox - cx
	var rel_y: float = oy - cy
	var sx: float = (rel_x * cosine + rel_y * sine) / RADIUS_X
	var sy: float = (-rel_x * sine + rel_y * cosine) / RADIUS_Y
	var a: float = ray_x * ray_x + ray_y * ray_y
	var b: float = 2.0 * (sx * ray_x + sy * ray_y)
	var c: float = sx * sx + sy * sy - 1.0
	var discriminant: float = b * b - 4.0 * a * c
	if a < 0.000001 or discriminant < 0.0:
		return false
	var low: float = (-b - sqrt(discriminant)) / (2.0 * a)
	var high: float = (-b + sqrt(discriminant)) / (2.0 * a)
	return high > 0.00001 and low < ray_length


static func _intersects(origin: Vector2, direction: Vector2, shape: Dictionary, ray_length: float = RAY_LENGTH) -> bool:
	var start: Vector2 = (origin - shape.center).rotated(-shape.angle) / Vector2(0.2, 0.1)
	var ray: Vector2 = direction.rotated(-shape.angle) / Vector2(0.2, 0.1)
	var a: float = ray.dot(ray)
	var b: float = 2.0 * start.dot(ray)
	var c: float = start.dot(start) - 1.0
	var discriminant: float = b * b - 4.0 * a * c
	if a < 0.000001 or discriminant < 0.0:
		return false
	var low: float = (-b - sqrt(discriminant)) / (2.0 * a)
	var high: float = (-b + sqrt(discriminant)) / (2.0 * a)
	return high > 0.00001 and low < ray_length

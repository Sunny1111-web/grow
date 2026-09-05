extends RefCounted

# 关卡环境基类：通用查询逻辑（生根/碰撞/锚点/水源/光照/刺激/揭示）。
# 各关卡脚本通过 _init 提供数据（soils/obstacles/surfaces/waters/lights/
# clues/exit_rect/memory_position）与标识（level_id/title/bounds）。

var level_id: String = ""
var title: String = ""
var soils: Array = []
var obstacles: Array = []
var surfaces: Array = []
var waters: Array = []
var lights: Array = []
var clues: Array = []
var exit_rect: Rect2 = Rect2()
var memory_position: Vector2 = Vector2.ZERO
# 白盒/取景范围：growth_framing 与相机夹取使用，避免关卡硬编码坐标。
var bounds: Rect2 = Rect2(0, -4, 24, 14)


func root_allowed(points: Array, radius: float = 0.025) -> bool:
	for index in range(1, points.size()):
		var intervals: Array = []
		for soil in soils:
			var interval: Array = segment_interval(points[index - 1], points[index], soil.grow(-radius))
			if not interval.is_empty():
				intervals.append(interval)
		intervals.sort_custom(func(a, b): return a[0] < b[0])
		var covered: float = 0.0
		for interval in intervals:
			if interval[0] > covered + 0.000001:
				break
			covered = maxf(covered, interval[1])
		if covered < 0.999999:
			return false
	return points.size() >= 2


func blocked(points: Array, radius: float) -> bool:
	for obstacle in obstacles:
		var rect: Rect2 = obstacle.rect.grow(radius - 0.0001)
		for index in range(1, points.size()):
			if not segment_interval(points[index - 1], points[index], rect).is_empty():
				return true
	return false


func anchor_at(point: Vector2, direction: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = 0.120001
	for surface in surfaces:
		var tangent: Vector2 = (surface.b - surface.a).normalized()
		if absf(direction.normalized().dot(tangent)) < cos(deg_to_rad(25.0)):
			continue
		var normal: Vector2 = surface.get("normal", Vector2(-tangent.y, tangent.x))
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point - normal * 0.04, surface.a, surface.b) + normal * 0.04
		var distance: float = point.distance_to(closest)
		if distance < best_distance:
			best_distance = distance
			best = {"id": surface.id, "pos": closest, "normal": normal}
	return best


func water_contacts(state) -> Array:
	var result: Array = []
	for node in state.nodes.values():
		if node.kind != "root":
			continue
		for water in waters:
			if water.rect.has_point(node.pos):
				result.append({"node": node.id, "access_id": water.id,
					"aquifer_id": water.aquifer_id, "q": water.q})
	return result


func light_at(point: Vector2) -> Dictionary:
	var best: Dictionary = {"intensity": 0.0, "direction": Vector2(0, 1), "id": "dark", "distance": 64.0}
	for fixture in lights:
		if fixture.rect.has_point(point) and (fixture.intensity > best.intensity or
			(is_equal_approx(fixture.intensity, best.intensity) and fixture.id < best.id)):
			best = fixture
	return best


func ray_blocked(from: Vector2, to: Vector2) -> bool:
	return blocked([from, to], 0.0)


func stimulus(state, origin: Vector2, kind: String) -> Vector2:
	if kind == "vine":
		var nearest: Vector2 = Vector2.ZERO
		var distance: float = 4.5
		for fixture in lights:
			if fixture.intensity < 0.6:
				continue
			var delta: Vector2 = fixture.rect.get_center() - origin
			if delta.length() < distance:
				distance = delta.length()
				nearest = delta.normalized()
		return nearest
	var candidates: Array = []
	var connected: Dictionary = {}
	for access in water_contacts(state):
		connected[access.access_id] = true
	for water in waters:
		if not connected.has(water.id):
			candidates.append({"id": water.id, "pos": water.rect.get_center()})
	for clue in clues:
		if clue.id not in state.revealed:
			candidates.append(clue)
	var distance: float = 2.400001
	var direction: Vector2 = Vector2.ZERO
	for item in candidates:
		var delta: Vector2 = item.pos - origin
		if delta.length() < distance and delta.length() > 0.1:
			distance = delta.length()
			direction = delta.normalized()
	return direction


# 关卡目标提示：子关卡按自身进度改写；返回空串时调用方提供兜底文案。
func objective(state, metrics: Dictionary) -> String:
	return ""


func reveal(state, position: Vector2) -> void:
	state.explored.append(position)
	for item in clues:
		if item.pos.distance_to(position) <= 1.2 and item.id not in state.revealed:
			state.revealed.append(item.id)
	for item in waters:
		if item.rect.get_center().distance_to(position) <= 1.2 and item.id not in state.revealed:
			state.revealed.append(item.id)


static func segment_interval(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var low: float = 0.0
	var high: float = 1.0
	var delta: Vector2 = b - a
	for axis in range(2):
		if absf(delta[axis]) < 0.0000001:
			if a[axis] < rect.position[axis] or a[axis] > rect.end[axis]:
				return []
		else:
			var start: float = (rect.position[axis] - a[axis]) / delta[axis]
			var end: float = (rect.end[axis] - a[axis]) / delta[axis]
			low = maxf(low, minf(start, end))
			high = minf(high, maxf(start, end))
			if low > high:
				return []
	return [low, high]

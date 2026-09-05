extends RefCounted

var soils: Array = [Rect2(0, -4, 24, 3.85), Rect2(1.6, -0.4, 0.8, 0.85)]
var obstacles: Array = [
	{"id": "floor_left", "rect": Rect2(0, -0.15, 1.6, 0.55)},
	{"id": "floor_right", "rect": Rect2(2.4, -0.15, 21.6, 0.55)},
	{"id": "chair_seat", "rect": Rect2(3, 0.88, 3, 0.12)},
	{"id": "chair_leg_left", "rect": Rect2(3.05, 0.4, 0.12, 0.48)},
	{"id": "chair_leg_right", "rect": Rect2(5.8, 0.4, 0.12, 0.48)},
	{"id": "chair_back", "rect": Rect2(5.8, 1.0, 0.14, 0.5)},
	{"id": "table_top", "rect": Rect2(7, 3.26, 4, 0.24)},
	{"id": "table_leg_left", "rect": Rect2(7.15, 0.4, 0.16, 2.86)},
	{"id": "table_leg_right", "rect": Rect2(10.65, 0.4, 0.16, 2.86)},
	{"id": "window_lower", "rect": Rect2(16, 0.4, 0.22, 4.1)},
	{"id": "window_upper", "rect": Rect2(16, 7, 0.22, 3)},
	{"id": "left_wall", "rect": Rect2(-0.2, 0.4, 0.2, 9.6)}]
var surfaces: Array = [
	{"id": "chair_seat", "a": Vector2(3, 1), "b": Vector2(6, 1), "normal": Vector2(0, 1)},
	{"id": "chair_back", "a": Vector2(5.8, 1), "b": Vector2(5.8, 1.5), "normal": Vector2(-1, 0)},
	{"id": "table_left", "a": Vector2(7.15, 0.4), "b": Vector2(7.15, 3.26), "normal": Vector2(-1, 0)},
	{"id": "table_top", "a": Vector2(7, 3.5), "b": Vector2(11, 3.5), "normal": Vector2(0, 1)},
	{"id": "pipe", "a": Vector2(12.5, 1), "b": Vector2(12.5, 6.5), "normal": Vector2(-1, 0)},
	{"id": "window_sill", "a": Vector2(15.6, 4.5), "b": Vector2(16.5, 4.5), "normal": Vector2(0, 1)},
	{"id": "window_frame", "a": Vector2(16, 4.5), "b": Vector2(16, 7), "normal": Vector2(-1, 0)}]
var waters: Array = [
	{"id": "W1", "aquifer_id": "apartment", "q": 12.0, "rect": Rect2(1.7, -2.7, 0.6, 0.6)},
	{"id": "W2", "aquifer_id": "apartment", "q": 20.0, "rect": Rect2(7.65, -2.95, 0.7, 0.7)}]
var lights: Array = [
	{"id": "L1", "rect": Rect2(3.2, 1.0, 1.8, 1.5), "intensity": 0.6, "direction": Vector2(0, 1), "distance": 1.8},
	{"id": "L2", "rect": Rect2(8.5, 3.5, 2.5, 1.5), "intensity": 1.0, "direction": Vector2(1, 0.25).normalized(), "distance": 5.0},
	{"id": "L3", "rect": Rect2(11.0, 4.5, 6.4, 3.0), "intensity": 0.6, "direction": Vector2(1, 0), "distance": 4.5},
	{"id": "L4", "rect": Rect2(16.22, 4.5, 7.78, 5.5), "intensity": 1.0, "direction": Vector2(0, 1), "distance": 5.0},
	{"id": "ambient", "rect": Rect2(0, 0.4, 16, 9.6), "intensity": 0.2, "direction": Vector2(0, 1), "distance": 3.0}]
var clues: Array = [{"id": "C1", "pos": Vector2(3.6, -2.4)},
	{"id": "C2", "pos": Vector2(5.2, -2.5)}, {"id": "C3", "pos": Vector2(6.8, -2.6)}]
var exit_rect: Rect2 = Rect2(16.4, 5.8, 1.0, 1.0)
var memory_position: Vector2 = Vector2(8.5, 0.6)


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
	for water in waters:
		candidates.append({"id": water.id, "pos": water.rect.get_center()})
	for clue in clues:
		candidates.append(clue)
	var distance: float = 2.400001
	var direction: Vector2 = Vector2.ZERO
	for item in candidates:
		if item.id in state.revealed:
			continue
		var delta: Vector2 = item.pos - origin
		if delta.length() < distance and delta.length() > 0.1:
			distance = delta.length()
			direction = delta.normalized()
	return direction


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

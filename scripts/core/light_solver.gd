extends RefCounted

const RAY_LENGTH: float = 64.0


static func solve(state, env) -> Dictionary:
	var shapes: Dictionary = {}
	for leaf in state.leaves.values():
		if leaf.z >= 24.0 or (leaf.emergency and leaf.produced >= 18.0):
			continue
		var axis: Vector2 = Vector2.from_angle(leaf.angle)
		shapes[leaf.id] = {"center": state.nodes[leaf.node].pos + axis * 0.16,
			"axis": axis, "angle": leaf.angle}
	var result: Dictionary = {}
	for leaf in state.leaves.values():
		if leaf.emergency:
			result[leaf.id] = {"light": 1.0, "transmission": 1.0, "intensity": 1.0}
			continue
		if not shapes.has(leaf.id):
			result[leaf.id] = {"light": 0.0, "transmission": 0.0, "intensity": 0.0}
			continue
		var shape: Dictionary = shapes[leaf.id]
		var fixture: Dictionary = env.light_at(shape.center)
		var direction: Vector2 = fixture.direction.normalized()
		var total: float = 0.0
		for offset in [-0.1, 0.0, 0.1]:
			var origin: Vector2 = shape.center + offset * shape.axis
			var end: Vector2 = origin + direction * RAY_LENGTH
			var transmission: float = 0.0 if env.ray_blocked(origin, end) else 1.0
			if transmission > 0.0:
				for other_id in shapes:
					if other_id != leaf.id and _intersects(origin, direction, shapes[other_id]):
						transmission *= 0.5
			total += transmission
		var mean: float = total / 3.0
		result[leaf.id] = {"light": fixture.intensity * mean,
			"transmission": mean, "intensity": fixture.intensity}
	return result


static func _intersects(origin: Vector2, direction: Vector2, shape: Dictionary) -> bool:
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
	return high > 0.00001 and low < RAY_LENGTH

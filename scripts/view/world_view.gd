extends Node2D

var game
var camera: Vector2 = Vector2(6.5, 1.0)
var unit_scale: float = 80.0
var _speckles: Array = []

const WALL = Color("465b68")
const DARK = Color("17252f")
const GREEN = Color("6f9e62")
const BUD = Color("b4d184")
const LIGHT = Color("e7c46a")
const WATER = Color("67b8c6")
const LOST = Color("837262")


func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 271828
	for _i in range(340):
		_speckles.append([Vector2(rng.randf_range(0, 24), rng.randf_range(-4, 10)), rng.randf_range(0.006, 0.025), rng.randf()])


func to_screen(point: Vector2) -> Vector2:
	return get_viewport_rect().size * 0.5 + (point - camera) * Vector2(unit_scale, -unit_scale)


func from_screen(point: Vector2) -> Vector2:
	return camera + (point - get_viewport_rect().size * 0.5) / Vector2(unit_scale, -unit_scale)


func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before: Vector2 = from_screen(screen_point)
	unit_scale = clampf(unit_scale * factor, 50.0, 180.0)
	camera += before - from_screen(screen_point)
	clamp_camera()


func clamp_camera() -> void:
	camera.x = clampf(camera.x, 1.0, 20.0)
	camera.y = clampf(camera.y, -1.5, 7.0)


func ensure_visible(position: Vector2) -> void:
	var screen: Vector2 = to_screen(position)
	var viewport: Vector2 = get_viewport_rect().size
	var safe: Vector2 = Vector2(clampf(screen.x, 180, viewport.x - 180), clampf(screen.y, 160, viewport.y - 210))
	camera += (screen - safe) / Vector2(unit_scale, -unit_scale)
	clamp_camera()


func pick(screen_point: Vector2, mode: String) -> Dictionary:
	var all: Array = pick_all(screen_point, mode)
	return all[0] if not all.is_empty() else {}


func pick_all(screen_point: Vector2, mode: String) -> Array:
	var state = game.service.state
	var hits: Array = []
	if mode == "prune":
		for leaf in state.leaves.values():
			if leaf.emergency:
				continue
			var center: Vector2 = state.nodes[leaf.node].pos + Vector2.from_angle(leaf.angle) * 0.16
			var distance: float = to_screen(center).distance_to(screen_point)
			if distance <= maxf(15.0, unit_scale * 0.25):
				hits.append({"node": leaf.node, "leaf": leaf.id, "edge": 0, "distance": distance - 20.0})
	for node in state.nodes.values():
		var distance: float = to_screen(node.pos).distance_to(screen_point)
		if distance <= 19.0:
			hits.append({"node": node.id, "edge": node.parent_edge, "distance": distance})
	if mode in ["reinforce", "prune"]:
		for edge in state.edges.values():
			var distance: float = 1000000.0
			for index in range(1, edge.points.size()):
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(screen_point, to_screen(edge.points[index - 1]), to_screen(edge.points[index]))
				distance = minf(distance, closest.distance_to(screen_point))
			if distance <= 13.0:
				hits.append({"node": edge.b, "edge": edge.id, "distance": distance})
	hits.sort_custom(func(a, b): return a.distance < b.distance)
	return hits


func _draw() -> void:
	if game.service == null:
		return
	_background()
	var state = game.service.state
	if game.sensing:
		_sense()
	var history_start: int = maxi(0, state.history.size() - 200)
	for index in range(history_start, state.history.size()):
		var item: Dictionary = state.history[index]
		if item.type == "edge":
			_polyline(item.data.points, Color(0.51, 0.45, 0.38, 0.28), 0.025)
		else:
			_leaf(item.pos, item.data.angle - 0.5, 24.0, 0.3)
	for scar in state.scars.values():
		draw_arc(to_screen(scar.pos), unit_scale * 0.1, -0.5, 2.8, 12, LOST, 2, true)
	for edge in state.edges.values():
		var points: Array = edge.points
		if edge.id == game.growing_edge and game.animation_remaining > 0.0:
			var shown: int = maxi(2, int(points.size() * (1.0 - game.animation_remaining / 0.6)))
			points = points.slice(0, shown)
		var color: Color = GREEN
		var width: float = 0.065
		if edge.kind == "root":
			color = Color("bcae88")
			width = 0.038
		elif edge.kind == "branch":
			color = Color("89946e")
			width = 0.11
		if edge.z >= 6.0:
			color = color.lerp(LOST, clampf(edge.z / 24.0, 0.0, 1.0))
		_polyline(points, Color(0.03, 0.08, 0.075, 0.8), width + 0.035)
		_polyline(points, color, width)
		if edge.kind == "root":
			_root_hairs(points, color)
		if not state.nodes[edge.b].anchor.is_empty():
			draw_arc(to_screen(state.nodes[edge.b].pos), unit_scale * 0.11, 0.2, 5.8, 20, BUD, 2, true)
		if game.sensing and game.sim.metrics.water.organs.has(edge.id):
			var ratio: float = game.sim.metrics.water.organs[edge.id].r
			_polyline(points, Color(WATER, 0.75 * ratio), 0.018)
	for leaf in state.leaves.values():
		var position: Vector2 = state.nodes[leaf.node].pos
		if leaf.emergency:
			position += Vector2(0, 0.15)
		var wave: float = sin(Time.get_ticks_msec() * 0.0016 + leaf.id) * 0.025
		_leaf(position, leaf.angle + wave, leaf.z, 0.45 if leaf.emergency and leaf.produced >= 18.0 else 1.0)
	var seed: Vector2 = state.nodes[state.seed_id].pos
	draw_circle(to_screen(seed), 0.14 * unit_scale, Color("bfab78"))
	draw_arc(to_screen(seed), 0.14 * unit_scale, 0.5, 3.2, 12, Color("e6d1a1"), 2.0, true)
	for node in state.nodes.values():
		if node.emergency:
			continue
		var position: Vector2 = to_screen(node.pos)
		if node.id == game.selected_node:
			draw_arc(position, 0.23 * unit_scale, 0, TAU, 32, Color(BUD, 0.7), 1.5, true)
			draw_circle(position, 5.0, BUD)
		elif game.selected_tool in ["root", "vine", "leaf"]:
			draw_circle(position, 3.5, Color(BUD, 0.65))
	_preview()
	if game.memory_remaining > 0.0:
		_memory_glow()


func _background() -> void:
	draw_rect(get_viewport_rect(), Color("17252f"))
	_rect(Rect2(0, 0.4, 16.0, 9.6), WALL)
	for index in range(24):
		_rect(Rect2(0, 0.4 + index * 0.4, 16, 0.4), Color(0.02, 0.06, 0.08, (24 - index) * 0.012))
	# Tall panes expose a soft exterior; foreground collisions are drawn separately.
	_rect(Rect2(16.22, 4.5, 8, 5.5), Color("a4b5a7"))
	for index in range(10):
		_rect(Rect2(16.22, 4.5 + index * 0.55, 8, 0.55), Color(0.87, 0.85, 0.66, index * 0.034))
	_polygon([Vector2(17, 4.5), Vector2(17, 6.7), Vector2(17.4, 7.2), Vector2(17.8, 6.9), Vector2(18.1, 7.7), Vector2(18.8, 7.6), Vector2(19, 4.5)], Color("667e77"))
	_polygon([Vector2(19, 4.5), Vector2(19, 6.1), Vector2(19.3, 6.7), Vector2(20.2, 6.7), Vector2(20.2, 7.2), Vector2(21.5, 7.2), Vector2(21.5, 4.5)], Color("758e82"))
	_polygon([Vector2(16.2, 6.9), Vector2(16.2, 4.7), Vector2(6.0, 0.4), Vector2(2.2, 0.4)], Color(0.9, 0.78, 0.48, 0.075))
	_polygon([Vector2(16.2, 6.8), Vector2(16.2, 6.35), Vector2(9.7, 3.5), Vector2(8.4, 3.5)], Color(0.94, 0.86, 0.58, 0.1))
	# Faded wallpaper seams, fallen frames, and cracks establish the abandoned room.
	for x in range(1, 16, 2):
		_line(Vector2(x, 0.4), Vector2(x, 10), Color(0.75, 0.78, 0.73, 0.055), 0.016)
	_rect(Rect2(2.8, 4.6, 2.0, 1.5), Color("394d57"))
	_rect(Rect2(2.91, 4.71, 1.78, 1.28), Color("758280"))
	_polygon([Vector2(2.96, 4.75), Vector2(3.4, 5.23), Vector2(3.8, 5.1), Vector2(4.6, 5.85), Vector2(4.65, 4.75)], Color("596f69"))
	_polyline([Vector2(9.3, 8.8), Vector2(9.12, 7.6), Vector2(9.4, 7.2), Vector2(9.1, 6.5)], Color("344a55"), 0.02)
	_polyline([Vector2(9.12, 7.6), Vector2(8.8, 7.35), Vector2(8.5, 7.4)], Color("344a55"), 0.012)
	_rect(Rect2(0, -4, 24, 4.4), Color("1c292e"))
	for x in range(0, 24):
		_line(Vector2(x, -0.08), Vector2(x + 0.2, -0.2), Color("35474a"), 0.022)
	for speck in _speckles:
		var point: Vector2 = speck[0]
		var color: Color = Color(0.55, 0.6, 0.57, 0.09) if point.y > 0.4 else Color(0.56, 0.51, 0.4, 0.12)
		draw_circle(to_screen(point), maxf(0.6, speck[1] * unit_scale), color)
	for obstacle in game.service.env.obstacles:
		var color: Color = Color("28393f")
		if obstacle.id.begins_with("chair"):
			color = Color("72776b")
		elif obstacle.id.begins_with("table"):
			color = Color("6b7773")
		_rect(obstacle.rect, color)
		_line(obstacle.rect.position + Vector2(0, obstacle.rect.size.y), obstacle.rect.end, Color(color.lightened(0.15), 0.8), 0.025)
	_line(Vector2(12.5, 1), Vector2(12.5, 6.5), Color("354b53"), 0.13)
	_line(Vector2(12.47, 1), Vector2(12.47, 6.5), Color("89918a"), 0.045)
	for y in [1.5, 3.5, 5.6]:
		_line(Vector2(12.32, y), Vector2(12.67, y), Color("87918a"), 0.08)
	_line(Vector2(15.6, 4.5), Vector2(16.5, 4.5), Color("a2ab98"), 0.12)
	_line(Vector2(16, 4.5), Vector2(16, 7), Color("a2ab98"), 0.065)
	_line(Vector2(16, 7), Vector2(17.4, 7), Color("a2ab98"), 0.065)
	# The L1 reflected patch makes the first income source readable without an overlay.
	_polygon([Vector2(3.2, 1.02), Vector2(5.0, 1.02), Vector2(4.95, 2.5), Vector2(3.7, 2.2)], Color(0.87, 0.78, 0.47, 0.07))
	_line(Vector2(3.3, 1.03), Vector2(5, 1.03), Color(LIGHT, 0.4), 0.025)
	# One old watering can — the optional memory object.
	_polygon([Vector2(8.18, 0.43), Vector2(8.12, 0.94), Vector2(8.62, 0.94), Vector2(8.7, 0.45)], Color("526f70"))
	_polyline([Vector2(8.67, 0.55), Vector2(8.98, 1.02), Vector2(9.14, 1.08)], Color("526f70"), 0.12)
	draw_arc(to_screen(Vector2(8.08, 0.73)), unit_scale * 0.24, 1.1, 5.1, 18, Color("526f70"), 0.045 * unit_scale, true)
	_polyline([Vector2(2.0, -0.8), Vector2(1.94, -0.25), Vector2(2.12, 0.03), Vector2(2.03, 0.39)], Color("080f15"), 0.13)
	for water in game.service.env.waters:
		if water.id in game.service.state.revealed:
			var center: Vector2 = water.rect.get_center()
			for ring in range(4, 0, -1):
				draw_circle(to_screen(center), ring * 0.12 * unit_scale, Color(WATER, 0.025 * (5 - ring)))
			_line(center + Vector2(-0.22, 0), center + Vector2(0.22, 0.02), Color(WATER, 0.8), 0.05)


func _sense() -> void:
	for fixture in game.service.env.lights:
		if fixture.intensity >= 0.6:
			_rect(fixture.rect, Color(LIGHT, 0.085))
	for surface in game.service.env.surfaces:
		_line(surface.a, surface.b, Color(BUD, 0.5), 0.025)
	for point in game.service.state.explored:
		draw_arc(to_screen(point), unit_scale * 1.2, 0, TAU, 48, Color(WATER, 0.07), 1.0, true)
	for clue in game.service.env.clues:
		if clue.id in game.service.state.revealed:
			draw_circle(to_screen(clue.pos), 0.065 * unit_scale, WATER)
	var selected: Dictionary = game.service.state.nodes.get(game.selected_node, game.service.state.nodes[1])
	var direction: Vector2 = game.service.env.stimulus(game.service.state, selected.pos, "root" if selected.kind in ["root", "seed"] else "vine")
	if direction != Vector2.ZERO:
		var end: Vector2 = selected.pos + direction * 0.65
		_line(selected.pos + direction * 0.28, end, WATER, 0.025)
		_line(end, end - direction.rotated(0.6) * 0.16, WATER, 0.025)
		_line(end, end - direction.rotated(-0.6) * 0.16, WATER, 0.025)


func _preview() -> void:
	var proposal: Dictionary = game.proposal
	if proposal.is_empty():
		return
	var color: Color = BUD if proposal.ok else Color("d79b67")
	if proposal.get("points", []).size() > 1:
		_polyline(proposal.points, Color(color, 0.2), 0.18)
		_polyline(proposal.points, color, 0.035)
		draw_arc(to_screen(proposal.points.back()), 0.12 * unit_scale, 0, TAU, 20, color, 1.5, true)
	if proposal.ok and proposal.kind.begins_with("prune"):
		for edge in game.service.state.edges.values():
			if not proposal.candidate.edges.has(edge.id):
				_polyline(edge.points, Color(0.88, 0.62, 0.38, 0.8), 0.11)
	if proposal.ok and proposal.kind == "leaf":
		var node: Dictionary = game.service.state.nodes[proposal.target]
		_leaf(node.pos, game.service.env.light_at(node.pos).direction.angle(), 0, 0.65)
	if proposal.ok and proposal.kind == "reinforce":
		_polyline(game.service.state.edges[proposal.edge].points, Color(BUD, 0.75), 0.14)


func _leaf(position: Vector2, angle: float, z: float, alpha: float = 1.0) -> void:
	var color: Color = GREEN
	var width: float = 0.11
	if z >= 6.0:
		color = Color("9b9c61")
		angle -= 0.3
	if z >= 12.0:
		color = Color("a08a61")
		width = 0.045
		angle -= 0.35
	if z >= 24.0:
		color = LOST
		width = 0.028
	var center: Vector2 = position + Vector2.from_angle(angle) * 0.16
	var shape: Array = []
	for index in range(24):
		var phase: float = float(index) / 24.0 * TAU
		shape.append(center + Vector2(cos(phase) * 0.21, sin(phase) * width).rotated(angle))
	_polygon(shape, Color(color, alpha))
	_polyline(shape + [shape[0]], Color(color.lightened(0.18), alpha * 0.7), 0.012)
	_line(position, center + Vector2.from_angle(angle) * 0.18, Color(BUD, alpha * 0.7), 0.012)
	for step in [-0.08, 0.0, 0.08]:
		var stem: Vector2 = center + Vector2(step, 0).rotated(angle)
		_line(stem, stem + Vector2(0.04, width * 0.7).rotated(angle), Color(BUD, alpha * 0.35), 0.006)
		_line(stem, stem + Vector2(0.04, -width * 0.7).rotated(angle), Color(BUD, alpha * 0.35), 0.006)


func _root_hairs(points: Array, color: Color) -> void:
	for index in range(7, points.size() - 1, 13):
		var direction: Vector2 = (points[index] - points[index - 1]).normalized()
		var side: float = 1.0 if index % 2 == 0 else -1.0
		_line(points[index], points[index] + direction.rotated(side * 1.1) * 0.10, Color(color, 0.6), 0.011)


func _rect(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(to_screen(Vector2(rect.position.x, rect.end.y)), rect.size * unit_scale), color)


func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(to_screen(a), to_screen(b), color, maxf(0.7, width * unit_scale), true)


func _polyline(points: Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var screen: PackedVector2Array = []
	for point in points:
		screen.append(to_screen(point))
	draw_polyline(screen, color, maxf(0.7, width * unit_scale), true)


func _polygon(points: Array, color: Color) -> void:
	var screen: PackedVector2Array = []
	for point in points:
		screen.append(to_screen(point))
	draw_colored_polygon(screen, color)


func growth_framing() -> Dictionary:
	var low: Vector2 = Vector2(1.0, -2.8)
	var high: Vector2 = Vector2(20.0, 7.5)
	for node in game.service.state.nodes.values():
		low = low.min(node.pos - Vector2(0.5, 0.5))
		high = high.max(node.pos + Vector2(0.5, 0.5))
	var available: Vector2 = get_viewport_rect().size - Vector2(150, 320)
	var scale: float = clampf(minf(available.x / (high.x - low.x), available.y / (high.y - low.y)), 40.0, 90.0)
	return {"camera": (low + high) * 0.5 + Vector2(0, -20.0 / scale), "scale": scale}


func _memory_glow() -> void:
	var fade: float = minf(1.0, game.memory_remaining) * minf(1.0, (5.0 - game.memory_remaining) * 2.0)
	var position: Vector2 = game.service.env.memory_position
	for ring in range(8, 0, -1):
		draw_circle(to_screen(position + Vector2(0, 0.3)), unit_scale * ring * 0.14, Color(LIGHT, 0.018 * fade))
	for drop in range(3):
		var phase: float = fmod((5.0 - game.memory_remaining) * 0.8 + drop * 0.3, 1.0)
		var point: Vector2 = position + Vector2(0.6 + phase * 0.2, 0.5 - phase * 0.45)
		draw_circle(to_screen(point), unit_scale * 0.025, Color(WATER, fade * (1.0 - phase)))

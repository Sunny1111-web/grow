extends Node2D

const HistorySlots = preload("res://scripts/view/history_slots.gd")
const BackgroundLayer = preload("res://scripts/view/background_layer.gd")
const GrowthLayer = preload("res://scripts/view/growth_layer.gd")
const OverlayLayer = preload("res://scripts/view/overlay_layer.gd")

var game
var camera: Vector2 = Vector2(6.5, 1.0)
var unit_scale: float = 80.0
var _speckles: Array = []
var _slots_cache: Dictionary = {"merged": false, "batched_count": 0, "batches": [], "items": []}
var _slots_history_size: int = -1
var _slots_environment_key: Array = []
var background_layer
var growth_layer
var overlay_layer
# 当前绘制目标：层脚本在自身_draw中把brush指向自己，复用world的绘制辅助。
var brush: CanvasItem = self

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
	# 分层缓存：背景仅在相机/揭示变化时重绘，植物层与模拟同频10Hz，覆盖层随父每帧。
	background_layer = BackgroundLayer.new()
	background_layer.world = self
	add_child(background_layer)
	growth_layer = GrowthLayer.new()
	growth_layer.world = self
	add_child(growth_layer)
	overlay_layer = OverlayLayer.new()
	overlay_layer.world = self
	add_child(overlay_layer)


func _process(delta: float) -> void:
	if game == null or game.service == null:
		return
	_update_history_slots(game.service.state)
	background_layer.sync()
	growth_layer.sync()


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
	if game != null and game.service != null and game.service.env.level_id != "apartment":
		var bounds: Rect2 = game.service.env.bounds
		camera = camera.clamp(bounds.position, bounds.end)
		return
	camera.x = clampf(camera.x, 1.0, 20.0)
	camera.y = clampf(camera.y, -1.5, 7.0)


# 实例身份使重开同一章也刷新；关卡标识可识别原地切换环境的调用方。
func environment_key() -> Array:
	return [game.service.env.get_instance_id(), game.service.env.level_id]


# 绘制直接消费碰撞、支点、资源与出口的真实数据，避免维护第二份场景坐标。
func whitebox_geometry() -> Dictionary:
	var env = game.service.env
	return {"obstacles": env.obstacles, "surfaces": env.surfaces,
		"lights": env.lights, "waters": env.waters, "bounds": env.bounds,
		"exit_rect": env.exit_rect}



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
	pass


# 剪叶预览的高亮数据：被剪普通叶的挂点位置，供绘制与测试共用。
func cut_highlight(proposal: Dictionary) -> Array:
	var positions: Array = []
	if not proposal.get("ok", false) or proposal.get("kind", "") != "prune_leaf":
		return positions
	var state = game.service.state
	if state.leaves.has(proposal.target):
		positions.append(state.nodes[state.leaves[proposal.target].node].pos)
	return positions


# 结构风险累积中的枝条（bend>0即开始吃力），供危险描边与测试共用。
func danger_edge_ids() -> Array:
	var result: Array = []
	for edge in game.service.state.edges.values():
		if edge.bend > 0.01:
			result.append(edge.id)
	return result


func _draw_history(state) -> void:
	for batch in _slots_cache.batches:
		var screen_lines: PackedVector2Array = PackedVector2Array()
		screen_lines.resize(batch.lines.size())
		for i in range(batch.lines.size()):
			screen_lines[i] = to_screen(batch.lines[i])
		brush.draw_multiline(screen_lines, Color(0.51, 0.45, 0.38, 0.22), maxf(0.7, 0.03 * unit_scale), true)
	for item in _slots_cache.items:
		if item.type == "edge":
			_polyline(item.data.points, Color(0.51, 0.45, 0.38, 0.28), 0.025)
		else:
			_leaf(item.pos, item.data.angle - 0.5, 24.0, 0.3)


func _draw_scars(state) -> void:
	for scar in state.scars.values():
		brush.draw_arc(to_screen(scar.pos), unit_scale * 0.1, -0.5, 2.8, 12, LOST, 2, true)


func _draw_plant(state) -> void:
	var selection_path: Array = _selection_path_ids(state)
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
		if edge.bend > 0.01:
			# 结构吃力警示：风险累积中的枝叠加暖色描边，与缺水色分开。
			_polyline(points, Color("d79b67", clampf(edge.bend * 0.4, 0.15, 0.6)), width * 0.4)
		if edge.kind == "root":
			_root_hairs(points, color)
		if not state.nodes[edge.b].anchor.is_empty():
			brush.draw_arc(to_screen(state.nodes[edge.b].pos), unit_scale * 0.11, 0.2, 5.8, 20, BUD, 2, true)
		if game.sensing and game.sim.metrics.water.organs.has(edge.id):
			var ratio: float = game.sim.metrics.water.organs[edge.id].r
			_polyline(points, Color(WATER, 0.75 * ratio), 0.018)
			# 选中供水路径：从选中节点到种子的父链加亮加粗，一眼可辨。
			if edge.id in selection_path:
				_polyline(points, Color(WATER, 0.95), 0.038)
	for leaf in state.leaves.values():
		var position: Vector2 = state.nodes[leaf.node].pos
		if leaf.emergency:
			position += Vector2(0, 0.15)
		var wave: float = leaf_wave(leaf.id)
		_leaf(position, leaf.angle + wave, leaf.z, 0.45 if leaf.emergency and leaf.produced >= 18.0 else 1.0)
		# 遮光标记：感知中给光照不足的普通叶画一圈冷灰细环，与缺水/承重区分。
		if game.sensing and not leaf.emergency and game.sim.metrics.light.has(leaf.id):
			if game.sim.metrics.light[leaf.id].light < 0.3:
				brush.draw_arc(to_screen(position + Vector2.from_angle(leaf.angle) * 0.16),
					unit_scale * 0.3, 0, TAU, 24, Color(0.62, 0.68, 0.72, 0.85), 1.5, true)


# 叶片摆动幅度：低动态设置下归零，感知/预览等暂停时也不摆动。
func leaf_wave(leaf_id: int) -> float:
	if game.low_motion:
		return 0.0
	return sin(Time.get_ticks_msec() * 0.0016 + leaf_id) * 0.025


# 选中节点到种子的父边链（感知高亮供水路径的数据源，与绘制共用）。
func _selection_path_ids(state) -> Array:
	if not game.sensing or not state.nodes.has(game.selected_node):
		return []
	return state.parent_chain(game.selected_node)


func selection_path_ids() -> Array:
	return _selection_path_ids(game.service.state)


# 遮光叶清单：普通叶光照 < 0.3，供测试与绘制共用。
func shaded_leaf_ids() -> Array:
	var result: Array = []
	if not game.sensing:
		return result
	for leaf in game.service.state.leaves.values():
		if leaf.emergency:
			continue
		if game.sim.metrics.light.has(leaf.id) and game.sim.metrics.light[leaf.id].light < 0.3:
			result.append(leaf.id)
	return result


func _draw_water_waves(state) -> void:
	for water in game.service.env.waters:
		if water.id in state.revealed:
			var center: Vector2 = water.rect.get_center()
			var phase: float = Time.get_ticks_msec() * 0.002
			for wave in range(3):
				var sway: float = 0.0 if game.low_motion else sin(phase + wave * 2.1) * 0.045
				_line(center + Vector2(-0.2 + sway, wave * 0.08 - 0.08),
					center + Vector2(0.2 - sway, wave * 0.08 - 0.07), Color(WATER, 0.22), 0.014)


func _draw_seed_and_nodes(state) -> void:
	var seed: Vector2 = state.nodes[state.seed_id].pos
	brush.draw_circle(to_screen(seed), 0.14 * unit_scale, Color("bfab78"))
	brush.draw_arc(to_screen(seed), 0.14 * unit_scale, 0.5, 3.2, 12, Color("e6d1a1"), 2.0, true)


func _draw_selection() -> void:
	var state = game.service.state
	for node in state.nodes.values():
		if node.emergency:
			continue
		var position: Vector2 = to_screen(node.pos)
		if node.id == game.selected_node:
			brush.draw_arc(position, 0.23 * unit_scale, 0, TAU, 32, Color(BUD, 0.7), 1.5, true)
			brush.draw_circle(position, 5.0, BUD)
		elif game.selected_tool in ["root", "vine", "leaf"]:
			brush.draw_circle(position, 3.5, Color(BUD, 0.65))


# 引导目标世界提示：教学前两步（选中种子/拖根）在种子外画呼吸金圈。
func _draw_guide_hint() -> void:
	if not game.guide_active:
		return
	var step: int = int(game.service.state.guide.get("step", 0))
	if step > 1:
		return
	var state = game.service.state
	var position: Vector2 = to_screen(state.nodes[state.seed_id].pos)
	if game.low_motion:
		brush.draw_arc(position, 0.34 * unit_scale, 0, TAU, 32, Color(LIGHT, 0.55), 2.0, true)
		brush.draw_arc(position, 0.46 * unit_scale, 0, TAU, 32, Color(LIGHT, 0.3), 1.5, true)
		return
	var pulse: float = 0.34 + 0.09 * sin(Time.get_ticks_msec() / 1000.0 * 3.2)
	brush.draw_arc(position, pulse * unit_scale, 0, TAU, 32, Color(LIGHT, 0.8), 2.5, true)


# 常态氛围层（背景层调用）：光区径向光晕，纯叠加绘制；低动态时单圈淡光。
func _atmosphere(state) -> void:
	for fixture in game.service.env.lights:
		if fixture.id == "ambient" or fixture.intensity < 0.3:
			continue
		var center: Vector2 = fixture.rect.get_center()
		var radius: float = maxf(fixture.rect.size.x, fixture.rect.size.y) * 0.5
		if game.low_motion:
			brush.draw_circle(to_screen(center), unit_scale * radius,
				Color(LIGHT, 0.03 * fixture.intensity))
			continue
		for ring in range(6, 0, -1):
			brush.draw_circle(to_screen(center), unit_scale * radius * ring / 6.0,
				Color(LIGHT, 0.011 * fixture.intensity * (7 - ring)))


func _update_history_slots(state) -> void:
	var identity: Array = environment_key()
	if _slots_environment_key == identity and _slots_history_size == state.history.size():
		return
	_slots_cache = HistorySlots.compute(state.history)
	_slots_history_size = state.history.size()
	_slots_environment_key = identity
	if _slots_cache.merged and game.has_method("notice_history_merged"):
		game.notice_history_merged(_slots_cache.batched_count)


# 背景按关卡分派：第一关保留原空房间装饰，其余关卡走通用白盒绘制。
func _background() -> void:
	if game.service.env.level_id == "apartment":
		_background_apartment()
	else:
		_background_generic()
	_draw_obstacles_and_waters()
	if game.service.env.level_id != "apartment":
		_draw_whitebox_supports()


func _background_generic() -> void:
	brush.draw_rect(get_viewport_rect(), Color("1a2530"))
	var geometry: Dictionary = whitebox_geometry()
	var bounds: Rect2 = geometry.bounds
	_rect(bounds, Color("3d5566"))
	var ground: float = clampf(0.4, bounds.position.y, bounds.end.y)
	_rect(Rect2(bounds.position, Vector2(bounds.size.x, ground - bounds.position.y)), Color("1c292e"))
	for fixture in geometry.lights:
		if fixture.id != "ambient":
			_rect(fixture.rect, Color(LIGHT, fixture.intensity * 0.055))
	for speck in _speckles:
		if bounds.has_point(speck[0]):
			brush.draw_circle(to_screen(speck[0]), maxf(0.6, speck[1] * unit_scale), Color(0.55, 0.6, 0.57, 0.09))


# 支点在实体之后描边；斜板和下沿全部对应真实可攀附线段。
func _draw_whitebox_supports() -> void:
	var geometry: Dictionary = whitebox_geometry()
	for surface in geometry.surfaces:
		_line(surface.a, surface.b, Color("17252f"), 0.13)
		_line(surface.a, surface.b, Color("a8b68c"), 0.065)
		_line(surface.a, surface.b, Color(BUD, 0.85), 0.018)
		for point in [surface.a, surface.b]:
			brush.draw_circle(to_screen(point), maxf(2.0, unit_scale * 0.045), BUD)
	var exit: Rect2 = geometry.exit_rect
	_rect(exit, Color(LIGHT, 0.22))
	_polyline([exit.position, Vector2(exit.position.x, exit.end.y), exit.end,
		Vector2(exit.end.x, exit.position.y), exit.position], Color(LIGHT, 0.9), 0.035)
	brush.draw_string(ThemeDB.fallback_font, to_screen(Vector2(exit.position.x, exit.end.y)) + Vector2(0, -12),
		"出口 · 向光生长", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LIGHT)


func _draw_obstacles_and_waters() -> void:
	var geometry: Dictionary = whitebox_geometry()
	for obstacle in geometry.obstacles:
		var color: Color = Color("28393f")
		if obstacle.id.begins_with("chair"):
			color = Color("72776b")
		elif obstacle.id.begins_with("table"):
			color = Color("6b7773")
		elif obstacle.id.begins_with("rail") or obstacle.id.begins_with("post"):
			color = Color("5f6b60")
		elif obstacle.id.begins_with("beam"):
			color = Color("6b5f4a")
		elif obstacle.id.begins_with("floor") or obstacle.id.begins_with("wall"):
			color = Color("465b68")
		_rect(obstacle.rect, color)
		_line(obstacle.rect.position + Vector2(0, obstacle.rect.size.y), obstacle.rect.end, Color(color.lightened(0.15), 0.8), 0.025)
	for water in geometry.waters:
		if water.id in game.service.state.revealed:
			var center: Vector2 = water.rect.get_center()
			for ring in range(4, 0, -1):
				brush.draw_circle(to_screen(center), ring * 0.12 * unit_scale, Color(WATER, 0.025 * (5 - ring)))
			_line(center + Vector2(-0.22, 0), center + Vector2(0.22, 0.02), Color(WATER, 0.8), 0.05)


func _background_apartment() -> void:
	var env = game.service.env
	brush.draw_rect(get_viewport_rect(), Color("17252f"))
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
		brush.draw_circle(to_screen(point), maxf(0.6, speck[1] * unit_scale), color)
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
	brush.draw_arc(to_screen(Vector2(8.08, 0.73)), unit_scale * 0.24, 1.1, 5.1, 18, Color("526f70"), 0.045 * unit_scale, true)
	_polyline([Vector2(2.0, -0.8), Vector2(1.94, -0.25), Vector2(2.12, 0.03), Vector2(2.03, 0.39)], Color("080f15"), 0.13)


func _sense() -> void:
	for fixture in game.service.env.lights:
		if fixture.intensity >= 0.6:
			_rect(fixture.rect, Color(LIGHT, 0.085))
	for surface in game.service.env.surfaces:
		_line(surface.a, surface.b, Color(BUD, 0.5), 0.025)
	for point in game.service.state.explored:
		brush.draw_arc(to_screen(point), unit_scale * 1.2, 0, TAU, 48, Color(WATER, 0.07), 1.0, true)
	for clue in game.service.env.clues:
		if clue.id in game.service.state.revealed:
			brush.draw_circle(to_screen(clue.pos), 0.065 * unit_scale, WATER)
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
		brush.draw_arc(to_screen(proposal.points.back()), 0.12 * unit_scale, 0, TAU, 20, color, 1.5, true)
	if proposal.ok and proposal.kind.begins_with("prune"):
		for edge in game.service.state.edges.values():
			if not proposal.candidate.edges.has(edge.id):
				_polyline(edge.points, Color(0.88, 0.62, 0.38, 0.8), 0.11)
		for position in cut_highlight(proposal):
			brush.draw_arc(to_screen(position), 0.3 * unit_scale, 0, TAU, 24, Color("d79b67"), 2.0, true)
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
	brush.draw_rect(Rect2(to_screen(Vector2(rect.position.x, rect.end.y)), rect.size * unit_scale), color)


func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	brush.draw_line(to_screen(a), to_screen(b), color, maxf(0.7, width * unit_scale), true)


func _polyline(points: Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var screen: PackedVector2Array = []
	for point in points:
		screen.append(to_screen(point))
	brush.draw_polyline(screen, color, maxf(0.7, width * unit_scale), true)


func _polygon(points: Array, color: Color) -> void:
	var screen: PackedVector2Array = []
	for point in points:
		screen.append(to_screen(point))
	brush.draw_colored_polygon(screen, color)


func growth_framing() -> Dictionary:
	var bounds: Rect2 = game.service.env.bounds
	if game.service.env.level_id != "apartment":
		var available_size: Vector2 = (get_viewport_rect().size - Vector2(150, 320)).max(Vector2(1, 1))
		var fitted_scale: float = maxf(1.0, minf(available_size.x / bounds.size.x, available_size.y / bounds.size.y))
		return {"camera": bounds.get_center(), "scale": fitted_scale}
	var low: Vector2 = bounds.position + Vector2(1.0, 1.2)
	var high: Vector2 = bounds.end - Vector2(4.0, 2.0)
	for node in game.service.state.nodes.values():
		low = low.min(node.pos - Vector2(0.5, 0.5))
		high = high.max(node.pos + Vector2(0.5, 0.5))
	var available: Vector2 = get_viewport_rect().size - Vector2(150, 320)
	var scale: float = clampf(minf(available.x / (high.x - low.x), available.y / (high.y - low.y)), 40.0, 90.0)
	return {"camera": (low + high) * 0.5 + Vector2(0, -20.0 / scale), "scale": scale}


func _memory_glow() -> void:
	var fade: float = minf(1.0, game.memory_remaining) * minf(1.0, (5.0 - game.memory_remaining) * 2.0)
	var position: Vector2 = game.service.env.memory_position
	if game.low_motion:
		brush.draw_circle(to_screen(position + Vector2(0, 0.3)), unit_scale * 0.8, Color(LIGHT, 0.05 * fade))
		return
	for ring in range(8, 0, -1):
		brush.draw_circle(to_screen(position + Vector2(0, 0.3)), unit_scale * ring * 0.14, Color(LIGHT, 0.018 * fade))
	for drop in range(3):
		var phase: float = fmod((5.0 - game.memory_remaining) * 0.8 + drop * 0.3, 1.0)
		var point: Vector2 = position + Vector2(0.6 + phase * 0.2, 0.5 - phase * 0.45)
		brush.draw_circle(to_screen(point), unit_scale * 0.025, Color(WATER, fade * (1.0 - phase)))

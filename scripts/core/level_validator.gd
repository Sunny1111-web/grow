extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const MIN_GAP: float = 0.08
const REVEAL_RADIUS: float = 1.2
const GROWTH_STEP: float = 0.8


static func validate(env) -> Array:
	return [_ids_unique(env), _light_direction(env), _water_in_soil(env),
		_key_points_clear(env), _no_thin_gap(env), _aquifer_consistent(env),
		_opening_root_reach(env), _opening_budget(), _rescue_route(env),
		_emergency_light_safe(env), _exit_not_single_span(env),
		_anchors_valid(env), _clue_chain(env)]


static func _ids_unique(env) -> Dictionary:
	# 同一实体可同时拥有碰撞矩形与锚点表面，二者共享ID合法；其余必须唯一。
	var duplicates: Array = []
	var structural: Dictionary = {}
	for item in env.obstacles:
		structural[item.get("id", "")] = true
	for item in env.surfaces:
		structural[item.get("id", "")] = true
	var seen: Dictionary = {}
	for collection in [env.waters, env.lights, env.clues]:
		for item in collection:
			var id = item.get("id", "")
			if id == "":
				duplicates.append("空ID")
			elif seen.has(id) or structural.has(id):
				duplicates.append(str(id))
			else:
				seen[id] = true
	if duplicates.is_empty():
		return _pass("ids_unique", "ID唯一(碰撞与锚点共享实体ID豁免)")
	return _fail("ids_unique", "ID重复或为空: " + ", ".join(duplicates))


static func _light_direction(env) -> Dictionary:
	for fixture in env.lights:
		var direction: Vector2 = fixture.direction
		if direction.length() < 0.0001 or not direction.is_finite():
			return _fail("light_direction", "光区 %s 未设方向" % fixture.id)
		if not is_finite(fixture.intensity) or fixture.intensity < 0.0:
			return _fail("light_direction", "光区 %s 强度非法" % fixture.id)
	return _pass("light_direction", "%d个光区方向与强度合法" % env.lights.size())


static func _water_in_soil(env) -> Dictionary:
	for water in env.waters:
		var inside: bool = false
		for soil in env.soils:
			if soil.intersects(water.rect):
				inside = true
		if not inside:
			return _fail("water_in_soil", "水点 %s 落在不可生根区域" % water.id)
	return _pass("water_in_soil", "%d个水点均在土壤内" % env.waters.size())


static func _key_points_clear(env) -> Dictionary:
	var points: Array = [
		["种子", Model.create().nodes[1].pos],
		["记忆水壶", env.memory_position]]
	for pair in points:
		for obstacle in env.obstacles:
			if obstacle.rect.has_point(pair[1]):
				return _fail("key_points_clear", "%s被装饰 %s 遮住" % [pair[0], obstacle.id])
	return _pass("key_points_clear", "种子与记忆位置无遮挡")


static func _no_thin_gap(env) -> Dictionary:
	for i in range(env.obstacles.size()):
		for j in range(i + 1, env.obstacles.size()):
			var a: Rect2 = env.obstacles[i].rect
			var b: Rect2 = env.obstacles[j].rect
			var overlap_y: float = minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
			var gap_x: float = maxf(a.position.x, b.position.x) - minf(a.end.x, b.end.x)
			if overlap_y > 0.0001 and gap_x > 0.0001 and gap_x < MIN_GAP:
				return _fail("no_thin_gap", "%s与%s存在%.3fu假缝隙(垂直通道)" %
					[env.obstacles[i].id, env.obstacles[j].id, gap_x])
			var overlap_x: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var gap_y: float = maxf(a.position.y, b.position.y) - minf(a.end.y, b.end.y)
			if overlap_x > 0.0001 and gap_y > 0.0001 and gap_y < MIN_GAP:
				return _fail("no_thin_gap", "%s与%s存在%.3fu假缝隙(水平通道)" %
					[env.obstacles[i].id, env.obstacles[j].id, gap_y])
	return _pass("no_thin_gap", "无小于%.2fu的假缝隙" % MIN_GAP)


static func _aquifer_consistent(env) -> Dictionary:
	for water in env.waters:
		if str(water.get("aquifer_id", "")) == "":
			return _fail("aquifer_consistent", "水点 %s 缺少含水层ID" % water.id)
	var by_id: Dictionary = {}
	for water in env.waters:
		by_id[water.id] = water
	if by_id.has("W1") and by_id.has("W2") and by_id.W1.aquifer_id != by_id.W2.aquifer_id:
		return _fail("aquifer_consistent", "W1/W2含水层ID不一致: %s != %s" %
			[by_id.W1.aquifer_id, by_id.W2.aquifer_id])
	return _pass("aquifer_consistent", "含水层ID一致")


static func _opening_root_reach(env) -> Dictionary:
	var seed: Vector2 = Model.create().nodes[1].pos
	var tip: Vector2 = seed
	for segment in range(2):
		var next: Vector2 = tip + Vector2(0, -0.8)
		if not env.root_allowed([tip, next]):
			return _fail("opening_root_reach", "第%d段首根离开土壤" % (segment + 1))
		tip = next
	for water in env.waters:
		if water.rect.has_point(tip):
			return _pass("opening_root_reach", "首根两段接水%s" % water.id)
	return _fail("opening_root_reach", "首根两段接水失败: 终点%s无水源" % str(tip))


static func _opening_budget() -> Dictionary:
	var initial: float = Model.create().energy
	var cost: float = 2.0 * 4.0 + 3.0 * 5.0 + 3.0
	if cost <= initial:
		return _pass("opening_budget", "开局26E≤初始%.0fE" % initial)
	return _fail("opening_budget", "初始%.0fE不能走完2根+3藤+1叶=%.0fE" % [initial, cost])


static func _rescue_route(env) -> Dictionary:
	var service = Commands.new(Model.create(), env)
	var rescue = service.preview("rescue", 1)
	if not rescue.ok:
		return _fail("rescue_route", "退守预览失败: " + rescue.reason)
	if not service.commit(rescue, "validate-rescue").ok:
		return _fail("rescue_route", "退守提交失败")
	# 应急子叶满产18E为预算上限；固定路线3藤(90/60/5°)15E+1叶3E恰好用尽。
	service.state.energy = 18.0
	var node: int = service.state.seed_id
	for degree in [90.0, 60.0, 5.0]:
		var proposal = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
		if not proposal.ok:
			return _fail("rescue_route", "应急路线藤%.0f°失败: %s" % [degree, proposal.reason])
		var result = service.commit(proposal, "validate-vine%.0f" % degree)
		if not result.ok:
			return _fail("rescue_route", "应急路线藤%.0f°提交失败: %s" % [degree, result.reason])
		node = result.node
	var leaf = service.preview("leaf", node)
	if not leaf.ok:
		return _fail("rescue_route", "应急路线叶失败: " + leaf.reason)
	if not service.commit(leaf, "validate-leaf").ok:
		return _fail("rescue_route", "应急路线叶提交失败")
	if service.state.energy < -0.0001:
		return _fail("rescue_route", "应急18E预算不足")
	var metrics: Dictionary = service.metrics()
	if metrics.income < 0.05:
		return _fail("rescue_route", "应急路线无持续产能")
	return _pass("rescue_route", "18E路线3藤1叶成立, 收入%.2fE/s" % metrics.income)


static func _emergency_light_safe(env) -> Dictionary:
	var seed: Vector2 = Model.create().nodes[1].pos
	var spot: Vector2 = seed + Vector2(0, 1.2)
	var fixture: Dictionary = env.light_at(spot)
	if fixture.intensity <= 0.0:
		return _fail("emergency_light_safe", "种子裂缝上方无有效光源")
	var direction: Vector2 = fixture.direction.normalized()
	var ray_length: float = clampf(float(fixture.get("distance", 64.0)), 0.0, 64.0)
	if env.ray_blocked(spot, spot + direction * ray_length):
		return _fail("emergency_light_safe", "首光被%s侧障碍遮挡" % fixture.id)
	return _pass("emergency_light_safe", "首光强度%.1f方向通畅" % fixture.intensity)


static func _exit_not_single_span(env) -> Dictionary:
	for surface in env.surfaces:
		if str(surface.id).begins_with("window"):
			continue
		var midpoint: Vector2 = (surface.a + surface.b) * 0.5
		var clamped: Vector2 = midpoint.clamp(env.exit_rect.position, env.exit_rect.end)
		var distance: float = midpoint.distance_to(clamped)
		if distance <= 1.0:
			return _fail("exit_not_single_span", "支点%s距出口%.2fu, 可被单段跨越" %
				[surface.id, distance])
	return _pass("exit_not_single_span", "出口不可被单段跨越")


static func _anchors_valid(env) -> Dictionary:
	for surface in env.surfaces:
		var span: Vector2 = surface.b - surface.a
		if span.length() < 0.001 or not span.is_finite():
			return _fail("anchors_valid", "支点%s线段退化" % surface.id)
		var normal: Vector2 = surface.get("normal", Vector2(-span.y, span.x).normalized())
		if not normal.is_finite() or absf(normal.length() - 1.0) > 0.01:
			return _fail("anchors_valid", "支点%s法线非单位向量" % surface.id)
	return _pass("anchors_valid", "%d个支点有效" % env.surfaces.size())


static func _clue_chain(env) -> Dictionary:
	var by_id: Dictionary = {}
	for water in env.waters:
		by_id[water.id] = water
	if not by_id.has("W1") or not by_id.has("W2"):
		return _pass("clue_chain", "无W1/W2水脉线索，检查跳过")
	var targets: Array = []
	for clue in env.clues:
		targets.append(clue.pos)
	targets.append(by_id.W2.rect.get_center())
	var position: Vector2 = by_id.W1.rect.get_center()
	var revealed: Dictionary = {}
	for _step in range(24):
		var found: bool = false
		for index in range(targets.size()):
			if not revealed.has(index) and position.distance_to(targets[index]) <= REVEAL_RADIUS + 0.000001:
				revealed[index] = true
				found = true
		if revealed.has(targets.size() - 1):
			return _pass("clue_chain", "W1→W2线索链%d步连续" % revealed.size())
		var direction: Vector2 = (targets[targets.size() - 1] - position).normalized()
		position += direction * GROWTH_STEP
		if not found and position.distance_to(targets[targets.size() - 1]) > REVEAL_RADIUS:
			var nearest: float = 1000000.0
			for index in range(targets.size()):
				if not revealed.has(index):
					nearest = minf(nearest, position.distance_to(targets[index]))
			if nearest > REVEAL_RADIUS:
				return _fail("clue_chain", "线索链在%s中断, 最近揭示目标%.2fu" % [str(position), nearest])
	return _fail("clue_chain", "线索链超过24步未抵达W2")


static func _pass(id: String, detail: String) -> Dictionary:
	return {"id": id, "ok": true, "detail": detail}


static func _fail(id: String, detail: String) -> Dictionary:
	return {"id": id, "ok": false, "detail": detail}

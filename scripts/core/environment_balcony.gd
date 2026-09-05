extends "res://scripts/core/level_base.gd"


# 第二章《断裂的阳台》白盒原型：学会取舍。
# 设计要点：光好（两处强光）但支点稀疏；中部断裂缺口 1.4u 无法单段跨越，
# 玩家选择 绕行下沿攀附 或 走斜板+强化跨越；W2 在缺口正下方，
# 修剪低效支路可把供水让给主干。美术留待白盒验证后再做。


func _init() -> void:
	level_id = "balcony"
	title = "第二章 · 断裂的阳台"
	bounds = Rect2(0, -4, 24, 12)
	soils = [Rect2(0, -4, 24, 3.85), Rect2(1.6, -0.4, 0.8, 0.85)]
	obstacles = [
		{"id": "floor_left", "rect": Rect2(0, -0.15, 1.6, 0.55)},
		{"id": "floor_right", "rect": Rect2(2.4, -0.15, 5.6, 0.55)},
		{"id": "floor_lower", "rect": Rect2(9.4, -0.55, 6.6, 0.55)},
		{"id": "post_a", "rect": Rect2(5.3, 0.4, 0.1, 0.7)},
		{"id": "post_b", "rect": Rect2(11.35, 0.0, 0.1, 0.9)},
		{"id": "wall", "rect": Rect2(16, 0.4, 0.3, 4.2)},
		{"id": "left_wall", "rect": Rect2(-0.2, 0.4, 0.2, 9.6)}]
	surfaces = [
		{"id": "rail_a", "a": Vector2(4.0, 1.1), "b": Vector2(5.4, 1.1), "normal": Vector2(0, 1)},
		{"id": "beam", "a": Vector2(7.3, 1.1), "b": Vector2(9.6, 0.7), "normal": Vector2(0.212, 0.977)},
		{"id": "lower_edge", "a": Vector2(9.4, 0.0), "b": Vector2(16.0, 0.0), "normal": Vector2(0, 1)},
		{"id": "planter", "a": Vector2(10.6, 0.9), "b": Vector2(12.2, 0.9), "normal": Vector2(0, 1)},
		{"id": "rail_b", "a": Vector2(13.2, 1.6), "b": Vector2(14.0, 1.6), "normal": Vector2(0, 1)},
		{"id": "wall_hook", "a": Vector2(14.5, 2.4), "b": Vector2(15.15, 2.9), "normal": Vector2(-0.55, 0.83).normalized()},
		{"id": "window_door", "a": Vector2(16.05, 4.6), "b": Vector2(16.05, 6.4), "normal": Vector2(-1, 0)}]
	waters = [
		{"id": "W1", "aquifer_id": "balcony", "q": 16.0, "rect": Rect2(1.7, -2.7, 0.6, 0.6)},
		{"id": "W2", "aquifer_id": "balcony", "q": 20.0, "rect": Rect2(8.2, -3.05, 0.7, 0.7)}]
	lights = [
		{"id": "morning", "rect": Rect2(1.8, 0.3, 5.2, 2.4), "intensity": 0.6, "direction": Vector2(0, 1), "distance": 3.0},
		{"id": "mid_sun", "rect": Rect2(9.6, 0.8, 3.0, 1.8), "intensity": 0.7, "direction": Vector2(0, 1), "distance": 2.5},
		{"id": "door_sun", "rect": Rect2(12.8, 3.2, 3.2, 3.0), "intensity": 1.0, "direction": Vector2(0, 1), "distance": 4.0},
		{"id": "ambient", "rect": Rect2(0, 0.4, 16, 9.6), "intensity": 0.25, "direction": Vector2(0, 1), "distance": 3.0}]
	clues = [{"id": "C1", "pos": Vector2(3.6, -2.48)},
		{"id": "C2", "pos": Vector2(5.2, -2.53)}, {"id": "C3", "pos": Vector2(6.9, -2.58)}]
	exit_rect = Rect2(16.1, 4.7, 1.0, 1.0)
	memory_position = Vector2(11.0, 0.5)


func objective(state, metrics: Dictionary) -> String:
	if water_contacts(state).is_empty():
		return "先让根接到水。空格感知方向，选种子后向下拖出根。"
	if metrics.get("ordinary_income", 0.0) < 0.05:
		return "按 2 长藤向上攀上栏杆；这片阳台光很好，但支点又高又稀。"
	if state.won:
		return "断口没有拦住你；每一次取舍都让路变得更短。"
	return "跨过断裂的缺口：绕行下沿，或借斜板强化跨越。向右侧门外的强光生长。"

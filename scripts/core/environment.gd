extends "res://scripts/core/level_base.gd"


# 第一章《空房间》：学会生长。数据从原 environment.gd 原样迁移，
# 通用查询逻辑上移到 level_base.gd，行为与迁移前逐字等价。


func _init() -> void:
	level_id = "apartment"
	title = "第一章 · 空房间"
	bounds = Rect2(0, -4, 24, 13.5)
	soils = [Rect2(0, -4, 24, 3.85), Rect2(1.6, -0.4, 0.8, 0.85)]
	obstacles = [
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
	surfaces = [
		{"id": "chair_seat", "a": Vector2(3, 1), "b": Vector2(6, 1), "normal": Vector2(0, 1)},
		{"id": "chair_back", "a": Vector2(5.8, 1), "b": Vector2(5.8, 1.5), "normal": Vector2(-1, 0)},
		{"id": "table_left", "a": Vector2(7.15, 0.4), "b": Vector2(7.15, 3.26), "normal": Vector2(-1, 0)},
		{"id": "table_top", "a": Vector2(7, 3.5), "b": Vector2(11, 3.5), "normal": Vector2(0, 1)},
		{"id": "pipe", "a": Vector2(12.5, 1), "b": Vector2(12.5, 6.5), "normal": Vector2(-1, 0)},
		{"id": "window_sill", "a": Vector2(15.6, 4.5), "b": Vector2(16.5, 4.5), "normal": Vector2(0, 1)},
		{"id": "window_frame", "a": Vector2(16, 4.5), "b": Vector2(16, 7), "normal": Vector2(-1, 0)}]
	waters = [
		{"id": "W1", "aquifer_id": "apartment", "q": 12.0, "rect": Rect2(1.7, -2.7, 0.6, 0.6)},
		{"id": "W2", "aquifer_id": "apartment", "q": 20.0, "rect": Rect2(7.65, -2.95, 0.7, 0.7)}]
	lights = [
		{"id": "L1", "rect": Rect2(3.2, 1.0, 1.8, 1.5), "intensity": 0.6, "direction": Vector2(0, 1), "distance": 1.8},
		{"id": "L2", "rect": Rect2(8.5, 3.5, 2.5, 1.5), "intensity": 1.0, "direction": Vector2(1, 0.25).normalized(), "distance": 5.0},
		{"id": "L3", "rect": Rect2(11.0, 4.5, 6.4, 3.0), "intensity": 0.6, "direction": Vector2(1, 0), "distance": 4.5},
		{"id": "L4", "rect": Rect2(16.22, 4.5, 7.78, 5.5), "intensity": 1.0, "direction": Vector2(0, 1), "distance": 5.0},
		{"id": "ambient", "rect": Rect2(0, 0.4, 16, 9.6), "intensity": 0.2, "direction": Vector2(0, 1), "distance": 3.0}]
	clues = [{"id": "C1", "pos": Vector2(3.6, -2.4)},
		{"id": "C2", "pos": Vector2(5.2, -2.5)}, {"id": "C3", "pos": Vector2(6.8, -2.6)}]
	exit_rect = Rect2(16.4, 5.8, 1.0, 1.0)
	memory_position = Vector2(8.5, 0.6)


func objective(state, metrics: Dictionary) -> String:
	if water_contacts(state).is_empty():
		return "先让根接到水。空格感知方向，选种子后向下拖出根。"
	if metrics.get("ordinary_income", 0.0) < 0.05:
		return "选回种子，按 2 长藤：向上穿过裂缝，再向右攀上椅座；按 3 长叶。"
	if state.won:
		return "你留下的每一道枝与伤痕，都成为通往光的路径。"
	return "沿椅子、桌沿和管道寻找支点。向右上方的窗外生长，必要时强化或修剪。"

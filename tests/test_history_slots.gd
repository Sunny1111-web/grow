extends RefCounted

const CAP: int = 200


func run(t) -> void:
	t.check(ResourceLoader.exists("res://scripts/view/history_slots.gd"), "历史表现槽合批器存在")
	if not ResourceLoader.exists("res://scripts/view/history_slots.gd"):
		return
	var Slots = load("res://scripts/view/history_slots.gd")
	_under_cap(t, Slots)
	_over_cap(t, Slots)
	_spatial_grouping(t, Slots)
	_far_history(t, Slots)
	_content_lines(t, Slots)
	_game_notice(t, Slots)


func _edge_item(x: float, tick: int) -> Dictionary:
	return {"type": "edge", "data": {"id": tick, "a": 1, "b": 2, "kind": "vine",
		"length": 0.8, "points": [Vector2(x, 1.0), Vector2(x + 0.4, 1.3), Vector2(x + 0.8, 1.0)],
		"z": 24.0, "bend": 0.0, "emergency": false, "slot": 0},
		"node": {"id": 2, "pos": Vector2(x + 0.8, 1.0), "parent_edge": tick, "kind": "shoot",
			"anchor": {}, "emergency": false},
		"reason": "prune", "tick": tick}


func _leaf_item(x: float, tick: int) -> Dictionary:
	return {"type": "leaf", "data": {"id": tick, "node": 1, "angle": 0.8, "z": 24.0,
		"emergency": false, "produced": 0.0},
		"pos": Vector2(x, 2.0), "reason": "prune", "tick": tick}


func _under_cap(t, Slots) -> void:
	var history: Array = []
	for i in range(150):
		history.append(_edge_item(float(i) * 0.1, i))
	var slots: Dictionary = Slots.compute(history)
	t.check(not slots.merged, "150项无合批")
	t.check(slots.items.size() == 150, "150项全部单项显示")
	t.check(slots.batches.is_empty() and slots.batched_count == 0, "无合批笔触")
	t.check(history.size() == 150, "逻辑历史未被修改")


func _over_cap(t, Slots) -> void:
	var history: Array = []
	for i in range(250):
		history.append(_edge_item(float(i) * 0.05, i))
	var slots: Dictionary = Slots.compute(history)
	t.check(slots.merged, "250项触发合批")
	t.check(slots.items.size() == CAP / 2, "最近100项保持单项清晰")
	t.check(slots.batched_count == 150, "最旧150项进入合批")
	t.check(slots.batches.size() <= CAP / 2, "合批笔触不超100组")
	t.check(slots.batches.size() + slots.items.size() <= CAP, "总表现槽不超200")
	t.check(slots.items[0].tick == 150, "单项区从第150项开始")
	t.check(history.size() == 250, "逻辑历史完整保留")


func _spatial_grouping(t, Slots) -> void:
	var history: Array = []
	# 150项挤在x≈0附近，另外100项散布远处；邻近项应合并为少量笔触。
	for i in range(150):
		history.append(_edge_item(randf() * 0.2, i))
	for i in range(100):
		history.append(_edge_item(5.0 + float(i) * 0.1, 150 + i))
	var slots: Dictionary = Slots.compute(history)
	t.check(slots.batches.size() <= 30, "150个空间邻近残枝合并为少量笔触: 实际%d组" % slots.batches.size())


func _far_history(t, Slots) -> void:
	var history: Array = []
	for i in range(600):
		history.append(_edge_item(float(i) * 0.3, i))
	var slots: Dictionary = Slots.compute(history)
	t.check(slots.merged, "600项触发合批")
	t.check(slots.batches.size() + slots.items.size() <= CAP, "600项总表现槽仍不超200")
	t.check(slots.batched_count == 500, "600项中最旧500项进入合批")
	var members: int = 0
	for batch in slots.batches:
		members += batch.members
	t.check(members == 500, "合批成员总数守恒")


func _content_lines(t, Slots) -> void:
	var history: Array = []
	for i in range(120):
		history.append(_edge_item(float(i) * 0.02, i))
	for i in range(30):
		history.append(_leaf_item(float(i) * 0.02, 120 + i))
	for i in range(100):
		history.append(_edge_item(8.0 + float(i) * 0.1, 150 + i))
	var slots: Dictionary = Slots.compute(history)
	t.check(slots.merged, "混合历史触发合批")
	var edges: int = 0
	var leaves: int = 0
	var segments: int = 0
	for batch in slots.batches:
		edges += batch.edges
		leaves += batch.leaves
		t.check(batch.lines.size() % 2 == 0, "合批线段成对")
		segments += batch.lines.size() / 2
	t.check(edges == 120 and leaves == 30, "合批涵盖120边30叶")
	# 每条3点折线边贡献2线段，每片叶贡献4线段菱形标记。
	t.check(segments == 120 * 2 + 30 * 4, "合批线段数=边折线+叶标记: 实际%d" % segments)


func _game_notice(t, Slots) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/history-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	for i in range(250):
		game.service.state.history.append(_edge_item(float(i) * 0.05, i))
	game.world._update_history_slots(game.service.state)
	t.check(game._history_merged_announced, "超过200表现槽后提示合批")
	t.check(game.hud.message_label.text.contains("合并"), "提示文案说明旧痕迹已合并显示")
	t.check(game.world._slots_cache.batches.size() > 0, "渲染层获得合批笔触")
	t.check(game.service.state.history.size() == 250, "提示后逻辑历史完整保留")
	game.free()

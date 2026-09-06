extends RefCounted

const Guide = preload("res://scripts/core/guide.gd")
const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")
const Saves = preload("res://scripts/core/save_service.gd")


func run(t) -> void:
	_step_progression(t)
	_skip_and_replay(t)
	_idle_help(t)
	_persistence(t)


func _fresh_game(t) -> Node:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/guide-game-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	return game


func _step_progression(t) -> void:
	var game = _fresh_game(t)
	var result: Dictionary = Guide.evaluate(game)
	t.check(result.active and result.step == 0, "开局处于第0步且引导激活")
	game._update_guide(0.1)
	t.check(game.guide_message == Guide.STEPS[0].text, "引导文案为当前步骤")
	t.check(game.hud.guide_panel.visible, "引导卡可见")
	t.check(game.hud.guide_text_label.text == Guide.STEPS[0].text, "引导卡显示当前任务")
	t.check(game.hud.guide_step_label.text.contains("1 / 5"), "引导卡显示步骤进度")
	# 第0步：选中种子并开始拖根。
	game.selected_node = 1
	game.selected_tool = "root"
	game.dragging = true
	result = Guide.evaluate(game)
	t.check(result.step == 1, "开始拖根推进到第1步")
	game._update_guide(0.1)
	t.check(game.hud.guide_text_label.text == Guide.STEP_FLASH[1], "步进瞬间引导卡显示强调反馈")
	game._update_guide(3.0)
	t.check(game.hud.guide_text_label.text == Guide.STEPS[1].text, "反馈后回到步骤说明")
	game.dragging = false
	# 第1步：长出第一段根——尚未触水，不能提前宣告接水。
	var state = game.service.state
	var tip: int = state.edges[state.add_edge(1, "root", [Vector2(2, -0.8), Vector2(2, -1.6)])].b
	result = Guide.evaluate(game)
	t.check(result.step == 1 and result.active, "只长一段根未触水，仍停留在拖根接水步骤")
	t.check(not state.guide.helped, "步进后重置追加帮助")
	# 第2步：第二段根尖接到水源，才推进到长藤。
	tip = state.edges[state.add_edge(tip, "root", [Vector2(2, -1.6), Vector2(2, -2.4)])].b
	t.check(game.service.env.water_contacts(state).size() > 0, "两根接水")
	result = Guide.evaluate(game)
	t.check(result.step == 2, "根尖真实接水后推进到长藤步骤")
	var vine: int = state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.2)])
	state.nodes[state.edges[vine].b].kind = "shoot"
	result = Guide.evaluate(game)
	t.check(result.step == 3, "长藤推进到第3步")
	# 第3步：攀附支点。
	state.nodes[state.edges[vine].b].anchor = {"id": "chair_seat", "pos": Vector2(2, 0.2), "normal": Vector2(0, 1)}
	result = Guide.evaluate(game)
	t.check(result.step == 4, "锚定支点推进到第4步")
	# 第4步：长叶 → 教学完成。
	var leaf: int = state.add_leaf(state.edges[vine].b)
	result = Guide.evaluate(game)
	t.check(not result.active and result.step >= Guide.STEPS.size(), "长叶后教学完成退出提示")
	game._update_guide(0.1)
	t.check(game.hud.guide_panel.visible and game.hud.guide_text_label.text == Guide.STEP_FLASH[5], "完成瞬间引导卡显示完成反馈")
	game._update_guide(4.0)
	t.check(not game.hud.guide_panel.visible, "反馈结束后引导卡收起")
	game.free()


func _skip_and_replay(t) -> void:
	var game = _fresh_game(t)
	Guide.skip(game)
	var result: Dictionary = Guide.evaluate(game)
	t.check(not result.active, "跳过后引导不再激活")
	t.check(game.service.state.guide.skipped, "跳过标记写入状态")
	t.check(Guide.replay_message(game).length() > 0, "跳过后仍可重看提示文案")
	game.service.state.guide.skipped = false
	game.service.state.guide.step = 2
	var message: String = Guide.replay_message(game)
	t.check(message == Guide.STEPS[2].text, "重看返回当前步骤的完整提示")
	game.free()


func _idle_help(t) -> void:
	var game = _fresh_game(t)
	game.idle_time = Guide.IDLE_HELP_SECONDS + 1.0
	game._update_guide(0.1)
	t.check(game.service.state.guide.get("helped", false), "长时间无进展追加帮助并记录")
	t.check(game.hud.guide_text_label.text.contains("\n"), "追加帮助进入引导卡")
	game.idle_time = 0.0
	game._update_guide(0.1)
	t.check(game.hud.guide_text_label.text.find("\n", 0) == -1 or game.hud.guide_text_label.text == game.guide_message, "帮助只追加一次，不重复堆叠")
	# 工具按钮提示映射与步骤对应。
	t.check(Guide.STEP_TOOLS.size() == Guide.STEPS.size(), "每步都有工具提示映射")
	t.check(Guide.STEP_TOOLS[2] == "vine" and Guide.STEP_TOOLS[4] == "leaf", "长藤/长叶步骤映射正确工具")
	game.free()


func _persistence(t) -> void:
	var game = _fresh_game(t)
	var state = game.service.state
	game.dragging = true
	game.selected_node = 1
	game.selected_tool = "root"
	Guide.evaluate(game)
	var saves = Saves.new(game.save_directory, game.level_id)
	var loaded: Dictionary = saves.load_latest()
	t.check(loaded.ok and loaded.state.guide.step >= 1, "引导步进随检查点保存")
	game.free()

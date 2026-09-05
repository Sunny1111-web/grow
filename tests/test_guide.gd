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
	t.check(game.guide_message == Guide.STEPS[0].text, "HUD 引导文案为当前步骤")
	# 第0步：选中种子并开始拖根。
	game.selected_node = 1
	game.selected_tool = "root"
	game.dragging = true
	result = Guide.evaluate(game)
	t.check(result.step == 1, "开始拖根推进到第1步")
	game.dragging = false
	# 第1步：长出第一段根。
	var state = game.service.state
	var tip: int = state.edges[state.add_edge(1, "root", [Vector2(2, -0.8), Vector2(2, -1.6)])].b
	result = Guide.evaluate(game)
	t.check(result.step == 2, "长出根推进到第2步")
	t.check(not state.guide.helped, "步进后重置追加帮助")
	# 第2步：接水后长藤。
	tip = state.edges[state.add_edge(tip, "root", [Vector2(2, -1.6), Vector2(2, -2.4)])].b
	t.check(game.service.env.water_contacts(state).size() > 0, "两根接水")
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
	t.check(game.message_hold > 0.0, "追加帮助持有消息展示期")
	game.idle_time = 0.0
	game._update_guide(0.1)
	t.check(game.guide_message.find("\n") == -1, "帮助只追加一次，不重复堆叠")
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

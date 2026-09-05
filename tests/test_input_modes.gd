extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const Service = preload("res://scripts/core/command_service.gd")


func run(t) -> void:
	_focus_out_combination(t)
	_tab_overlap(t)
	_cut_leaf_highlight(t)
	_danger_visualization(t)
	_ending_input_conflicts(t)
	_modal_clears_transient_modes(t)
	_sensing_toggle_mode(t)
	_settings_and_readability(t)
	_selection_feedback(t)


# 失焦与预览/感知/修剪/平移模式组合：失焦清空交互状态且不遗留冻结。
func _focus_out_combination(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/focus-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var trunk: int = state.edges[state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.5)])].b
	game._activate_state(state)
	game.selected_node = trunk
	game.select_tool("leaf")
	t.check(not game.proposal.is_empty() and game.sim.frozen.has("preview"), "叶预览进入预览冻结")
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(game.proposal.is_empty(), "失焦取消预览")
	t.check(not game.sim.frozen.has("preview"), "失焦释放预览冻结")
	t.check(not game.sensing and not game.pruning and not game.panning, "失焦退出感知/修剪/平移模式")
	# 失焦冻结经济时间（TDD：所有收益与损伤同冻），焦点回归后恢复流动。
	t.check(game.sim.frozen.has("focus"), "失焦冻结经济时间")
	game._process(0.1)
	t.check(state.tick == 0, "失焦期间时间不走")
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(not game.sim.frozen.has("focus"), "焦点回归解除失焦冻结")
	game._process(0.1)
	t.check(state.tick > 0, "焦点回归后时间继续流动")
	# 感知+菜单嵌套：失焦释放感知，菜单仍冻结。
	var down = InputEventKey.new()
	down.keycode = KEY_SPACE
	down.pressed = true
	game._unhandled_input(down)
	t.check(game.sim.frozen.has("sense"), "感知冻结生效")
	game.show_pause()
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(not game.sim.frozen.has("sense"), "失焦退出感知")
	t.check(game.sim.frozen.has("menu"), "菜单冻结保留嵌套")
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.resume_game()
	t.check(game.sim.frozen.is_empty(), "恢复后无残留冻结: %s" % str(game.sim.frozen.keys()))
	game.free()


# Tab在重叠目标间循环切换。
func _tab_overlap(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/tab-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var empty_env = Level.new()
	var trunk: int = state.edges[state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.5)])].b
	var branch_a: int = state.edges[state.add_edge(trunk, "vine", [Vector2(2, 0.5), Vector2(2.3, 0.8)])].b
	var branch_b: int = state.edges[state.add_edge(trunk, "vine", [Vector2(2, 0.5), Vector2(2.25, 0.82)], {}, false, 1)].b
	game._activate_state(state)
	game.selected_tool = "vine"
	# 光标放在两个分支端点之间的重叠区。
	game.cursor_position = game.world.to_screen(Vector2(2.27, 0.81))
	game.selected_node = branch_a
	game._cycle_selection()
	t.check(game.selected_node == branch_b, "Tab从分支A切换到重叠的分支B")
	game._cycle_selection()
	t.check(game.selected_node == branch_a, "Tab再次按返回分支A形成循环")
	game.free()


# 剪叶预览高亮被剪的叶；剪边预览保持整子树高亮。
func _cut_leaf_highlight(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/cut-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var trunk: int = state.edges[state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.5)])].b
	var leaf: int = state.add_leaf(trunk)
	game._activate_state(state)
	var proposal: Dictionary = game.service.preview("prune_leaf", leaf)
	t.check(proposal.ok, "剪叶预览可用")
	game.proposal = proposal
	var positions: Array = game.world.cut_highlight(proposal)
	t.check(positions.size() == 1, "剪叶高亮恰好一片叶")
	if positions.size() == 1:
		t.check(positions[0] == state.nodes[trunk].pos, "高亮位置为被剪叶的挂点")
	var edge_proposal: Dictionary = game.service.preview("prune_edge", state.edges.keys()[0])
	t.check(game.world.cut_highlight(edge_proposal).is_empty(), "剪边预览不产生叶高亮")
	game.proposal = {}
	game.free()


# 结构风险累积（bend>0）的枝有独立警示数据源，供渲染层叠加危险描边。
func _danger_visualization(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/danger-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var risky: int = state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(3.2, -0.4)])
	state.edges[risky].bend = 0.5
	game._activate_state(state)
	var danger: Array = game.world.danger_edge_ids()
	t.check(danger.has(risky), "危险枝清单包含bend超阈枝条")
	t.check(not danger.has(state.edges.keys()[0]) or state.edges[state.edges.keys()[0]].bend > 0.0,
		"无风险的枝条不入清单")
	game.free()


# 结尾运镜期间：空格/Esc/切窗都不打断结尾卡，也不遗留感知冻结。
func _ending_input_conflicts(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/ending-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var vine: int = state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.5)])
	state.nodes[state.edges[vine].b].kind = "shoot"
	state.add_leaf(state.edges[vine].b)
	game._activate_state(state)
	state.won = true
	game._process(0.05)
	t.check(game.ending_elapsed >= 0.0, "通关后进入结尾运镜")
	# 运镜中按空格与 Esc：应被完全忽略。
	_key(game, KEY_SPACE, true)
	_key(game, KEY_SPACE, false)
	_key(game, KEY_ESCAPE, true)
	t.check(not game.sensing and not game.sim.frozen.has("sense"), "结尾期间空格不进入感知")
	t.check(game.ending_elapsed >= 0.0 and not game.sim.frozen.has("menu"), "结尾期间Esc不打开暂停也不打断运镜")
	# 运镜中失焦再回焦：结尾继续。
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.notification(game.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._process(2.5)
	t.check(game.hud.modal != null, "运镜结束后通关卡正常弹出")
	t.check(not game.sim.frozen.has("sense"), "通关卡无感知冻结残留")
	# 继续观察后无任何残留冻结。
	game.resume_game()
	t.check(game.sim.frozen.is_empty(), "结尾后恢复无残留冻结: %s" % str(game.sim.frozen.keys()))
	game.free()


# 打开救援等模态前清空感知/修剪：按住的空格在模态冻结下收不到释放事件。
func _modal_clears_transient_modes(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/modal-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	_key(game, KEY_SPACE, true)
	t.check(game.sensing and game.sim.frozen.has("sense"), "按住空格进入感知")
	game.show_rescue()
	t.check(not game.sensing and not game.sim.frozen.has("sense"), "救援模态清空感知与冻结")
	t.check(game.sim.frozen.has("menu"), "救援模态保持菜单冻结")
	game.resume_game()
	t.check(game.sim.frozen.is_empty(), "模态恢复后无残留冻结")
	_key(game, KEY_SPACE, true)
	game.show_pause()
	t.check(not game.sensing, "暂停模态同样清空感知")
	game.resume_game()
	_key(game, KEY_SPACE, true)
	_rescue_freeze(t, game)
	game.free()


func _rescue_freeze(t, game) -> void:
	game.sim.needs_rescue = true
	game._rescue_shown = false
	game._process(0.05)
	t.check(game.sensing == false, "危机模态弹出时感知已释放")
	game.resume_game()
	t.check(game.sim.frozen.is_empty(), "危机模态恢复无残留冻结")


func _key(game, keycode: int, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	game._unhandled_input(event)


# 感知切换模式：点击/空格切换开合，释放键不复位。
func _sensing_toggle_mode(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/toggle-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	game.set_sensing_toggle(true)
	t.check(game.sensing_toggle, "感知切换设置生效")
	_key(game, KEY_SPACE, true)
	t.check(game.sensing and game.sim.frozen.has("sense"), "切换模式：按下开启感知")
	_key(game, KEY_SPACE, false)
	t.check(game.sensing, "切换模式：释放保持感知")
	_key(game, KEY_SPACE, true)
	t.check(not game.sensing and not game.sim.frozen.has("sense"), "切换模式：再次按下关闭感知")
	game.set_sensing_toggle(false)
	_key(game, KEY_SPACE, true)
	_key(game, KEY_SPACE, false)
	t.check(not game.sensing and not game.sim.frozen.has("sense"), "切回按住模式后语义恢复")
	game.free()


# 界面缩放、低动态与设置持久化。
func _settings_and_readability(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/settings-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	game.audio.settings_path = "res://test-results/settings-%d.cfg" % Time.get_ticks_usec()
	var base_size: int = game.hud.message_label.get_theme_font_size("font_size")
	game.set_ui_scale(1.5)
	t.check(is_equal_approx(game.ui_scale, 1.5), "界面缩放设置生效")
	t.check(game.hud.message_label.get_theme_font_size("font_size") > base_size, "缩放后消息字号变大")
	t.check(game.audio.setting("ui", "ui_scale", 0.0) == 1.5, "界面缩放写入设置存储")
	game.set_low_motion(true)
	t.check(game.world.leaf_wave(3) == 0.0, "低动态下叶摆为0")
	t.check(game.audio.setting("ui", "low_motion", false), "低动态写入设置存储")
	game.set_low_motion(false)
	t.check(game.world.leaf_wave(3) != 0.0, "恢复动态后叶摆函数可用")
	game.set_ui_scale(1.0)
	game.free()


# 选中供水路径与状态反馈数据源。
func _selection_feedback(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/feedback-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	var state = game.service.state
	var trunk: int = state.edges[state.add_edge(1, "vine", [Vector2(2, -0.8), Vector2(2, 0.5)])].b
	state.nodes[trunk].kind = "shoot"
	var leaf: int = state.add_leaf(trunk)
	game._activate_state(state)
	game.sensing = true
	game.selected_node = trunk
	var path: Array = game.world.selection_path_ids()
	t.check(path.size() == 1 and path[0] == state.edges.keys()[0], "感知高亮返回选中节点到种子的父链")
	t.check(game.service.state.parent_chain(trunk).size() == 1, "父链来自状态而非缓存")
	game.sensing = false
	t.check(game.world.shaded_leaf_ids().is_empty(), "非感知模式无遮光清单")
	game.sensing = true
	# 低光照叶入清单：直接构造替身指标。
	var dim: Dictionary = {"light": 0.1, "transmission": 1.0, "intensity": 0.1}
	game.sim.metrics.light[leaf] = dim
	t.check(game.world.shaded_leaf_ids().has(leaf), "光照不足的普通叶进入遮光清单")
	game.free()

extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const Service = preload("res://scripts/core/command_service.gd")


func run(t) -> void:
	_focus_out_combination(t)
	_tab_overlap(t)
	_cut_leaf_highlight(t)
	_danger_visualization(t)


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

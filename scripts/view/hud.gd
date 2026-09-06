extends CanvasLayer

const Levels = preload("res://scripts/core/levels.gd")

var game
var chapter_title_label: Label
var root: Control
var energy_label: Label
var water_label: Label
var income_label: Label
var selection_label: Label
var message_label: Label
var preview_label: Label
var mode_label: Label
var energy_bar: ProgressBar
var modal: Control
var tool_buttons: Dictionary = {}
var sense_button: Button = null

const PAPER = Color("e6e0cc")
const GREEN = Color("b4d184")
const INK = Color("17252f")


func _ready() -> void:
	_build()


# 设置（界面缩放）变更后整体重建；引导进度等动态状态不受影响。
func apply_settings() -> void:
	if root != null:
		root.queue_free()
		root = null
	tool_buttons.clear()
	_build()


func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	theme.default_font = font
	theme.default_font_size = int(18 * game.ui_scale)
	root.theme = theme
	add_child(root)
	var top = HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 38
	top.offset_top = 24
	top.offset_right = -38
	top.add_theme_constant_override("separation", 30)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var brand = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	var level_title: String = str(game.service.env.title) if game.service != null else ""
	brand.add_child(_label("G R O W", 30, PAPER))
	chapter_title_label = _label("向 光 而 生  /  " + level_title, 13, Color("87969c"))
	brand.add_child(chapter_title_label)
	var resource_panel = PanelContainer.new()
	resource_panel.custom_minimum_size = Vector2(360 * game.ui_scale, 0)
	resource_panel.add_theme_stylebox_override("panel", _box(Color(0.065, 0.1, 0.12, 0.94), 8, Color("465b68"), 10))
	top.add_child(resource_panel)
	var resources = VBoxContainer.new()
	resource_panel.add_child(resources)
	energy_label = _label("能量 30 / 40", 20, GREEN)
	resources.add_child(energy_label)
	energy_bar = ProgressBar.new()
	energy_bar.max_value = 40
	energy_bar.show_percentage = false
	energy_bar.custom_minimum_size = Vector2(320 * game.ui_scale, 5)
	energy_bar.add_theme_stylebox_override("background", _box(Color("2b3b42"), 3))
	energy_bar.add_theme_stylebox_override("fill", _box(GREEN, 3))
	resources.add_child(energy_bar)
	water_label = _label("供水 尚未接入", 15, Color("67b8c6"))
	resources.add_child(water_label)
	income_label = _label("", 13, PAPER)
	resources.add_child(income_label)
	selection_label = _label("", 12, Color("9fb8bd"))
	resources.add_child(selection_label)
	var pause = _button("Ⅱ  暂停", game.show_pause)
	pause.custom_minimum_size = Vector2(96, 45)
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(pause)
	var bottom = VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 38
	bottom.offset_right = -38
	bottom.offset_top = -156
	bottom.offset_bottom = -18
	bottom.add_theme_constant_override("separation", 9)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	message_label = _label("", 17, PAPER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 25
	bottom.add_child(message_label)
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.065, 0.1, 0.12, 0.94), 10, Color("465b68")))
	bottom.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	for item in [["root", "1  根", "4 E"], ["vine", "2  藤", "5 E"], ["leaf", "3  叶", "3 E"], ["reinforce", "4  强化", "6 E"]]:
		var tool: String = item[0]
		var button = _button(item[1] + "\n" + item[2], game.select_tool.bind(tool))
		button.custom_minimum_size = Vector2(120, 62)
		row.add_child(button)
		tool_buttons[tool] = button
	sense_button = _button("感知\n空格", game.toggle_sensing)
	sense_button.custom_minimum_size = Vector2(84, 62)
	row.add_child(sense_button)
	var detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 5)
	row.add_child(detail)
	preview_label = _label("选择一个生长点，然后拖出方向", 16, GREEN)
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(preview_label)
	mode_label = _label("空格 感知  ·  Shift 修剪  ·  F 催生  ·  中键 平移  ·  滚轮 缩放", 13, Color("87969c"))
	detail.add_child(mode_label)


func refresh() -> void:
	if game.service == null:
		return
	var state = game.service.state
	var metrics: Dictionary = game.sim.metrics
	energy_label.text = "能量  %.1f / 40" % state.energy
	energy_bar.value = state.energy
	if metrics.water.q <= 0.0:
		water_label.text = "供水  尚未接入 · 根会逐渐失水"
	else:
		water_label.text = "供水 %.0f  /  需求 %.2f" % [metrics.water.q, metrics.water.demand]
	income_label.text = "光合 +%.2f E / 秒     悬空风险 %.2f" % [metrics.income, metrics.support.max_risk]
	_update_selection_line(state, metrics)
	for tool in tool_buttons:
		tool_buttons[tool].modulate = GREEN if tool == game.selected_tool else PAPER
	if sense_button != null:
		sense_button.modulate = GREEN if game.sensing else PAPER
	var proposal: Dictionary = game.proposal
	if not proposal.is_empty():
		if proposal.ok:
			var m: Dictionary = proposal.metrics
			preview_label.text = "确认：%.0f E  ·  需求 %.2f  ·  风险 %.2f" % [proposal.cost, m.water.demand, m.support.max_risk]
			if proposal.kind.begins_with("prune"):
				preview_label.text = "修剪 %d 枝 / %d 叶  ·  剩余需求 %.2f  ·  产能 %.2f" % [proposal.removed_edges, proposal.removed_leaves, m.water.demand, m.income]
			preview_label.modulate = Color("d79b67") if m.support.max_risk > 1.0 else GREEN
		else:
			preview_label.text = proposal.reason
			preview_label.modulate = Color("d79b67")
	else:
		preview_label.modulate = GREEN
		preview_label.text = "感知中 · 水光与生命一同暂停" if game.sensing else "拖拽生长；叶与强化需再次点击目标确认"
	if game.pruning:
		mode_label.text = "修剪模式：点击高亮叶片或枝段；残枝会留下，能量不返还"
	elif not game.sim.frozen.is_empty():
		mode_label.text = "思考时间  ·  模拟暂停     右键取消预览  /  Home 回到选中点"
	else:
		mode_label.text = "空格 感知  ·  Shift 修剪  ·  F 催生  ·  中键 平移  ·  滚轮 缩放"


# 选中路径反馈：到种子的供水链、选中器官的水分与光照状态。
func _update_selection_line(state, metrics: Dictionary) -> void:
	var node_id: int = game.selected_node
	if not state.nodes.has(node_id):
		selection_label.text = ""
		return
	var chain: Array = state.parent_chain(node_id)
	var parts: Array = []
	var worst_supply: float = 1.0
	for edge_id in chain:
		if metrics.water.organs.has(edge_id):
			worst_supply = minf(worst_supply, metrics.water.organs[edge_id].r)
	if chain.is_empty():
		parts.append("选中：种子")
	else:
		parts.append("选中路径 %d 段 · 沿途供水 %.2f" % [chain.size(), worst_supply])
	var leaf_id: int = state.leaf_at(node_id, true)
	if leaf_id != 0 and metrics.light.has(leaf_id):
		parts.append("叶光照 %.2f" % metrics.light[leaf_id].light)
	elif metrics.water.organs.has(node_id):
		parts.append("此处供水 %.2f" % metrics.water.organs[node_id].r)
	if worst_supply < 0.95:
		parts.append("缺水")
	if metrics.support.max_risk > 1.0:
		parts.append("承重吃力 %.2f" % metrics.support.max_risk)
	selection_label.text = "  ·  ".join(parts)


func set_message(text: String) -> void:
	if message_label != null and message_label.text != text:
		message_label.text = text


func close_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null


func refresh_chapter_title() -> void:
	if is_instance_valid(chapter_title_label):
		chapter_title_label.text = "向 光 而 生  /  " + str(game.service.env.title)


func show_chapter_error(reason: String) -> void:
	var content = _modal("暂时无法进入这一章", reason + "\n已有进度仍然保留。")
	content.add_child(_button("返回章节列表", game.return_to_title))


func show_title() -> void:
	var content = _modal("向 光 而 生", "从无人居住的房间，向断裂的阳台伸展。\n你长出的身体，就是你走过的路。")
	for definition in Levels.ordered():
		if not game.is_chapter_unlocked(definition.id):
			content.add_child(_label("%s  ·  通关上一章后解锁" % definition.title, 17, Color("87969c")))
			continue
		var chapter_status: Dictionary = game.chapter_status(definition.id)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
		row.add_child(_label(definition.title, 17, PAPER))
		if chapter_status.get("found", false) and not chapter_status.ok:
			var warning = _label(chapter_status.reason, 15, Color("d79b67"))
			warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(warning)
		elif chapter_status.ok:
			row.add_child(_button("继续", game.continue_game.bind(definition.id)))
			row.add_child(_button("重新开始", game.start_new_game.bind(definition.id)))
		else:
			row.add_child(_button("开始生长", game.start_new_game.bind(definition.id)))
	content.add_child(_label("每章独立保存；重玩前一章不会收回已经解锁的章节。", 15, Color("87969c")))
	content.add_child(_label("拖拽引导生长  /  预览时暂停  /  随时可以退守种子", 14, Color("87969c")))


func show_pause() -> void:
	var content = _modal("留一点时间，观察", "根接水，叶获取光能。藤需要支点，也需要持续供水。\n生长不只是向前；修剪能让资源重新抵达重要的枝叶。")
	content.add_child(_button("继续生长", game.resume_game))
	content.add_child(_volume_row("整体音量", "Master"))
	content.add_child(_volume_row("环境声", "Ambience"))
	content.add_child(_volume_row("动作音效", "SFX"))
	content.add_child(_settings_rows())
	content.add_child(_button("保存进度  ·  F5", game.save_progress.bind(true)))
	content.add_child(_button("退守种子…", game.show_rescue))
	content.add_child(_button("重看本步引导", game.replay_guide_hint))
	content.add_child(_button("跳过引导", game.skip_guide))
	content.add_child(_button("保存并返回章节列表", game.return_to_title))
	content.add_child(_button("保存并退出", game.request_quit))
	content.add_child(_label("1 根 · 2 藤 · 3 叶 · 4 强化\n空格感知 · Shift 修剪 · F 催生\n中键平移 · 滚轮缩放 · Home 回到选中点", 16, PAPER))


func _volume_row(label_text: String, bus_name: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var label = _label(label_text, 16, PAPER)
	label.custom_minimum_size = Vector2(116, 0)
	row.add_child(label)
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = game.audio.volume(bus_name)
	slider.custom_minimum_size = Vector2(300, 0)
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.value_changed.connect(func(value: float) -> void:
		game.audio.set_volume(bus_name, value)
		game.audio.save_settings())
	row.add_child(slider)
	return row


# 可读性与操作设置：界面缩放、感知按住/切换、低动态效果。
func _settings_rows() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var scale_row = HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 18)
	scale_row.add_child(_label("界面缩放", 16, PAPER))
	for option in [1.0, 1.25, 1.5]:
		var mark: String = "▸" if is_equal_approx(game.ui_scale, option) else "　"
		var scale_button = _button("%s%.0f%%" % [mark, option * 100.0], game.set_ui_scale.bind(option))
		scale_button.toggle_mode = false
		scale_row.add_child(scale_button)
	box.add_child(scale_row)
	var sense_row = HBoxContainer.new()
	sense_row.add_theme_constant_override("separation", 18)
	sense_row.add_child(_label("感知方式", 16, PAPER))
	sense_row.add_child(_button("按住空格" if not game.sensing_toggle else "▸按住空格",
		game.set_sensing_toggle.bind(false)))
	sense_row.add_child(_button("点击切换" if game.sensing_toggle else "▸点击切换",
		game.set_sensing_toggle.bind(true)))
	box.add_child(sense_row)
	var motion_row = HBoxContainer.new()
	motion_row.add_theme_constant_override("separation", 18)
	motion_row.add_child(_label("动态效果", 16, PAPER))
	motion_row.add_child(_button("低动态（减少摆动与光晕）" if not game.low_motion else "▸低动态（减少摆动与光晕）",
		game.set_low_motion.bind(not game.low_motion)))
	box.add_child(motion_row)
	return box


func show_rescue() -> void:
	var content = _modal("回到那颗种子", "当前能量归零，所有普通枝叶退为残痕。\n探索和记忆会留下。种子恢复两条固定根和一片应急子叶，\n子叶最多提供 18 能量，足够重新长出三段藤和一片叶。")
	content.add_child(_button("确认退守", game.confirm_rescue))
	var next: String = game.next_chapter()
	if next != "":
		content.add_child(_button("进入" + str(Levels.get_definition(next).title), game.open_next_chapter))
	content.add_child(_button("继续观察", game.resume_game))


func show_victory() -> void:
	var content = _modal("G R O W  ·  向光而生", "你从地板下醒来，借着旧物，长成了自己的路。\n那些剪去的枝、留下的伤口，也成为这株植物的一部分。\n\n" + str(game.service.env.title) + "  完成")
	var next: String = game.next_chapter()
	if next != "":
		content.add_child(_button("进入" + str(Levels.get_definition(next).title), game.open_next_chapter))
	content.add_child(_button("继续观察", game.resume_game))
	content.add_child(_button("返回标题", game.return_to_title))


func _modal(title: String, body: String) -> VBoxContainer:
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0.04, 0.07, 0.085, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	panel.add_theme_stylebox_override("panel", _box(Color("17252f"), 16, Color("465b68"), 36))
	center.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	panel.add_child(content)
	content.add_child(_label(title, 38, GREEN))
	content.add_child(_label(body, 19, PAPER))
	return content


func _label(text: String, size: int, color: Color) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(round(size * game.ui_scale)))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_stylebox_override("normal", _box(Color("24353d"), 7))
	button.add_theme_stylebox_override("hover", _box(Color("3c5355"), 7, GREEN))
	button.add_theme_stylebox_override("pressed", _box(Color("465b68"), 7, GREEN))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), 7, GREEN))
	button.pressed.connect(action)
	return button


func _box(color: Color, radius: int, border: Color = Color.TRANSPARENT, margin: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.border_color = border
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

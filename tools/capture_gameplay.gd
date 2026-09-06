extends SceneTree

# 玩法视频录制：真实输入驱动的约30秒剧本，10fps逐帧截屏。
# 用法: godot --path <工程> --script res://tools/capture_gameplay.gd -- --output-dir=<目录>
# 之后用 ffmpeg 合成: ffmpeg -framerate 10 -i frames/f_%04d.png -r 30 -c:v libx264 -crf 22 -pix_fmt yuv420p gameplay.mp4

var output_directory: String = "res://test-results/gameplay"
var game: Node = null
var frame_index: int = 0


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_directory + "/frames")
	# ---------- 第一章：开局与引导 ----------
	game = await _new_game("apartment")
	game.start_new_game("apartment")
	await _capture(20)          # 2.0s 开局：引导卡与种子金圈
	var seed_screen: Vector2 = game.world.to_screen(_seed_pos())
	# 第一段根：向下拖（世界-y为向下，动画预览）
	await _animated_drag(seed_screen, game.world.to_screen(_seed_pos() + Vector2(0.0, -0.85)), 8)
	await _capture(10)
	# 第二段根：接到水
	await _animated_drag(game.world.to_screen(_seed_pos() + Vector2(0.0, -0.85)),
		game.world.to_screen(_seed_pos() + Vector2(0.0, -1.7)), 8)
	await _capture(16)          # 接水反馈
	# ---------- 长藤与攀附（90°→60°→12°，与验证器同款路线） ----------
	game.select_tool("vine")
	await _capture(8)
	var node1: Vector2 = _tip_pos()
	await _animated_drag(game.world.to_screen(node1), game.world.to_screen(node1 + Vector2(0.0, 1.0)), 10)
	await _capture(10)
	var node2: Vector2 = _tip_pos()
	await _animated_drag(game.world.to_screen(node2), game.world.to_screen(node2 + Vector2(0.5, 0.87)), 10)
	await _capture(12)          # 60°上斜，接近椅座
	# ---------- 长叶与产能 ----------
	game.select_tool("leaf")
	var leaf_target: int = _any_grow_node()
	await _click_node(leaf_target)
	await _capture(6)
	await _click_node(leaf_target)
	await _capture(30)          # 3s 首叶与能量累积
	# ---------- 继续生长与拉远收尾 ----------
	game.select_tool("vine")
	var node3: Vector2 = _tip_pos()
	await _animated_drag(game.world.to_screen(node3), game.world.to_screen(node3 + Vector2(0.95, 0.2)), 8)
	await _capture(8)
	game.world.unit_scale = 58.0
	game.world.clamp_camera()
	await _capture(24)          # 拉远看整株
	game.queue_free()
	await process_frame
	# ---------- 第二章：断裂的阳台 ----------
	var completed = load("res://scripts/core/plant_state.gd").create()
	completed.won = true
	var first_save = load("res://scripts/core/save_service.gd").new(output_directory + "/saves/chapter1", "apartment")
	first_save.save(completed)
	game = await _new_game("balcony")
	game.start_new_game("balcony")
	game.world.ensure_visible(_seed_pos())
	await _capture(18)          # 阳台开场
	game.select_tool("vine")
	var balcony_node: Vector2 = _seed_pos()
	# 藤先垂直穿过裂缝，再斜向栏杆（裂缝两侧是楼板，斜向会被硬障碍挡下）。
	await _animated_drag(game.world.to_screen(balcony_node), game.world.to_screen(balcony_node + Vector2(0.0, 1.05)), 8)
	await _capture(10)
	var balcony_tip: Vector2 = _tip_pos()
	await _animated_drag(game.world.to_screen(balcony_tip), game.world.to_screen(balcony_tip + Vector2(0.35, 0.94)), 8)
	await _capture(8)
	balcony_tip = _tip_pos()
	await _animated_drag(game.world.to_screen(balcony_tip), game.world.to_screen(balcony_tip + Vector2(0.95, 0.32)), 8)
	await _capture(14)          # 攀向栏杆
	print("GAMEPLAY_CAPTURE frames=%d dir=%s" % [frame_index, output_directory])
	quit(0)


func _new_game(level_id: String) -> Node:
	var instance = load("res://scenes/main.tscn").instantiate()
	instance.save_root = output_directory + "/saves"
	root.add_child(instance)
	instance.set_process(false)
	await process_frame
	return instance


func _seed_pos() -> Vector2:
	return game.service.state.nodes[game.service.state.seed_id].pos


func _tip_pos() -> Vector2:
	var best: int = game.service.state.seed_id
	var best_y: float = -100.0
	for node in game.service.state.nodes.values():
		if node.pos.y > best_y:
			best_y = node.pos.y
			best = node.id
	return game.service.state.nodes[best].pos


func _any_grow_node() -> int:
	var best: int = game.service.state.seed_id
	var best_y: float = -100.0
	for node in game.service.state.nodes.values():
		if node.emergency:
			continue
		if node.pos.y > best_y:
			best_y = node.pos.y
			best = node.id
	return best


# 按住拖动并逐帧截屏：预览曲线随鼠标生长，松开后提交。
func _animated_drag(from: Vector2, to: Vector2, frames: int) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	game._unhandled_input(down)
	await _capture(2)
	for i in range(1, frames + 1):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(i) / float(frames))
		motion.relative = to - from
		game._unhandled_input(motion)
		await _capture(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	game._unhandled_input(up)


func _click_node(target: int) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.world.to_screen(game.service.state.nodes[target].pos)
	game._unhandled_input(click)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = click.position
	game._unhandled_input(release)


# 每帧：推进0.1s逻辑，等待渲染完成，保存一张截图。
func _capture(count: int) -> void:
	for _i in range(count):
		if is_instance_valid(game):
			game._process(0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		frame_index += 1
		root.get_texture().get_image().save_png(output_directory + "/frames/f_%04d.png" % frame_index)

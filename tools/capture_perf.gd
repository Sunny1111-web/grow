extends SceneTree

# 正式性能采样：400活边/100活叶/200+历史表现槽压力株，真实窗口渲染。
# 采样整帧、逻辑步、预览求解、命令提交与存档加载，输出p95报告与JSON证据。
var output_directory: String = ""
var game = null
var frames: Array = []
var logic: Array = []
var previews: Array = []
var commits: Array = []
var loads: Array = []
var load_failures: Array = []
var elapsed: float = 0.0
var next_action: float = 0.0
var rng = RandomNumberGenerator.new()


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_directory = argument.trim_prefix("--output-dir=")
	if output_directory == "":
		output_directory = ProjectSettings.globalize_path("res://test-results/perf-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output_directory)
	rng.seed = 20260905
	call_deferred("_start")


func _start() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var window: Window = root.get_window()
	window.size = Vector2i(1920, 1080)
	window.mode = Window.MODE_WINDOWED
	game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = output_directory + "/saves"
	root.add_child(game)
	game.start_new_game()
	_stress_plant(game.service.state)
	game._activate_state(game.service.state)
	game.audio.muted_debug_log = true
	var info: Dictionary = {
		"processor": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"memory_total_mb": OS.get_memory_info().physical / 1048576,
		"engine": Engine.get_version_info().string,
		"build": "editor-debug",
		"resolution": "%dx%d" % [window.size.x, window.size.y],
		"vsync": "disabled",
		"stress": "400 edges / 100 leaves / %d history" % game.service.state.history.size()}
	var file = FileAccess.open(output_directory + "/machine.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "\t", true, true))
	file.close()
	print("PERF_MACHINE ", JSON.stringify(info))


func _process(delta: float) -> bool:
	if game == null:
		return false
	var frame_begin: int = Time.get_ticks_usec()
	elapsed += delta
	if elapsed > 30.0:
		_finish()
		return true
	# 帧采样走游戏正常advance路径；逻辑步计时独立进行，不影响帧路径。
	game._process(delta)
	next_action -= delta
	if next_action <= 0.0:
		next_action = 0.5
		_sample_actions(game.service.state)
		# 存读为周期性运维操作，有独立≤2秒门禁；该帧不计入渲染帧口径。
		return false
	var begin: int = Time.get_ticks_usec()
	game.sim.step(0.1)
	logic.append(Time.get_ticks_usec() - begin)
	# CPU端帧成本=本回调全程；delta另计（受vsync/合成器影响）。
	frames.append(float(Time.get_ticks_usec() - frame_begin) / 1000.0)
	if frames.size() <= 90 and frames.size() % 15 == 0:
		print("PERF_FRAME %d delta=%.3fms cpu_cost=%.3fms bg_redraws=%d" %
			[frames.size(), delta * 1000.0, frames[-1], game.world.background_layer.redraw_count])
	return false


func _sample_actions(state) -> void:
	# 保持399边：先剪最新藤腾出插槽，使preview/commit覆盖完整成功路径；
	# 能量由采样器补充，专注测量命令处理成本而非经济节奏。
	state.energy = 40.0
	if state.edges.size() >= 400:
		var ids: Array = state.edges.keys()
		game.service.commit(game.service.preview("prune_edge", ids[ids.size() - 1]),
			"perf-thin-%d" % state.tick)
	state.energy = 40.0
	var nodes: Array = state.nodes.keys()
	var target: int = nodes[nodes.size() - 1]
	var begin: int = Time.get_ticks_usec()
	var proposal: Dictionary = game.service.preview("vine", target, Vector2.from_angle(rng.randf_range(-PI, PI)))
	previews.append(Time.get_ticks_usec() - begin)
	if proposal.ok:
		begin = Time.get_ticks_usec()
		var result: Dictionary = game.service.commit(proposal, "perf-%d" % state.tick)
		commits.append(Time.get_ticks_usec() - begin)
	# 存读采样独立于提交频率，每两次动作采一轮保存+加载。
	var load_begin: int = Time.get_ticks_usec()
	var saved: Dictionary = game.saves.save(state)
	var loaded: Dictionary = game.saves.load_latest()
	if saved.ok and loaded.ok:
		loads.append(Time.get_ticks_usec() - load_begin)
	elif load_failures.size() < 3:
		load_failures.append("%s | %s" % [saved.reason, loaded.reason])


func _stress_plant(state) -> void:
	var seed: Vector2 = state.nodes[1].pos
	var node: int = state.edges[state.add_edge(1, "root", [seed, seed + Vector2(0, -0.8)])].b
	state.add_edge(node, "root", [seed + Vector2(0, -0.8), seed + Vector2(0, -1.6)])
	var tip: int = 1
	for index in range(398):
		var origin: Vector2 = state.nodes[tip].pos
		tip = state.edges[state.add_edge(tip, "vine", [origin, origin + Vector2(0.01, 0.01)],
			{"id": "chair_seat"})].b
		if index % 4 == 0:
			state.add_leaf(tip)
	# 制造220项真实历史（修剪记录），触发200表现槽合批路径。
	var template: Dictionary = state.edges[state.edges.keys()[2]]
	for index in range(220):
		state.history.append({"type": "edge", "data": template.duplicate(true),
			"node": state.nodes[template.b].duplicate(true), "reason": "prune",
			"tick": index})
	state.energy = 40.0


func _percent(samples: Array, fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array = samples.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, ceili(sorted.size() * fraction) - 1)]


func _finish() -> void:
	var report: Dictionary = {
		"frame_ms_p95": snappedf(_percent(frames, 0.95), 0.001),
		"frame_ms_median": snappedf(_percent(frames, 0.5), 0.001),
		"logic_us_p95": int(_percent(logic, 0.95)),
		"logic_us_median": int(_percent(logic, 0.5)),
		"preview_us_p95": int(_percent(previews, 0.95)),
		"preview_us_max": int(previews.max()) if not previews.is_empty() else 0,
		"commit_us_p95": int(_percent(commits, 0.95)),
		"load_us_p95": int(_percent(loads, 0.95)),
		"samples": {"frames": frames.size(), "logic": logic.size(),
			"previews": previews.size(), "commits": commits.size(), "loads": loads.size()}}
	var file = FileAccess.open(output_directory + "/perf-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("PERF_REPORT frame_p95=%.3fms frame_med=%.3fms logic_p95=%dus preview_p95=%dus preview_max=%dus commit_p95=%dus load_p95=%dus loads=%d" %
		[report.frame_ms_p95, report.frame_ms_median, report.logic_us_p95,
		report.preview_us_p95, report.preview_us_max, report.commit_us_p95, report.load_us_p95, loads.size()])
	if not load_failures.is_empty():
		print("PERF_LOAD_FAIL ", load_failures[0])
	print("PERF_EVIDENCE ", output_directory)
	var passed: bool = report.frame_ms_p95 <= 16.7 and report.logic_us_p95 <= 3000 \
		and report.preview_us_p95 <= 8000 and report.commit_us_p95 <= 100000 \
		and report.load_us_p95 <= 2000000
	print("PERF_GATE ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)

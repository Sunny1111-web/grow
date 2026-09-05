extends RefCounted

const NAMES: Array[String] = ["grow", "leaf", "prune", "snap", "water", "rescue", "victory"]


func run(t) -> void:
	t.check(ResourceLoader.exists("res://scripts/view/audio_bank.gd"), "程序化音源库存在")
	t.check(ResourceLoader.exists("res://scripts/view/audio.gd"), "音频总线节点存在")
	if not ResourceLoader.exists("res://scripts/view/audio_bank.gd"):
		return
	var Bank = load("res://scripts/view/audio_bank.gd")
	for name in NAMES:
		var samples: PackedByteArray = Bank.call(name)
		t.check(samples.size() > 4000, "%s音源非空(%d字节)" % [name, samples.size()])
		t.check(samples.size() % 2 == 0, "%s为16位PCM" % name)
		var peak: float = 0.0
		for i in range(0, samples.size(), 2):
			var value: int = samples[i] | (samples[i + 1] << 8)
			if value >= 32768:
				value -= 65536
			peak = maxf(peak, absf(float(value)) / 32768.0)
		t.check(peak > 0.05 and peak <= 0.95, "%s峰值在(0.05,0.95]: %.3f" % [name, peak])
	var stream: AudioStreamWAV = Bank.stream(Bank.grow())
	t.check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050,
		"流为16位22050Hz")
	var ambient: AudioStreamWAV = Bank.ambient_stream()
	t.check(ambient.loop_mode == AudioStreamWAV.LOOP_FORWARD, "环境音循环")
	_bus_and_volume(t)
	_settings_persistence(t)
	_event_hooks(t)


func _bus_and_volume(t) -> void:
	var Audio = load("res://scripts/view/audio.gd")
	var audio = Audio.new()
	t.root.add_child(audio)
	var ambience: int = AudioServer.get_bus_index("Ambience")
	var sfx: int = AudioServer.get_bus_index("SFX")
	t.check(ambience >= 0 and sfx >= 0, "Ambience与SFX总线存在")
	t.check(AudioServer.get_bus_send(ambience) == "Master" and AudioServer.get_bus_send(sfx) == "Master",
		"两条总线汇入Master")
	audio.set_volume("SFX", 0.5)
	t.near(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.5), 0.01, "音量线性映射分贝")
	audio.set_volume("Ambience", 0.25)
	t.near(AudioServer.get_bus_volume_db(ambience), linear_to_db(0.25), 0.01, "环境音量独立可调")
	audio.set_volume("Master", 1.0)
	audio.play("grow")
	audio.play("snap")
	t.check(true, "headless播放不崩溃")
	audio.free()
	AudioServer.remove_bus(AudioServer.get_bus_index("Ambience"))
	AudioServer.remove_bus(AudioServer.get_bus_index("SFX"))


func _settings_persistence(t) -> void:
	var Audio = load("res://scripts/view/audio.gd")
	var audio = Audio.new()
	audio.settings_path = "res://test-results/audio-settings-%d.cfg" % Time.get_ticks_usec()
	t.root.add_child(audio)
	audio.set_volume("SFX", 0.3)
	audio.set_volume("Ambience", 0.6)
	t.check(audio.save_settings(), "音量设置保存")
	var restored = Audio.new()
	restored.settings_path = audio.settings_path
	t.root.add_child(restored)
	t.near(restored.volume("SFX"), 0.3, 0.0001, "音效音量存读一致")
	t.near(restored.volume("Ambience"), 0.6, 0.0001, "环境音量存读一致")
	restored.free()
	audio.free()
	AudioServer.remove_bus(AudioServer.get_bus_index("Ambience"))
	AudioServer.remove_bus(AudioServer.get_bus_index("SFX"))


func _event_hooks(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_directory = "res://test-results/audio-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	t.check(game.audio != null, "游戏持有音频节点")
	game.audio.muted_debug_log = true
	var point: Vector2 = game.world.to_screen(Vector2(2, -0.8))
	_drag(game, point, game.world.to_screen(Vector2(2, -1.6)))
	t.check(game.audio.played_log.has("grow"), "生长提交播放动作音")
	game.show_pause()
	var sliders: Array = []
	_collect_sliders(game.hud.modal, sliders)
	t.check(sliders.size() == 3, "暂停菜单提供三条音量滑块")
	if sliders.size() == 3:
		sliders[1].value = 0.4
		t.near(game.audio.volume("Ambience"), 0.4, 0.0001, "滑块调节环境音量")
	game.free()


func _collect_sliders(node: Node, found: Array) -> void:
	if node is HSlider:
		found.append(node)
	for child in node.get_children():
		_collect_sliders(child, found)


func _drag(scene, from: Vector2, to: Vector2) -> void:
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	scene._unhandled_input(down)
	var motion = InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	scene._unhandled_input(motion)
	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	scene._unhandled_input(up)

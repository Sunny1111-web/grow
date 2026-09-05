extends Node

const Bank = preload("res://scripts/view/audio_bank.gd")
const BUSES: Array[String] = ["Master", "Ambience", "SFX"]

var settings_path: String = "user://settings.cfg"
var muted_debug_log: bool = false
var played_log: Array = []
var _volumes: Dictionary = {"Master": 1.0, "Ambience": 1.0, "SFX": 1.0}
var _extra: Dictionary = {}
var _ambient_player: AudioStreamPlayer = null


func _ready() -> void:
	_ensure_bus("Ambience")
	_ensure_bus("SFX")
	load_settings()
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = Bank.ambient_stream()
	_ambient_player.bus = "Ambience"
	_ambient_player.volume_db = -6.0
	add_child(_ambient_player)
	_ambient_player.play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func play(sound: String) -> void:
	played_log.append(sound)
	if muted_debug_log:
		return
	var player := AudioStreamPlayer.new()
	player.stream = _bank_stream(sound)
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


static func _bank_stream(sound: String) -> AudioStreamWAV:
	match sound:
		"grow":
			return Bank.stream(Bank.grow())
		"leaf":
			return Bank.stream(Bank.leaf())
		"prune":
			return Bank.stream(Bank.prune())
		"snap":
			return Bank.stream(Bank.snap())
		"water":
			return Bank.stream(Bank.water())
		"rescue":
			return Bank.stream(Bank.rescue())
		_:
			return Bank.stream(Bank.victory())


func set_volume(bus_name: String, linear: float) -> void:
	var clamped: float = clampf(linear, 0.0001, 1.0)
	_volumes[bus_name] = clamped
	var index: int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clamped))


func volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 1.0))


func save_settings() -> bool:
	var config := ConfigFile.new()
	for bus_name in BUSES:
		config.set_value("audio", bus_name, volume(bus_name))
	for key in ["ui_scale", "sensing_toggle", "low_motion"]:
		if _extra.has(key):
			config.set_value("ui", key, _extra[key])
	return config.save(settings_path) == OK


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	for bus_name in BUSES:
		set_volume(bus_name, float(config.get_value("audio", bus_name, 1.0)))
	for key in ["ui_scale", "sensing_toggle", "low_motion"]:
		if config.has_section_key("ui", key):
			_extra[key] = config.get_value("ui", key)


# 通用界面设置存取：与音量共用 settings.cfg。
func set_setting(section: String, key: String, value) -> void:
	if section == "ui":
		_extra[key] = value
	save_settings()


func setting(section: String, key: String, default_value):
	if section == "ui" and _extra.has(key):
		return _extra[key]
	return default_value

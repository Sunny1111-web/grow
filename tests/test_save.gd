extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Level = preload("res://scripts/core/environment.gd")


func run(t) -> void:
	var path: String = "res://scripts/core/save_service.gd"
	t.check(ResourceLoader.exists(path), "Immutable save service exists")
	if not ResourceLoader.exists(path):
		return
	var save_type = load(path)
	var directory: String = "res://test-results/saves-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var saves = save_type.new(directory)
	t.check(not saves.load_latest().found, "No save is reported without silently creating progress")
	var service = Commands.new(Model.create(), Level.new())
	service.commit(service.preview("rescue", 1), "rescue")
	service.state.energy = 7.5
	service.state.leaves.values()[0].produced = 7.5
	service.state.emergency_produced = 7.5
	service.state.scars["1:0"] = {"pos": Vector2(2, -0.8), "node": 1, "slot": 0, "issued": true, "consumed": true, "reason": "prune"}
	service.state.events.append({"type": "memory", "id": "M1"})
	var first: Dictionary = saves.save(service.state)
	t.check(first.ok, "First generation saves successfully: " + first.reason)
	if not first.ok:
		return
	var original: String = FileAccess.get_file_as_string(first.path)
	var loaded: Dictionary = saves.load_latest()
	t.check(loaded.ok and loaded.generation == 1, "Loads latest committed generation")
	t.near(loaded.state.energy, 7.5, 0.000001, "Energy round-trips")
	t.check(loaded.state.nodes[1].pos == Vector2(2, -0.8), "Logical Vector2 round-trips")
	t.check(loaded.state.edges.keys()[0] is int, "Persistent dictionary IDs restored as integers")
	t.check(loaded.state.scars["1:0"].consumed, "Spent scar entitlement remains spent")
	t.near(loaded.state.emergency_produced, 7.5, 0.000001, "Emergency income cap counter persists")
	t.check(loaded.state.validate().is_empty(), "Restored topology validates")
	service.state.energy = 9.0
	var second: Dictionary = saves.save(service.state)
	t.check(second.ok and second.generation == 2 and first.path != second.path, "Second save uses a new generation path")
	t.check(FileAccess.get_file_as_string(first.path) == original, "Old generation byte content remains unchanged")
	_new_file(directory + "/000000000003-interrupted.tmp", "partial write")
	loaded = saves.load_latest()
	t.check(loaded.ok and loaded.generation == 2, "Interrupted temporary file is ignored and retained")
	_new_file(directory + "/000000000003-broken.json", "{broken-json")
	loaded = saves.load_latest()
	t.check(loaded.ok and loaded.generation == 2 and loaded.recovered, "Damaged latest generation falls back with recovery notice")
	t.check(loaded.reason != "", "Recovery is explained to the player")
	t.check(FileAccess.file_exists(directory + "/000000000003-broken.json"), "Damaged evidence remains intact")
	var bad_state = service.state.clone()
	bad_state.nodes[1].pos.x = INF
	t.check(not saves.save(bad_state).ok, "Invalid state refused before writing a new generation")
	var bad_payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(second.path))
	bad_payload.checksum = "invalid"
	_new_file(directory + "/000000000004-checksum.json", JSON.stringify(bad_payload))
	loaded = saves.load_latest()
	t.check(loaded.ok and loaded.generation == 2, "Checksum mismatch cannot load")
	bad_payload = JSON.parse_string(FileAccess.get_file_as_string(second.path))
	bad_payload.schema_version = 999
	_new_file(directory + "/000000000005-future.json", JSON.stringify(bad_payload))
	loaded = saves.load_latest()
	t.check(not loaded.ok and loaded.future_version, "Future schema is explicitly refused rather than silently rolling back")
	t.check(FileAccess.get_file_as_string(first.path) == original, "Validation and recovery never modify old generations")
	_malformed_payloads(t, save_type, directory, second.path)
	_version_protection(t, save_type)
	_schema_migration(t, save_type)
	_guide_persistence(t, save_type)


func _malformed_payloads(t, save_type, directory: String, sample_path: String) -> void:
	var mutations: Array = [
		func(data): data.nodes = {"1": 123},
		func(data): data.edges.values()[0].a = 9999,
		func(data): data.energy = -1,
		func(data): data.nodes.values()[0].parent_edge = 2,
		func(data): data.next_id = 1,
		func(data): data.leaves.values()[0].node = 9999,
		func(data): data.nodes.values()[0].anchor = {"id": "missing_surface"}]
	for index in range(mutations.size()):
		var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sample_path))
		var payload: Dictionary = JSON.parse_string(bad.payload)
		mutations[index].call(payload)
		bad.payload = JSON.stringify(payload, "", true, true)
		bad.checksum = bad.payload.sha256_text()
		var case_dir: String = directory + "/malformed%d" % index
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(case_dir))
		_new_file(case_dir + "/000000000001-case.json", JSON.stringify(bad))
		var result = save_type.new(case_dir).load_latest()
		t.check(not result.ok and result.found, "Malformed state rejected safely: case%d" % index)


func _version_protection(t, save_type) -> void:
	# 未来版本（schema 或规则不同）的世代：显式拒绝并加写入锁，
	# 保证旧规则进度无法覆盖不兼容存档。
	var locked_dir: String = "res://test-results/locked-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var service = Commands.new(Model.create(), Level.new())
	var good: Dictionary = save_type.new(locked_dir).save(service.state)
	t.check(good.ok, "正常世代仍可写入")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(good.path))
	envelope.schema_version = 99
	envelope.payload = envelope.payload
	envelope.checksum = envelope.payload.sha256_text()
	_new_file(locked_dir + "/000000000099-future.json", JSON.stringify(envelope))
	var blocked = save_type.new(locked_dir)
	var loaded: Dictionary = blocked.load_latest()
	t.check(not loaded.ok and loaded.future_version, "未来 schema 被显式拒绝而非回退到旧代")
	t.check(blocked.incompatible_locked, "检测到不兼容存档后进入写入锁")
	t.check(not blocked.save(service.state).ok, "写入锁阻止新世代写入")
	t.check(not save_type.new(locked_dir).save(service.state).ok, "重启后锁仍然生效（标记文件持久化）")
	# 同 schema、异规则版本：同样视为不兼容。
	var rules_dir: String = "res://test-results/rules-%d" % Time.get_ticks_usec()
	var rules_saves = save_type.new(rules_dir)
	var base: Dictionary = rules_saves.save(service.state)
	var rules_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base.path))
	rules_envelope.rules_version = "grow-p0-v999"
	rules_envelope.payload = JSON.stringify(save_type._encode(_state_payload(service.state)), "", true, true)
	rules_envelope.checksum = rules_envelope.payload.sha256_text()
	_new_file(rules_dir + "/000000000002-rules.json", JSON.stringify(rules_envelope))
	var rules_blocked = save_type.new(rules_dir)
	var rules_loaded: Dictionary = rules_blocked.load_latest()
	t.check(not rules_loaded.ok and rules_loaded.future_version, "异规则版本被拒绝且不回退覆盖")
	t.check(not rules_blocked.save(service.state).ok, "异规则存档同样触发写入锁")
	# 错误的关卡ID：按损坏处理，不加载。
	var level_dir: String = "res://test-results/levelid-%d" % Time.get_ticks_usec()
	var level_saves = save_type.new(level_dir, "balcony")
	var level_base: Dictionary = level_saves.save(service.state)
	t.check(level_base.ok and level_base.path.contains("levelid"), "关卡专属存档按 level_id 落盘")
	var wrong_reader = save_type.new(level_dir, "apartment")
	t.check(not wrong_reader.load_latest().ok, "其它关卡的读取器不能加载这份存档")
	var right_reader = save_type.new(level_dir, "balcony")
	t.check(right_reader.load_latest().ok, "对应关卡的读取器正常加载")


func _schema_migration(t, save_type) -> void:
	# schema 1（无 guide 字段）自动迁移到 schema 2，进度不丢。
	var migration_dir: String = "res://test-results/migration-%d" % Time.get_ticks_usec()
	var saves = save_type.new(migration_dir)
	var service = Commands.new(Model.create(), Level.new())
	var first: Dictionary = saves.save(service.state)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first.path))
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	payload.erase("guide")
	envelope.schema_version = 1
	envelope.payload = JSON.stringify(save_type._encode(payload), "", true, true)
	envelope.checksum = envelope.payload.sha256_text()
	var legacy_path: String = migration_dir + "/000000000001-legacy.json"
	_new_file(legacy_path, JSON.stringify(envelope))
	var loaded: Dictionary = save_type.new(migration_dir).load_latest()
	t.check(loaded.ok, "旧 schema 存档可以加载")
	t.check(loaded.state.guide.get("step", -1) == 0, "迁移补齐 guide 字段默认值")
	var resaved: Dictionary = save_type.new(migration_dir).save(loaded.state)
	t.check(resaved.ok, "迁移后的状态可以再保存")


func _guide_persistence(t, save_type) -> void:
	var guide_dir: String = "res://test-results/guide-save-%d" % Time.get_ticks_usec()
	var saves = save_type.new(guide_dir)
	var service = Commands.new(Model.create(), Level.new())
	service.state.guide = {"step": 3, "skipped": false, "helped": true}
	saves.save(service.state)
	var loaded: Dictionary = saves.load_latest()
	t.check(loaded.state.guide.step == 3 and loaded.state.guide.helped, "引导进度随存档往返")
	service.state.guide.skipped = true
	saves.save(service.state)
	loaded = saves.load_latest()
	t.check(loaded.state.guide.skipped, "跳过标记随存档往返")


func _state_payload(state) -> Dictionary:
	var payload: Dictionary = {}
	for field in Model.persistent_fields():
		payload[field] = state.get(field)
	return payload


func _new_file(path: String, text: String) -> void:
	assert(not FileAccess.file_exists(path), "Tests only create unique new files")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

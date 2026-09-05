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


func _new_file(path: String, text: String) -> void:
	assert(not FileAccess.file_exists(path), "Tests only create unique new files")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

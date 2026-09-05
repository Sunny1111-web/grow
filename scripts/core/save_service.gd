extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Level = preload("res://scripts/core/environment.gd")
const SCHEMA: int = 2
const RULES: String = "grow-p0-v1"
const LEVEL_ID: String = "apartment"
const MAX_FILE_BYTES: int = 64 * 1024 * 1024

var directory: String
var level_id: String = LEVEL_ID
# 版本保护：目录里出现未来/异规则世代后暂停写入，防止旧规则进度覆盖它。
var incompatible_locked: bool = false


func _init(save_directory: String = "user://saves/chapter1", level_identifier: String = LEVEL_ID) -> void:
	directory = save_directory.trim_suffix("/")
	level_id = level_identifier
	incompatible_locked = FileAccess.file_exists(directory + "/.incompatible")


func save(state) -> Dictionary:
	if incompatible_locked:
		return {"ok": false, "reason": "这里存有更新版本游戏的进度，已暂停写入以保护它。"}
	var payload: Dictionary = {}
	for field in Model.persistent_fields():
		payload[field] = state.get(field)
	var problem: String = _shape_problem(payload)
	if problem == "":
		var errors: Array = state.validate()
		if not errors.is_empty():
			problem = str(errors[0])
	if problem != "":
		return {"ok": false, "reason": "没有写入无效进度：" + problem}
	var create_error: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if create_error != OK:
		return {"ok": false, "reason": "无法创建存档目录（%d）" % create_error}
	var generation: int = 1
	for filename in _generations():
		generation = maxi(generation, filename.get_slice("-", 0).to_int() + 1)
	var token: String = "%012d-%d-%d" % [generation, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var temporary: String = directory + "/" + token + ".tmp"
	var final_path: String = directory + "/" + token + ".json"
	while FileAccess.file_exists(temporary) or FileAccess.file_exists(final_path):
		token += "-%d" % randi()
		temporary = directory + "/" + token + ".tmp"
		final_path = directory + "/" + token + ".json"
	var payload_text: String = JSON.stringify(_encode(payload), "", true, true)
	var envelope: Dictionary = {"schema_version": SCHEMA, "rules_version": RULES,
		"level_id": level_id, "level_revision": 1, "engine_build": Engine.get_version_info().hash,
		"generation": generation, "checksum": payload_text.sha256_text(), "payload": payload_text}
	var text: String = JSON.stringify(envelope, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return {"ok": false, "reason": "存档超过64MB，已保留现有进度文件"}
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "无法写入新的存档文件（%d）" % FileAccess.get_open_error()}
	file.store_string(text)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "reason": "本次写入未完成，临时文件已保留（%d）" % write_error}
	var verified: Dictionary = _read(temporary)
	if not verified.ok:
		return {"ok": false, "reason": "本次存档未通过回读校验，旧进度仍保留"}
	if FileAccess.file_exists(final_path):
		return {"ok": false, "reason": "目标世代已存在，已保留临时文件"}
	var rename_error: int = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(final_path))
	if rename_error != OK:
		return {"ok": false, "reason": "无法提交本次存档，旧进度仍保留（%d）" % rename_error}
	return {"ok": true, "reason": "已保存 · 第%d代" % generation, "generation": generation, "path": final_path}


func load_latest() -> Dictionary:
	var filenames: Array = _generations()
	if filenames.is_empty():
		return {"ok": false, "found": false, "reason": "没有已提交的存档", "future_version": false}
	filenames.reverse()
	var rejected: int = 0
	for filename in filenames:
		var result: Dictionary = _read(directory + "/" + filename)
		if result.get("future_version", false):
			result.found = true
			return result
		if result.ok:
			result.found = true
			result.recovered = rejected > 0
			result.reason = "最近的存档未能验证，已恢复到第%d代；原文件均已保留。" % result.generation if rejected > 0 else "已继续上次的生长"
			return result
		rejected += 1
	return {"ok": false, "found": true, "future_version": false,
		"reason": "已有存档均未通过校验。可以开始新的生长，原存档仍保留供恢复。"}


func _incompatible(reason: String) -> Dictionary:
	incompatible_locked = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var marker = FileAccess.open(directory + "/.incompatible", FileAccess.WRITE)
	if marker != null:
		marker.store_string(reason)
		marker.close()
	return {"ok": false, "future_version": true, "reason": reason}


func _generations() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		return result
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".json") and file.get_slice("-", 0).is_valid_int():
			result.append(file)
	result.sort_custom(func(a, b):
		var a_generation: int = a.get_slice("-", 0).to_int()
		var b_generation: int = b.get_slice("-", 0).to_int()
		return a_generation < b_generation if a_generation != b_generation else a < b)
	return result


func _read(path: String) -> Dictionary:
	var failure: Dictionary = {"ok": false, "future_version": false, "reason": "存档损坏或结构无效"}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return failure
	var text: String = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return failure
	var envelope: Dictionary = json.data
	if not _number(envelope.get("schema_version")):
		return failure
	if envelope.schema_version > SCHEMA:
		return _incompatible("这份存档来自较新的游戏版本，请使用对应版本继续。原存档未修改。")
	# 同 schema 但规则版本不同：来自另一套规则的进度，同样不许被旧规则覆盖。
	if envelope.schema_version == SCHEMA and str(envelope.get("rules_version", "")) != RULES:
		return _incompatible("这份存档使用了不同规则版本，无法在这里继续。原存档未修改。")
	if envelope.schema_version < 1 or envelope.schema_version > SCHEMA or str(envelope.get("rules_version", "")) != RULES:
		return failure
	if envelope.get("level_id", "") != level_id or envelope.get("level_revision", 0) != 1:
		return failure
	if not envelope.get("payload") is String or not envelope.get("checksum") is String:
		return failure
	if envelope.payload.sha256_text() != envelope.checksum:
		return failure
	if not _number(envelope.get("generation")) or envelope.generation < 1 or float(int(envelope.generation)) != envelope.generation:
		return failure
	if json.parse(envelope.payload) != OK or not json.data is Dictionary:
		return failure
	var decoded = _decode(json.data)
	if not decoded is Dictionary:
		return failure
	if envelope.schema_version < SCHEMA:
		# 旧 schema 迁移：guide 是 v0.1.1 新增的引导进度字段。
		decoded["guide"] = {"step": 0, "skipped": false, "helped": false}
	for field in ["nodes", "edges", "leaves"]:
		if not decoded.get(field) is Dictionary:
			return failure
		var indexed: Dictionary = {}
		for key in decoded[field]:
			if not str(key).is_valid_int():
				return failure
			indexed[str(key).to_int()] = decoded[field][key]
		decoded[field] = indexed
	if _shape_problem(decoded) != "":
		return failure
	var state = Model.new()
	for field in Model.persistent_fields():
		state.set(field, decoded[field])
	if not state.validate().is_empty():
		return failure
	return {"ok": true, "state": state, "generation": int(envelope.generation), "path": path, "future_version": false}


static func _encode(value):
	if value is Vector2:
		return {"$vector2": [value.x, value.y]}
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_encode(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _encode(value[key])
		return result
	return value


static func _decode(value, depth: int = 0):
	if depth > 64:
		return null
	if value is Dictionary:
		if value.size() == 1 and value.has("$vector2"):
			var pair = value["$vector2"]
			if pair is Array and pair.size() == 2 and _number(pair[0]) and _number(pair[1]):
				return Vector2(pair[0], pair[1])
			return null
		var result: Dictionary = {}
		for key in value:
			result[key] = _decode(value[key], depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_decode(item, depth + 1))
		return result
	if value is float and is_finite(value) and absf(value) < 9007199254740991.0 and floor(value) == value:
		return int(value)
	return value


static func _shape_problem(data: Dictionary) -> String:
	for field in Model.persistent_fields():
		if not data.has(field):
			return "缺少状态字段：" + field
	if data.size() != Model.persistent_fields().size():
		return "包含当前版本不认识的状态字段"
	for field in ["energy", "emergency_produced", "victory_time", "dry_hint_time"]:
		if not _number(data[field]) or data[field] < 0.0:
			return "数值字段无效"
	for field in ["revision", "next_id", "tick", "seed_id", "rescue_count"]:
		if not data[field] is int or data[field] < 0:
			return "计数器字段无效"
	if not data.won is bool or data.emergency_produced > 18.000001:
		return "恢复或结尾状态无效"
	for field in ["history", "events", "explored", "revealed"]:
		if not data[field] is Array:
			return "记录集合无效"
	for field in ["nodes", "edges", "leaves", "scars"]:
		if not data[field] is Dictionary:
			return "器官索引无效"
	if not _finite_tree(data):
		return "状态中包含无效数据"
	var allowed_anchors: Dictionary = {}
	for surface in Level.new().surfaces:
		allowed_anchors[surface.id] = true
	for node in data.nodes.values():
		if not node is Dictionary or not _has_types(node, {"id": TYPE_INT, "pos": TYPE_VECTOR2, "parent_edge": TYPE_INT, "kind": TYPE_STRING, "anchor": TYPE_DICTIONARY, "emergency": TYPE_BOOL}):
			return "节点字段无效"
		if not node.anchor.is_empty() and not allowed_anchors.has(node.anchor.get("id", "")):
			return "存档引用了未知支点"
	for edge in data.edges.values():
		if not edge is Dictionary or not _has_types(edge, {"id": TYPE_INT, "a": TYPE_INT, "b": TYPE_INT, "kind": TYPE_STRING, "points": TYPE_ARRAY, "emergency": TYPE_BOOL, "slot": TYPE_INT}):
			return "边字段无效"
		for field in ["length", "z", "bend"]:
			if not _number(edge.get(field)) or edge[field] < 0.0:
				return "枝条数值无效"
		for point in edge.points:
			if not point is Vector2:
				return "枝条曲线无效"
		if edge.slot not in [0, 1]:
			return "生长插槽无效"
	for leaf in data.leaves.values():
		if not leaf is Dictionary or not _has_types(leaf, {"id": TYPE_INT, "node": TYPE_INT, "emergency": TYPE_BOOL}):
			return "叶片字段无效"
		for field in ["angle", "z", "produced"]:
			if not _number(leaf.get(field)):
				return "叶片数值无效"
		if leaf.z < 0.0 or leaf.produced < 0.0 or leaf.produced > 18.000001:
			return "叶片积分无效"
	if not data.guide is Dictionary or not data.guide.get("step", -1) is int or data.guide.step < 0:
		return "引导进度无效"
	if not data.guide.get("skipped", "") is bool or not data.guide.get("helped", "") is bool:
		return "引导进度无效"
	return ""


static func _has_types(object: Dictionary, fields: Dictionary) -> bool:
	for field in fields:
		if not object.has(field) or typeof(object[field]) != fields[field]:
			return false
	return true


static func _number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _finite_tree(value, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value is Vector2:
		return value.is_finite()
	if value is Dictionary:
		for key in value:
			if not _finite_tree(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not _finite_tree(item, depth + 1):
				return false
		return true
	return value is String or value is bool or _number(value)

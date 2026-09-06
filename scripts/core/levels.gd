extends RefCounted

# 关卡注册表：分关目录、场景脚本与解锁链的唯一来源。
# 新增关卡只改这张表，不允许复制第一关的服务代码。

const APARTMENT: String = "apartment"
const BALCONY: String = "balcony"

const DEFINITIONS: Array = [
	{"id": "apartment", "title": "第一章 · 空房间",
		"env_script": "res://scripts/core/environment.gd",
		"save_dir": "user://saves/chapter1", "revision": 1, "order": 0, "unlock_after": ""},
	{"id": "balcony", "title": "第二章 · 断裂的阳台",
		"env_script": "res://scripts/core/environment_balcony.gd",
		"save_dir": "user://saves/chapter2", "revision": 1, "order": 1, "unlock_after": "apartment"}]


static func get_definition(level_id: String) -> Dictionary:
	for definition in DEFINITIONS:
		if definition.id == level_id:
			return definition.duplicate(true)
	return {}


static func env_for(level_id: String):
	var definition: Dictionary = get_definition(level_id)
	if definition.is_empty():
		return null
	return load(definition.env_script).new()


static func save_dir_for(level_id: String, save_root: String = "user://saves") -> String:
	var definition: Dictionary = get_definition(level_id)
	if definition.is_empty():
		return ""
	return save_root.trim_suffix("/") + "/" + str(definition.save_dir).get_file()


static func ordered() -> Array:
	var result: Array = DEFINITIONS.duplicate(true)
	result.sort_custom(func(a, b): return a.order < b.order)
	return result


# 有效世代只增不删：任一合法通关世代都是永久凭证，旧won档无需迁移。
# 缓存每个目录的查询；成功保存时使负缓存失效，UI逐帧不遍历磁盘。
static var _completion_cache: Dictionary = {}


static func invalidate_progress() -> void:
	for key in _completion_cache.keys():
		if not _completion_cache[key]:
			_completion_cache.erase(key)


static func record_completion(level_id: String, save_root: String = "user://saves") -> Dictionary:
	var directory: String = save_dir_for(level_id, save_root)
	if directory == "":
		return {"ok": false, "reason": "未知关卡"}
	var saves = load("res://scripts/core/save_service.gd").new(directory, level_id)
	var completed: bool = saves.has_completed_generation()
	_completion_cache[directory] = completed
	return {"ok": completed, "reason": "已保留通关记录" if completed else "没有有效通关世代"}


static func is_unlocked(level_id: String, save_root: String = "user://saves") -> bool:
	var definition: Dictionary = get_definition(level_id)
	if definition.is_empty():
		return false
	var previous: String = str(definition.get("unlock_after", ""))
	if previous == "":
		return true
	var directory: String = save_dir_for(previous, save_root)
	if not _completion_cache.has(directory):
		record_completion(previous, save_root)
	return bool(_completion_cache.get(directory, false))

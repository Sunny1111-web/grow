extends RefCounted

# 关卡注册表：分关目录、场景脚本与解锁链的唯一来源。
# 新增关卡只改这张表，不允许复制第一关的服务代码。

const APARTMENT: String = "apartment"
const BALCONY: String = "balcony"

const DEFINITIONS: Array = [
	{"id": "apartment", "title": "第一章 · 空房间",
		"env_script": "res://scripts/core/environment.gd",
		"save_dir": "user://saves/chapter1", "order": 0, "unlock_after": ""},
	{"id": "balcony", "title": "第二章 · 断裂的阳台",
		"env_script": "res://scripts/core/environment_balcony.gd",
		"save_dir": "user://saves/chapter2", "order": 1, "unlock_after": "apartment"}]


static func get_definition(level_id: String) -> Dictionary:
	for definition in DEFINITIONS:
		if definition.id == level_id:
			return definition
	return {}


static func env_for(level_id: String):
	var definition: Dictionary = get_definition(level_id)
	if definition.is_empty():
		return null
	return load(definition.env_script).new()


static func save_dir_for(level_id: String) -> String:
	return str(get_definition(level_id).get("save_dir", "user://saves/" + level_id))


static func ordered() -> Array:
	var result: Array = DEFINITIONS.duplicate(true)
	result.sort_custom(func(a, b): return a.order < b.order)
	return result


# 章节解锁：前一关最新存档 won=true 才解锁；无前驱的关卡始终开放。
static func is_unlocked(level_id: String) -> bool:
	var definition: Dictionary = get_definition(level_id)
	if definition.is_empty():
		return false
	var previous: String = str(definition.get("unlock_after", ""))
	if previous == "":
		return true
	var saves = load("res://scripts/core/save_service.gd").new(save_dir_for(previous), previous)
	var loaded: Dictionary = saves.load_latest()
	return loaded.ok and loaded.state.won

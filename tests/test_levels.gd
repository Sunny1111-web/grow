extends RefCounted

const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Levels = preload("res://scripts/core/levels.gd")
const Validator = preload("res://scripts/core/level_validator.gd")
const ApartmentEnv = preload("res://scripts/core/environment.gd")
const BalconyEnv = preload("res://scripts/core/environment_balcony.gd")
const Saves = preload("res://scripts/core/save_service.gd")


func run(t) -> void:
	_registry(t)
	_validator_both_levels(t)
	_balcony_route(t)
	_balcony_multiple_routes(t)
	_per_level_saves(t)


func _registry(t) -> void:
	t.check(Levels.env_for("apartment") is ApartmentEnv, "第一关环境来自注册表")
	t.check(Levels.env_for("balcony") is BalconyEnv, "第二关环境来自注册表")
	t.check(Levels.env_for("missing") == null, "未知关卡返回空")
	t.check(Levels.save_dir_for("balcony") == "user://saves/chapter2", "第二关有独立存档目录")
	var ordered: Array = Levels.ordered()
	t.check(ordered[0].id == "apartment" and ordered[1].id == "balcony", "章节按顺序排列")
	t.check(Levels.is_unlocked("apartment"), "第一章始终解锁")
	t.check(str(Levels.get_definition("balcony").unlock_after) == "apartment",
		"第二章配置为通关第一章后解锁（运行时值取决于本机存档）")


# 关卡检查器 13 项对每一关都要全过。
func _validator_both_levels(t) -> void:
	for definition in Levels.DEFINITIONS:
		var env = load(definition.env_script).new()
		var failures: Array = []
		for report in Validator.validate(env):
			if not report.ok:
				failures.append("%s:%s" % [report.id, report.detail])
		t.check(failures.is_empty(), "%s 检查器全部通过 %s" % [definition.id, str(failures)])


# 两条路径均从正常30E开局，通过生产、真实命令和胜利计时完成。
func _balcony_route(t) -> void:
	var result = load("res://tools/balcony_runner.gd").new().run("upper")
	t.check(result.ok and result.state.won, "阳台上路真实通关：" + result.reason)


func _balcony_multiple_routes(t) -> void:
	var result = load("res://tools/balcony_runner.gd").new().run("lower")
	t.check(result.ok and result.state.won, "阳台下沿真实通关：" + result.reason)
	var anchored: bool = false
	for node in result.state.nodes.values():
		anchored = anchored or node.anchor.get("id", "") == "lower_edge"
	t.check(anchored, "下沿路线真正锚定lower_edge")


func _per_level_saves(t) -> void:
	var root_dir: String = "res://test-results/levels-saves-%d" % Time.get_ticks_usec()
	var apartment = Saves.new(root_dir + "/c1", "apartment")
	var balcony = Saves.new(root_dir + "/c2", "balcony")
	var service = Commands.new(Model.create(), Levels.env_for("apartment"))
	t.check(apartment.save(service.state).ok, "第一关存档写入自己的目录")
	t.check(balcony.save(service.state).ok, "第二关存档写入自己的目录")
	t.check(apartment.load_latest().ok and balcony.load_latest().ok, "两关存档互不干扰")
	var won_state = Model.create()
	won_state.won = true
	apartment.save(won_state)
	t.check(Model.persistent_fields().has("guide"), "guide 属于持久化字段")

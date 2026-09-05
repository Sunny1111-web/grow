extends RefCounted

const Level = preload("res://scripts/core/environment.gd")
const IDS: Array[String] = ["ids_unique", "light_direction", "water_in_soil",
	"key_points_clear", "no_thin_gap", "aquifer_consistent", "opening_root_reach",
	"opening_budget", "rescue_route", "emergency_light_safe", "exit_not_single_span",
	"anchors_valid", "clue_chain"]


func run(t) -> void:
	t.check(ResourceLoader.exists("res://scripts/core/level_validator.gd"), "关卡检查器存在")
	if not ResourceLoader.exists("res://scripts/core/level_validator.gd"):
		return
	var Validator = load("res://scripts/core/level_validator.gd")
	var report: Array = Validator.validate(Level.new())
	var by_id: Dictionary = {}
	for item in report:
		by_id[item.id] = item
	for id in IDS:
		t.check(by_id.has(id), "报告包含检查项: " + id)
	for item in report:
		t.check(item.ok, "当前关卡通过: " + item.id + " " + str(item.get("detail", "")))
	_bad_levels(t, Validator)


func _expect_fail(t, Validator, mutate: Callable, id: String) -> void:
	var env = Level.new()
	mutate.call(env)
	var report: Array = Validator.validate(env)
	for item in report:
		if item.id == id:
			t.check(not item.ok, "破坏后报告失败: " + id + " " + str(item.get("detail", "")))
			return
	t.check(false, "报告包含检查项: " + id)


func _bad_levels(t, Validator) -> void:
	_expect_fail(t, Validator, func(env) -> void:
		env.waters.append({"id": "W1", "aquifer_id": "apartment", "q": 1.0,
			"rect": Rect2(20, -3, 0.6, 0.6)}), "ids_unique")
	_expect_fail(t, Validator, func(env) -> void:
		env.lights[0].direction = Vector2.ZERO, "light_direction")
	_expect_fail(t, Validator, func(env) -> void:
		env.waters[0].rect = Rect2(30, -2.7, 0.6, 0.6), "water_in_soil")
	_expect_fail(t, Validator, func(env) -> void:
		env.obstacles.append({"id": "deco", "rect": Rect2(1.9, -0.95, 0.3, 0.3)}), "key_points_clear")
	_expect_fail(t, Validator, func(env) -> void:
		env.obstacles.append({"id": "thin", "rect": Rect2(2.36, -0.15, 0.03, 0.55)}), "no_thin_gap")
	_expect_fail(t, Validator, func(env) -> void:
		env.waters[1].aquifer_id = "other", "aquifer_consistent")
	_expect_fail(t, Validator, func(env) -> void:
		env.waters[0].rect = Rect2(8.5, -3.4, 0.6, 0.6), "opening_root_reach")
	_expect_fail(t, Validator, func(env) -> void:
		env.waters[0].rect = Rect2(30, -2.7, 0.6, 0.6), "rescue_route")
	_expect_fail(t, Validator, func(env) -> void:
		env.lights[4].intensity = 0.0, "emergency_light_safe")
	_expect_fail(t, Validator, func(env) -> void:
		env.surfaces.append({"id": "hop", "a": Vector2(15.9, 5.9), "b": Vector2(15.9, 6.3),
			"normal": Vector2(-1, 0)}), "exit_not_single_span")
	_expect_fail(t, Validator, func(env) -> void:
		env.surfaces[0].b = env.surfaces[0].a, "anchors_valid")
	_expect_fail(t, Validator, func(env) -> void:
		env.clues[1].pos = Vector2(12, -8), "clue_chain")

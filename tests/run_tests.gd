extends SceneTree

var passed: int = 0
var failed: int = 0


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)


func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s [got %.8f, expected %.8f]" % [message, actual, expected])


func _run() -> void:
	var selected: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--suite="):
			selected = argument.trim_prefix("--suite=")
	var files = DirAccess.get_files_at("res://tests")
	var count: int = 0
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		if selected != "" and file != "test_%s.gd" % selected:
			continue
		count += 1
		print("SUITE: ", file)
		var script = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			check(false, "Suite cannot load: " + file)
			continue
		var suite = script.new()
		var before: int = passed + failed
		suite.run(self)
		check(passed + failed > before, "Suite produced assertions: " + file)
	check(count > 0, "At least one suite selected")
	print("RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

extends SceneTree

const Levels = preload("res://scripts/core/levels.gd")

# 命令行关卡检查入口：
#   godot --headless --path <工程> --script res://tools/validate_level.gd
#   godot --headless --path <工程> --script res://tools/validate_level.gd -- --level=balcony
# 缺省检查全部已注册关卡；任一检查项失败时退出码为1。

func _init() -> void:
	var selected: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			selected = argument.trim_prefix("--level=")
	var failed: int = 0
	var total: int = 0
	for definition in Levels.DEFINITIONS:
		if selected != "" and definition.id != selected:
			continue
		var env = load(definition.env_script).new()
		print("== %s (%s) ==" % [definition.title, definition.id])
		var report: Array = load("res://scripts/core/level_validator.gd").validate(env)
		for item in report:
			print(("%s %s: %s" % ["PASS" if item.ok else "FAIL", item.id, item.detail]))
			if not item.ok:
				failed += 1
		total += report.size()
	print("LEVEL_CHECK %d passed, %d failed" % [total - failed, failed])
	quit(1 if failed else 0)

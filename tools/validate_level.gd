extends SceneTree

# 命令行关卡检查入口：
#   godot --headless --path <工程> --script res://tools/validate_level.gd
# 任一检查项失败时退出码为1，供测试与提交前检查使用。

func _init() -> void:
	var env = load("res://scripts/core/environment.gd").new()
	var report: Array = load("res://scripts/core/level_validator.gd").validate(env)
	var failed: int = 0
	for item in report:
		print(("%s %s: %s" % ["PASS" if item.ok else "FAIL", item.id, item.detail]))
		if not item.ok:
			failed += 1
	print("LEVEL_CHECK %d passed, %d failed" % [report.size() - failed, failed])
	quit(1 if failed else 0)

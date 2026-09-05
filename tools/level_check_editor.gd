@tool
extends EditorScript

# 编辑器内关卡检查：在脚本编辑器中打开本文件，File > Run 执行，
# 报告打印到编辑器输出面板；只报告不修改场景。

func _run() -> void:
	var env = load("res://scripts/core/environment.gd").new()
	var report: Array = load("res://scripts/core/level_validator.gd").validate(env)
	var failed: int = 0
	for item in report:
		var line: String = ("%s %s: %s" % ["PASS" if item.ok else "FAIL", item.id, item.detail])
		if item.ok:
			print(line)
		else:
			push_error(line)
			failed += 1
	print("LEVEL_CHECK %d passed, %d failed" % [report.size() - failed, failed])

extends Node2D

# 轻量覆盖层：选中环、工具点与记忆光。随父级每帧重绘，调用数极少。
var world


func _draw() -> void:
	if world.game == null or world.game.service == null:
		return
	world._draw_selection()
	if world.game.memory_remaining > 0.0:
		world._memory_glow()

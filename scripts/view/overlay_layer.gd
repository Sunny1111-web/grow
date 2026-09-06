extends Node2D

# 最顶层覆盖：选中环、工具点、记忆光、感知与生长预览。
# 预览/感知必须画在这一层：父节点自身的绘制会被背景/植物子层盖住。
var world


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world.game == null or world.game.service == null:
		return
	world.brush = self
	world._draw_selection()
	world._draw_guide_hint()
	if world.game.memory_remaining > 0.0:
		world._memory_glow()
	if world.game.sensing:
		world._sense()
	world._preview()

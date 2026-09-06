extends Node2D

# 静态背景层：仅在相机/缩放/揭示状态变化时重绘；其余帧复用已录制命令。
var world

var _key: Array = []
var redraw_count: int = 0


func mark_dirty() -> void:
	queue_redraw()


func sync() -> void:
	var state = world.game.service.state
	var key: Array = [world.environment_key(), world.get_viewport_rect().size, world.camera, world.unit_scale, state.revealed.duplicate()]
	if key == _key:
		return
	_key = key
	redraw_count += 1
	queue_redraw()


func _draw() -> void:
	if world.game == null or world.game.service == null:
		return
	world.brush = self
	world._background()
	var state = world.game.service.state
	world._atmosphere(state)


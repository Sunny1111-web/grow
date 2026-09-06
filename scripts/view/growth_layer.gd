extends Node2D

# 植物表现层：历史残枝、伤痕、活体、种子与节点标记。
# 波动动画与模拟同为10Hz步进，本层每0.1秒重绘一次；拓扑变化立即标脏。
var world

var _key: Array = []
var _accumulator: float = 0.0


func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator + 0.0000001 >= 0.1:
		_accumulator = 0.0
		queue_redraw()


func sync() -> void:
	var state = world.game.service.state
	var key: Array = [world.environment_key(), world.get_viewport_rect().size, world.camera, world.unit_scale, state.history.size(),
		state.edges.size(), state.leaves.size(), state.tick]
	if key == _key:
		return
	_key = key
	queue_redraw()


func _draw() -> void:
	if world.game == null or world.game.service == null:
		return
	world.brush = self
	var state = world.game.service.state
	world._draw_history(state)
	world._draw_scars(state)
	world._draw_plant(state)
	world._draw_water_waves(state)
	world._draw_seed_and_nodes(state)

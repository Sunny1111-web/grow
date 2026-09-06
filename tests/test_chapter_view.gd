extends RefCounted

const World = preload("res://scripts/view/world_view.gd")
const Background = preload("res://scripts/view/background_layer.gd")
const Growth = preload("res://scripts/view/growth_layer.gd")
const Model = preload("res://scripts/core/plant_state.gd")
const Commands = preload("res://scripts/core/command_service.gd")
const Apartment = preload("res://scripts/core/environment.gd")
const Balcony = preload("res://scripts/core/environment_balcony.gd")

func run(t) -> void:
	var world = World.new()
	var service = Commands.new(Model.create(), Apartment.new())
	world.game = {"service": service}
	t.root.add_child(world)
	var background = Background.new()
	background.world = world
	var growth = Growth.new()
	growth.world = world
	background.sync()
	growth.sync()
	var old_key: Array = growth._key.duplicate()
	world._update_history_slots(service.state)
	world._slots_cache.items = ["previous chapter"]
	service.env = Balcony.new()
	background.sync()
	growth.sync()
	world._update_history_slots(service.state)
	t.check(background.redraw_count == 2, "同相机及揭示状态切关仍重绘背景")
	t.check(old_key != growth._key, "同规模同tick切关仍重绘植物")
	t.check(world._slots_cache.items.is_empty(), "同历史长度切关不保留上一关残枝")
	service.env = Balcony.new()
	background.sync()
	t.check(background.redraw_count == 3, "同章节新环境实例仍使背景失效")
	world.camera = Vector2(100, 100)
	world.clamp_camera()
	t.check(world.camera == service.env.bounds.end, "阳台相机上限来自实际bounds")
	world.camera = Vector2(-100, -100)
	world.clamp_camera()
	t.check(world.camera == service.env.bounds.position, "阳台相机下限来自实际bounds")
	t.check(world.has_method("whitebox_geometry"), "白盒绘制暴露与绘制共用的环境几何")
	if world.has_method("whitebox_geometry"):
		var geometry: Dictionary = world.whitebox_geometry()
		for field in ["obstacles", "surfaces", "lights", "waters", "bounds", "exit_rect"]:
			t.check(geometry[field] == service.env.get(field), "白盒几何对应实际环境：" + field)
	var frame: Dictionary = world.growth_framing()
	t.check(service.env.bounds.has_point(frame.camera), "阳台回放相机位于环境范围内")
	var viewport: Vector2 = world.get_viewport_rect().size
	t.check(service.env.bounds.size.x * frame.scale <= maxf(1, viewport.x - 150) + 0.01,
		"阳台回放宽度容纳完整关卡")
	t.check(service.env.bounds.size.y * frame.scale <= maxf(1, viewport.y - 320) + 0.01,
		"阳台回放高度容纳完整关卡")
	background.free()
	growth.free()
	world.free()

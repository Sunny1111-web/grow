extends SceneTree

func _init() -> void:
	var model = load("res://scripts/core/plant_state.gd")
	var env = load("res://scripts/core/environment.gd").new()
	var solver = load("res://scripts/core/growth_solver.gd")
	var base = model.create()
	var node: int = 1
	for _i in range(2):
		var root: Dictionary = solver.build(base, env, node, "root", Vector2(0, -1))
		node = base.edges[base.add_edge(node, "root", root.points)].b
		env.reveal(base, base.nodes[node].pos)
	node = 1
	for angle in [90.0, 60.0]:
		var growth: Dictionary = solver.build(base, env, node, "vine", Vector2.from_angle(deg_to_rad(angle)))
		node = base.edges[base.add_edge(node, "vine", growth.points, growth.anchor)].b
		print("NODE ", node, " ", base.nodes[node].pos)
	for degree in range(-8, 9):
		var growth: Dictionary = solver.build(base, env, node, "vine", Vector2.from_angle(deg_to_rad(degree)))
		var aim: Vector2 = (growth.points[-1] - growth.points[-2]).normalized()
		var anchor: Dictionary = env.anchor_at(growth.points.back(), aim)
		var attached: Array = []
		if not anchor.is_empty():
			var tangent: Vector2 = (growth.points[1] - growth.points[0]).normalized()
			attached = solver._with_endpoint(base.nodes[node].pos, tangent, aim, anchor.pos, 1.0)
		print("ANGLE ",degree," OK ",growth.ok," end ",growth.points.back()," chosen ",growth.anchor," potential ",anchor," attached ",attached.size()," blocked ",env.blocked(attached,0.04))
	quit()

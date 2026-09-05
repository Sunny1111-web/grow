extends SceneTree

func _init() -> void:
	var model = load("res://scripts/core/plant_state.gd")
	var env = load("res://scripts/core/environment.gd").new()
	var service = load("res://scripts/core/command_service.gd").new(model.create(), env)
	service.commit(service.preview("rescue", 1), "r")
	service.state.energy = 18.0
	var node: int = 1
	for degree in [90.0, 60.0, 0.0]:
		var proposal = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
		print("degree ", degree, " ok ", proposal.ok, " reason ", proposal.reason,
			" start ",service.state.nodes[node].pos," end ",proposal.points.back())
		if not proposal.ok:
			for alternative in range(-15, 16):
				var candidate = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree + alternative)))
				if candidate.ok:
					print("alternative ",degree+alternative," end ",candidate.points.back(), " anchor ",candidate.candidate.nodes[candidate.node].anchor)
			break
		var result = service.commit(proposal, "g%d" % degree)
		node = result.node
	quit()

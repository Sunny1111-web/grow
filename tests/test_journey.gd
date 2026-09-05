extends RefCounted


func run(t) -> void:
	var path: String = "res://tools/journey_runner.gd"
	t.check(ResourceLoader.exists(path), "Complete journey verifier exists")
	if not ResourceLoader.exists(path):
		return
	var result: Dictionary = load(path).new().run()
	t.check(result.ok, "New game can reach a sustainable window ending: " + result.reason)
	if result.ok:
		t.check(result.state.won, "Journey reaches actual simulation victory")
		t.check(result.state.energy >= 0.0 and result.state.validate().is_empty(), "No budget or topology shortcuts")
		t.check(result.q == 20.0, "Journey obtains W2 through living roots")
		t.check(result.actions.size() > 20, "Witness contains actual growth and maintenance decisions")
		print("JOURNEY actions=%d simulated_seconds=%.1f E=%.2f income=%.2f" % [result.actions.size(), result.seconds, result.state.energy, result.income])

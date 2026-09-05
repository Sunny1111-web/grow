extends RefCounted


func run(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	t.check(game.has_method("return_to_title"), "Ending supports a real return-to-title flow")
	if not game.has_method("return_to_title"):
		game.free()
		return
	game.save_directory = "res://test-results/presentation-saves-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	game.service.state.won = true
	game._process(0.1)
	t.check(game.sim.frozen.has("ending"), "Ending camera freezes all economic time")
	t.check(game.hud.modal == null, "Camera shows actual plant before ending card")
	game._process(1.9)
	t.check(game.hud.modal != null, "Ending card appears after2seconds")
	game.resume_game()
	t.check(not game.sim.frozen.has("ending") and not game.sim.frozen.has("menu"), "Continue observing removes ending freeze")
	game.return_to_title()
	t.check(not game.started and game.hud.modal != null and game.load_status.ok, "Returning to title saves and offers continue")
	game.continue_game()
	t.check(game.started and game.service.state.won, "Continuing completed chapter preserves result")
	var state = load("res://scripts/core/plant_state.gd").create(Vector2(8, 0.6))
	state.add_edge(1, "vine", [Vector2(8, 0.6), Vector2(8.5, 0.7)], {"id": "table_left"})
	game._activate_state(state)
	game._process(0.1)
	t.check(game.memory_remaining > 4.8 and game.sim.frozen.has("memory"), "Optional memory begins its5second presentation")
	var tick: int = state.tick
	game._process(1.0)
	t.check(state.tick == tick, "Memory presentation does not secretly spend water or gain energy")
	game._process(4.0)
	t.check(game.memory_remaining <= 0.0 and not game.sim.frozen.has("memory"), "Memory ends and releases time")
	game.free()

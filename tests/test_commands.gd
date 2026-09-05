extends RefCounted

var Model = preload("res://scripts/core/plant_state.gd")
var LevelEnvironment = preload("res://scripts/core/environment.gd")
var Service


func run(t) -> void:
	t.check(ResourceLoader.exists("res://scripts/core/command_service.gd"), "Command service exists")
	if not ResourceLoader.exists("res://scripts/core/command_service.gd"):
		return
	Service = load("res://scripts/core/command_service.gd")
	var service = Service.new(Model.create(), LevelEnvironment.new())
	var initial_id: int = service.state.next_id
	var first = service.preview("root", 1, Vector2(0, -1))
	t.check(first.ok, "Valid root preview")
	for _i in range(100):
		service.preview("root", 1, Vector2(0, -1))
	t.near(service.state.energy, 30.0, 0.0001, "100 cancelled previews spend nothing")
	t.check(service.state.next_id == initial_id and service.state.explored.is_empty(), "Cancelled previews allocate no IDs or knowledge")
	var result = service.commit(first, "first")
	t.check(result.ok and service.state.edges.size() == 1, "One root committed")
	t.near(service.state.energy, 26.0, 0.0001, "Root cost paid exactly once")
	service.commit(first, "first")
	t.near(service.state.energy, 26.0, 0.0001, "Duplicate command cannot charge again")
	result = service.commit(first, "different")
	t.check(not result.ok, "Old revision cannot commit")
	var fresh = service.preview("root", 1, Vector2(0.2, -1))
	fresh.candidate.energy = 40.0
	t.check(not service.commit(fresh, "tamper").ok, "Candidate integrity protects the preview contract")
	t.check(not service.preview("leaf", 1).ok, "Cannot grow ordinary leaf underground")
	t.check(not service.preview("prune_edge", 1).ok, "Seed cannot be pruned")
	_opening(t)
	_slots_and_pruning(t)
	_rescue(t)


func _opening(t) -> void:
	var service = Service.new(Model.create(), LevelEnvironment.new())
	var node: int = 1
	for i in range(2):
		var preview = service.preview("root", node, Vector2(0, -1))
		t.check(preview.ok, "Opening root preview %d" % i)
		var result = service.commit(preview, "root%d" % i)
		t.check(result.ok, "Opening root commit")
		node = result.node
	node = 1
	for degree in [90.0, 60.0, 0.0]:
		var preview = service.preview("vine", node, Vector2.from_angle(deg_to_rad(degree)))
		t.check(preview.ok, "Opening vine: " + preview.reason)
		if not preview.ok:
			return
		var result = service.commit(preview, "vine%.0f" % degree)
		t.check(result.ok, "Opening vine commits")
		node = result.node
	var leaf = service.preview("leaf", node)
	t.check(leaf.ok, "Opening leaf legal: " + leaf.reason)
	service.commit(leaf, "leaf")
	t.near(service.state.energy, 4.0, 0.0001, "Actual opening costs 26E")
	t.near(service.metrics().income, 0.96, 0.0001, "Actual opening produces .96E/sec")
	t.check(service.state.validate().is_empty(), "Opening topology remains valid")
	t.check(not service.preview("leaf", node).ok, "One ordinary leaf slot")


func _slots_and_pruning(t) -> void:
	var state = Model.create(Vector2(3.5, 1.5))
	var env = LevelEnvironment.new()
	env.obstacles = []
	var edge: int = state.add_edge(1, "vine", [Vector2(3.5, 1.5), Vector2(4.5, 1.5)], {"id": "chair_seat"})
	var node: int = state.edges[edge].b
	var service = Service.new(state, env)
	var second = service.preview("vine", node, Vector2(1, 0))
	var committed = service.commit(second, "v1")
	var outgoing: int = committed.edge
	t.check(second.ok and committed.ok, "Grow first slot at shoot")
	var split = service.preview("vine", node, Vector2(0, 1))
	t.near(split.cost, 9.0, 0.0001, "Second outgoing vine includes 4E branch fee")
	service.commit(split, "v2")
	t.check(not service.preview("vine", node, Vector2(1, 1)).ok, "Two occupied shoot slots reject more")
	var old_energy: float = service.state.energy
	var prune = service.preview("prune_edge", outgoing)
	t.check(prune.ok and prune.removed_edges == 1, "Prune identifies target subtree")
	service.commit(prune, "cut1")
	t.near(service.state.energy, old_energy, 0.0001, "Pruning refunds no energy")
	t.check(service.state.history.size() == 1, "Pruning preserves full historical edge")
	var regrow = service.preview("vine", node, Vector2.RIGHT)
	t.near(regrow.cost, 7.0, 0.0001, "First slot scar reduces only base cost by2, preserves split fee")
	var grown = service.commit(regrow, "regrow")
	t.check(grown.ok, "Scar benefit commits")
	service.commit(service.preview("prune_edge", grown.edge), "cut2")
	regrow = service.preview("vine", node, Vector2.RIGHT)
	t.near(regrow.cost, 9.0, 0.0001, "Same slot cannot farm repeated benefit")
	t.check(service.state.validate().is_empty(), "Pruned/regrown tree valid")


func _rescue(t) -> void:
	for energy in [0.0, 3.0, 4.0, 40.0]:
		var state = Model.create()
		state.energy = energy
		var service = Service.new(state, LevelEnvironment.new())
		for count in range(20):
			var rescue = service.preview("rescue", 1)
			t.check(rescue.ok, "Rescue always available")
			t.check(service.commit(rescue, "rescue%d" % count).ok, "Rescue commits repeatedly")
			t.near(service.state.energy, 0.0, 0.0001, "Rescue resets current energy")
			t.check(service.state.edges.size() == 2 and service.state.leaves.size() == 1, "Rescue never accumulates free organs")
			t.check(service.state.validate().is_empty(), "Rescue maintains valid tree")
		var root_id = service.state.edges.keys()[0]
		t.check(not service.preview("prune_edge", root_id).ok, "Emergency root cannot be cut")
		t.check(not service.preview("root", service.state.edges[root_id].b, Vector2.RIGHT).ok, "Emergency root cannot branch")
		t.near(service.metrics().income, 1.0, 0.0001, "Emergency cotyledon produces 1E/sec")

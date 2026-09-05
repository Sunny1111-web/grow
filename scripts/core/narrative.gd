extends RefCounted


static func has_event(state, id: String) -> bool:
	for event in state.events:
		var event_id = event.get("id", "")
		if event_id is String and event_id == id:
			return true
	return false


static func evaluate(state, metrics: Dictionary, env) -> Array:
	var produced: Array = []
	if metrics.water.q > 0.0:
		_once(state, produced, "tutorial_water", "teaching", "根接到了水。选回种子，长藤穿过裂缝；身体会成为你的路。")
	var anchored: bool = false
	var suffering: bool = metrics.support.max_risk > 1.0
	for node in state.nodes.values():
		if not node.anchor.is_empty():
			anchored = true
		if node.kind == "shoot" and node.pos.distance_to(env.memory_position) <= 0.65:
			_once(state, produced, "M1", "memory", "很久以前，有人也在这里等一片叶子展开。", 5.0)
	if anchored:
		_once(state, produced, "tutorial_anchor", "teaching", "缠绕环表示真实支点。从这里再伸展，悬空负载会重新计算。")
	if metrics.ordinary_income >= 0.05:
		_once(state, produced, "tutorial_leaf", "teaching", "叶片开始供能。按住 F 可催生；在感知和预览中，收入与风险会一起暂停。")
	if metrics.water.q >= 20.0:
		_once(state, produced, "tutorial_w2", "teaching", "更好的水脉接入了同一片地下水。总供水现在是20，重复扎根不会复制水量。")
	for leaf in state.leaves.values():
		if leaf.z >= 6.0:
			suffering = true
	if suffering:
		_once(state, produced, "tutorial_prune", "teaching", "有些枝叶开始吃力。按住 Shift 比较剪前与剪后；修剪不返还能量，但能省下维护和负载。")
	return produced


static func _once(state, produced: Array, id: String, type: String, text: String, duration: float = 0.0) -> void:
	if has_event(state, id):
		return
	var event: Dictionary = {"type": type, "id": id, "text": text, "duration": duration, "tick": state.tick}
	state.events.append(event)
	produced.append(event)

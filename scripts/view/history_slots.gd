extends RefCounted

# 200个伤痕/残枝表现槽的显示层合批：最近100项保持单项清晰，更旧的按
# 时间序空间邻近聚类为静态笔触，逻辑历史始终完整保留（TDD §9）。
const CAP: int = 200
const RECENT: int = 100
const MAX_BATCHES: int = 100


static func compute(history: Array) -> Dictionary:
	if history.size() <= CAP:
		return {"merged": false, "batched_count": 0, "batches": [], "items": history}
	var items: Array = history.slice(history.size() - RECENT)
	var older: Array = history.slice(0, history.size() - RECENT)
	var batches: Array = []
	for group in _cluster(older):
		batches.append(_stroke(group))
	return {"merged": true, "batched_count": older.size(), "batches": batches, "items": items}


# 按时间序贪心聚类；组数超上限时扩大半径重跑，最终硬合并最旧的组。
static func _cluster(older: Array) -> Array:
	var radius: float = 1.5
	var groups: Array = []
	for _attempt in range(8):
		groups = []
		for item in older:
			var pos: Vector2 = _item_pos(item)
			if not groups.is_empty() and groups.back().center.distance_to(pos) <= radius:
				var last: Dictionary = groups.back()
				last.center = (last.center * float(last.items.size()) + pos) / float(last.items.size() + 1)
				last.items.append(item)
			else:
				groups.append({"center": pos, "items": [item]})
		if groups.size() <= MAX_BATCHES:
			return groups
		radius *= 1.5
	while groups.size() > MAX_BATCHES:
		var merged: Array = []
		var index: int = 0
		while index < groups.size():
			if index + 1 < groups.size():
				var a: Dictionary = groups[index]
				var b: Dictionary = groups[index + 1]
				var items: Array = []
				items.append_array(a.items)
				items.append_array(b.items)
				merged.append({"center": (a.center * float(a.items.size())
					+ b.center * float(b.items.size())) / float(items.size()), "items": items})
				index += 2
			else:
				merged.append(groups[index])
				index += 1
		groups = merged
	return groups


# 每组生成一次draw_multiline可用的世界坐标线段对：边按折线、叶按菱形标记。
static func _stroke(group: Dictionary) -> Dictionary:
	var lines: PackedVector2Array = PackedVector2Array()
	var edges: int = 0
	var leaves: int = 0
	for item in group.items:
		if item.type == "edge":
			edges += 1
			var points: Array = item.data.points
			for index in range(1, points.size()):
				lines.append(points[index - 1])
				lines.append(points[index])
		else:
			leaves += 1
			var pos: Vector2 = item.pos
			var diamond: Array = [pos + Vector2(0.1, 0), pos + Vector2(0, 0.1),
				pos + Vector2(-0.1, 0), pos + Vector2(0, -0.1)]
			for index in range(4):
				lines.append(diamond[index])
				lines.append(diamond[(index + 1) % 4])
	return {"lines": lines, "members": group.items.size(), "edges": edges, "leaves": leaves}


static func _item_pos(item: Dictionary) -> Vector2:
	if item.type == "edge":
		return item.data.points.back()
	return item.pos

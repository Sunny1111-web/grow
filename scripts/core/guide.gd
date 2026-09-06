extends RefCounted

# 第一章新手引导：选种子→拖根接水→长藤攀附→长叶产能。
# 每次只提示当前一步，完成即推进；进度随 state.guide 持久化，
# 可在菜单重看提示或整体跳过；长时间无进展才追加详细帮助。


const STEPS: Array = [
	{"id": "select", "text": "点击种子（金色圆点）选中它，准备第一段生长。",
		"help": "屏幕下方的按钮可以切换工具；种子位于地板裂缝旁，发光并有金色圆环标记。"},
	{"id": "root", "text": "保持 1 根工具，从种子按住左键向下拖出一段根，松开确认。再从根尖向下拖第二段，接到裂缝深处的水。",
		"help": "根必须沿土壤生长。按住空格可以感知湿润方向；先拖一小段也没关系，根尖可以继续拖。"},
	{"id": "vine", "text": "接水了！按 2 选藤，回到种子向上拖，穿过裂缝继续向上生长。",
		"help": "藤是地上的茎，可以从种子的上方节点继续延伸；悬空太长会吃力，尽量找支点。"},
	{"id": "anchor", "text": "藤尖靠近椅座等家具会自动缠上支点（金色圆环）。有支点的地方可以放心继续伸展。",
		"help": "缠绕环表示真实支点：从这里再生长，悬空负载会以支点为起点重新计算。"},
	{"id": "leaf", "text": "按 3 选叶，点击藤上的节点长出叶片；叶片开始持续提供能量。教学完成，自由生长吧！",
		"help": "叶片只在有光的区域有效；叶尖朝向由光照方向决定。长叶后就能积攒能量强化或修剪。"}]

const IDLE_HELP_SECONDS: float = 45.0
# 每步对应的工具（用于工具栏按钮提示），与 STEPS 一一对应。
const STEP_TOOLS: Array = ["root", "root", "vine", "vine", "leaf"]
# 步骤推进时引导卡的强调反馈语；5 为教学完成。
const STEP_FLASH: Dictionary = {
	1: "✓ 选好了，开始拖根",
	2: "✓ 根接到水了！",
	3: "✓ 藤长出来了",
	4: "✓ 缠住支点了",
	5: "✓ 叶片开始供能，教学完成！"}


# 每帧驱动：推进步序并返回当前提示。changed 表示步序发生推进。
static func evaluate(game) -> Dictionary:
	var state = game.service.state
	var guide: Dictionary = state.guide
	if not guide.get("skipped", false):
		var reached: int = _reached_step(game)
		if reached > int(guide.get("step", 0)):
			guide.step = reached
			guide.helped = false
			game.save_progress()
	elif int(guide.get("step", 0)) < STEPS.size():
		pass
	var active: bool = not guide.get("skipped", false) and int(guide.get("step", 0)) < STEPS.size()
	var message: String = ""
	if active:
		message = str(STEPS[int(guide.step)].text)
	return {"active": active, "message": message, "step": int(guide.get("step", 0))}


# 「重看提示」：返回当前步骤的完整提示；教学已完成则返回纪念文案。
static func replay_message(game) -> String:
	var state = game.service.state
	var step: int = int(state.guide.get("step", 0))
	if state.guide.get("skipped", false) or step >= STEPS.size():
		return "教学已完成。随时可以在感知和预览中暂停观察；修剪能把资源让给重要的枝叶。"
	return str(STEPS[step].text)


# 「长时间无进展」的追加帮助：只对当前步骤追加一次。
static func request_help(game) -> String:
	var state = game.service.state
	if state.guide.get("skipped", false):
		return ""
	var step: int = int(state.guide.get("step", 0))
	if step >= STEPS.size() or state.guide.get("helped", false):
		return ""
	state.guide.helped = true
	game.save_progress()
	return str(STEPS[step].help)


# 玩家跳过整段引导。
static func skip(game) -> void:
	game.service.state.guide.skipped = true
	game.save_progress()


static func _reached_step(game) -> int:
	var state = game.service.state
	if state.edges.size() > 0:
		var has_root: bool = false
		var has_vine: bool = false
		for edge in state.edges.values():
			if edge.kind == "root":
				has_root = true
			elif edge.kind in ["vine", "branch"]:
				has_vine = true
		if has_root:
			var anchored: bool = false
			for node in state.nodes.values():
				if not node.anchor.is_empty():
					anchored = true
			var leaf_grown: bool = false
			for leaf in state.leaves.values():
				if not leaf.emergency:
					leaf_grown = true
			if leaf_grown:
				return 5
			if anchored:
				return 4
			if has_vine:
				return 3
			return 2
	# 尚未长出任何器官：选中种子并开始拖根即完成第一步。
	if game.selected_tool == "root" and game.selected_node == state.seed_id and (game.dragging or not game.proposal.is_empty()):
		return 1
	return 0

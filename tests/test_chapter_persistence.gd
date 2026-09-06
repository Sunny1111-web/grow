extends RefCounted
const Levels = preload("res://scripts/core/levels.gd")
const Save = preload("res://scripts/core/save_service.gd")
const Model = preload("res://scripts/core/plant_state.gd")

func run(t) -> void:
	var definition: Dictionary = Levels.get_definition("apartment")
	definition.title = "changed"
	t.check(Levels.get_definition("apartment").title != "changed", "注册数据深隔离")
	t.check(Levels.save_dir_for("../unknown") == "", "未知ID禁止构造路径")
	t.check(not Save.new("res://test-results/unknown-never-created", "unknown").save(Model.create()).ok, "未知关卡禁止保存")
	var root: String = "res://test-results/chapters-%d" % Time.get_ticks_usec()
	# callv让旧接口仍能编译，红灯先显示既有缺陷。
	if not Levels.get_definition("apartment").has("revision"):
		t.check(false, "注册表必须包含关卡revision及注入目录接口")
		return
	var a: String = Levels.save_dir_for.call("apartment", root)
	var b: String = Levels.save_dir_for.call("balcony", root)
	t.check(a == root + "/chapter1" and b == root + "/chapter2", "分关目录保留兼容名称")
	t.check(not Levels.is_unlocked.call("balcony", root), "未通关锁定第二章")
	var state = Model.create()
	state.energy = 11.0
	state.guide.step = 3
	t.check(Save.new(a).save(state).ok, "第一章保存")
	t.check(not Levels.is_unlocked.call("balcony", root), "普通存档不能解锁")
	state.won = true
	t.check(Save.new(a).save(state).ok, "有效通关世代保存")
	t.check(Levels.is_unlocked.call("balcony", root), "旧won世代自动解锁")
	t.check(Save.new(a).save(Model.create()).ok, "第一章可重新游玩")
	t.check(Levels.is_unlocked.call("balcony", root), "重玩不会丢失已解锁章节")
	Levels._completion_cache.clear()
	t.check(Levels.is_unlocked.call("balcony", root), "重建进程缓存后仍从历史世代恢复解锁")
	var balcony_env = Levels.env_for("balcony")
	var anchored = Model.create()
	anchored.nodes[1].anchor = {"id": balcony_env.surfaces[0].id}
	t.check(Save.new(root + "/balcony-anchor", "balcony").save(anchored).ok, "第二章合法支点按关卡配置接受")
	t.check(not Save.new(root + "/wrong-anchor", "apartment").save(anchored).ok, "第一章拒绝第二章专属支点")
	var other = Model.create()
	other.energy = 23.0
	other.add_leaf(1)
	other.guide.skipped = true
	t.check(Save.new(b, "balcony").save(other).ok, "第二章独立保存")
	var first: Dictionary = Save.new(a).load_latest()
	var second: Dictionary = Save.new(b, "balcony").load_latest()
	t.check(first.ok and second.ok, "两关重新实例化后可读取")
	t.check(first.state.energy == 30.0 and second.state.energy == 23.0, "能量不串档")
	t.check(first.state.leaves.is_empty() and second.state.leaves.size() == 1, "植物不串档")
	t.check(not first.state.guide.skipped and second.state.guide.skipped, "guide不串档")
	var wrong = Save.new(b, "apartment")
	t.check(not wrong.load_latest().ok and not wrong.save(state).ok, "跨关目录禁止读写")
	var future_dir: String = root + "/future"
	var saved: Dictionary = Save.new(future_dir).save(state)
	var bytes: String = FileAccess.get_file_as_string(saved.path)
	var envelope: Dictionary = JSON.parse_string(bytes)
	envelope.level_revision = 999
	var file = FileAccess.open(future_dir + "/000000000002-future.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	var reader = Save.new(future_dir)
	var loaded: Dictionary = reader.load_latest()
	t.check(not loaded.ok and loaded.future_version, "未来关卡revision不能回退")
	t.check(not reader.save(state).ok and not Save.new(future_dir).save(state).ok, "未来关卡锁跨实例持久")
	t.check(FileAccess.get_file_as_string(saved.path) == bytes, "版本保护保留原文件")

	var broken_dir: String = root + "/all-broken"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(broken_dir))
	var broken_file = FileAccess.open(broken_dir + "/000000000001-broken.json", FileAccess.WRITE)
	broken_file.store_string("{broken")
	broken_file.close()
	var broken_reader = Save.new(broken_dir)
	t.check(not broken_reader.load_latest().ok and not broken_reader.save(Model.create()).ok, "全损坏目录读失败后禁止写新档")
	t.check(not Save.new(broken_dir).save(Model.create()).ok, "重建实例也不能绕过损坏目录保护")
	t.check(DirAccess.get_files_at(broken_dir).size() == 1, "失败读写没有新增或覆盖文件")

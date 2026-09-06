extends RefCounted

const Saves = preload("res://scripts/core/save_service.gd")
const Model = preload("res://scripts/core/plant_state.gd")


func run(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	t.check(game.has_method("chapter_status"), "章节入口使用统一可注入存档根目录")
	if not game.has_method("chapter_status"):
		game.free()
		return
	game.save_root = "res://test-results/chapter-flow-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	t.check(not game.is_chapter_unlocked("balcony"), "隔离新档第二章锁定")
	game.start_new_game("apartment")
	game.service.state.energy = 19.0
	game.start_new_game("balcony")
	t.check(game.level_id == "apartment" and game.service.state.energy == 19.0, "锁定章节不能替换当前现场")
	game.start_new_game("../invalid")
	t.check(game.level_id == "apartment", "未知关卡入口拒绝")
	game.service.state.won = true
	t.check(game.save_progress().ok, "已完成第一章保存成功")
	t.check(game.is_chapter_unlocked("balcony"), "完成存档解锁第二章")
	game.start_new_game("balcony")
	t.check(game.level_id == "balcony" and game.service.env.level_id == "balcony", "新开第二章使用阳台环境")
	t.check(game.service.state.energy == 30.0 and game.service.state.edges.is_empty(), "第二章独立种子和30E")
	t.check(game.saves.level_id == "balcony" and game.save_directory.ends_with("/chapter2"), "环境与存档章节一致")
	t.check(game.service.state.guide.skipped, "第二章不重播第一章家具引导")
	game.service.state.energy = 11.5
	t.check(game.save_progress().ok, "第二章独立保存")
	game.continue_game("apartment")
	t.check(game.service.env.level_id == "apartment" and game.service.state.won, "从第二章继续第一章恢复环境和完成状态")
	t.near(game.service.state.energy, 19.0, 0.00001, "第一章能量未被第二章覆盖")
	game.start_new_game("apartment")
	t.check(game.is_chapter_unlocked("balcony"), "重开第一章不会反锁第二章")
	game.continue_game("balcony")
	t.check(game.level_id == "balcony" and game.service.env.level_id == "balcony", "继续第二章仍为阳台")
	t.near(game.service.state.energy, 11.5, 0.00001, "第二章恢复独立能量")
	game.start_new_game()
	t.check(game.service.env.level_id == "balcony" and game.service.state.energy == 30.0, "当前第二章直接重开不回公寓")
	game.return_to_title()
	t.check(not game.started and game.hud.modal != null, "暂停返回章节菜单保存并停止模拟")
	var second = load("res://scenes/main.tscn").instantiate()
	second.save_root = game.save_root
	t.root.add_child(second)
	t.check(second.is_chapter_unlocked("balcony"), "重启仍保留章节解锁")
	second.continue_game("balcony")
	t.check(second.service.env.level_id == "balcony" and second.service.state.energy == 30.0, "重启后通过标题继续第二章")
	second.free()
	game.free()
	_failed_continue(t)


func _failed_continue(t) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_root = "res://test-results/chapter-flow-missing-%d" % Time.get_ticks_usec()
	t.root.add_child(game)
	game.start_new_game()
	game.service.state.won = true
	game.save_progress()
	var before = game.service.state
	game.continue_game("balcony")
	t.check(game.level_id == "apartment" and game.service.state == before, "目标没有存档时继续失败保留原现场")
	t.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(game.chapter_save_dir("balcony"))), "失败续档不暗中创建新局")
	game.free()

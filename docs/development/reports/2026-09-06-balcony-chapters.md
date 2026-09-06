# 2026-09-06 第二关白盒与章节系统（v0.1.2）验证报告

## 范围

第二关《断裂的阳台》白盒原型收尾：上下双路线几何调优、章节注册/解锁/分关存档防串、章节菜单与切换失败保护、绘制缓存跨关隔离；新增四套测试与阳台窗口回放工具。

## 变更

- `environment_balcony.gd`：支点几何再调优（rail_a 左移降低便于开局攀附、post_b 缩短），双路线（upper：rail_a→beam→planter→rail_b→wall_hook→门框；lower：经 lower_edge 下沿绕行）均可真实命令走通并实际胜利。
- `levels.gd`：注册表扩充为章节元数据源（解锁链、存档目录、完成缓存与负缓存失效）。
- `save_service.gd`：level_id 绑定存档目录，跨章恢复校验环境一致性。
- `game.gd`：`start_new_game(level_id)` 防护（锁定章节/未知 ID 不动现场）、`is_chapter_unlocked`、`chapter_status`、`return_to_title` 保存并停模拟。
- 视图层：背景/生长/覆盖分层绘制按关卡刷新，修复绘制缓存串关。
- 新测试：`test_balcony_journey`（4 组真实路线+动作重放）、`test_chapter_flow`、`test_chapter_persistence`、`test_chapter_view`；新工具：`balcony_runner.gd`、`capture_balcony.gd`，`Invoke-Tests.ps1 -BalconyWindow`。

## 证据（2026-09-06 本机复跑）

- 全套测试：**8617 passed, 0 failed**（`run-20260906-103348-236-29ebca`）。
- 关卡检查器：apartment + balcony 共 **26 项全过**。
- 阳台窗口鼠标回放（`-BalconyWindow`，真实输入处理器）：upper 与 lower 均 `won=true, reloaded=true`（28/29 边，6/4 叶），证据 `run-20260906-103453-242-3956ef`。
- 第一章回归：`-JourneyWindow` 与 `-OpeningWindow` 此前复跑通过，章节化未破坏旧关。

## 遗留（转入人工清单）

- 白盒视觉替换为阳台正式美术；真人试玩数据（双路线趣味性、修剪价值、失败续玩）。
- 新玩家首玩数据与独立代码审查（0.1.0 起累积项）。

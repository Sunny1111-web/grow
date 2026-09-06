# 第二关白盒与章节流程实施计划

> 使用 subagent-driven-development 分工实现，test-driven-development 先验证失败，再修复；各模块复审后整体验证。用户已明确授权编码，本轮直接执行。

**目标：** 第二章《断裂的阳台》从正常新局可真实通关，第一章完成后解锁；两章可独立重开、保存和继续。

**架构：** 延续 LevelBase + Levels 注册表、Commands/Simulation 共用规则和不可变世代保存。Game 以完整章节事务切换环境、状态和存档服务；视图从实际环境绘制白盒。

**技术：** 本机 Godot 4.7.2 / GDScript / Compatibility；沿用当前主目录工程，不复制核心服务。

## 约束与验收

- 任何旧文件修订均通过 tools/safe_write.py 先整体迁移到 C:/backup/当日年月日并记日志，不直接删除或覆盖。
- 根4、藤5、叶3、强化6，初始30E/上限40，400边/100叶规则保持。阳台W1=16、W2=20，共享同一水预算。
- 正常路线测试不直接补能量、创建器官或跳过足水/健康3秒通关判定。两条路线必须由真实命令和模拟收入走通。
- 默认保存目录保留 user://saves/chapter1、chapter2，旧第一章数据不迁走；测试使用独立save_root。
- 第一章有效完成记录永久解锁第二章，重开第一章不会反锁。未知关卡不能绕过校验；失败续档保留现场并解释原因。
- 第二关白盒清楚呈现实际支点、碰撞、断口、下沿、光区和出口；不宣称完成最终美术或真人平衡验收。

## 分工与步骤

### A：阳台可通关路线（balcony_complete）

- [x] 新增 tests/test_balcony_journey.gd，先证实当前不补能量路线失败。
- [x] 调整 scripts/core/environment_balcony.gd；新增 tools/balcony_runner.gd，run(route="upper")返回ok/reason/service/sim/actions/simulated_seconds。
- [x] 验证upper/lower两路真实通关和退守收入18E后的恢复，修正 tests/test_levels.gd 中几何探测与完整通关证据的区分。
- [x] 运行 balcony_journey、levels、level_validator 套件并记录限制。

### B：配置、解锁与分关保存（chapter_persistence）

- [x] 新增 tests/test_chapter_persistence.gd，覆盖隔离目录、初始锁定、旧档完成解锁、重开不反锁、错关/未来版本保护。
- [x] Levels.save_dir_for(id, save_root="user://saves")、is_unlocked同参数；record_completion(id,save_root)在完成存档成功后登记。
- [x] 注册表提供独立副本、未知ID拒绝、关卡revision；Save按对应环境校验支点和版本。
- [x] 运行 chapter_persistence、save 套件，存档旧文件字节保持。

### C：白盒表现与绘制缓存（balcony_view）

- [x] 新增 tests/test_chapter_view.gd，覆盖环境变化、同相机切关和实际几何数据源。
- [x] 修改 world_view/background_layer/growth_layer/overlay_layer；真实支点置于可读层，相机使用关卡bounds，历史缓存隔离。
- [x] chapter_view套件通过，窗口截图由主线程统一验证。

### D：章节入口与集成（主线程）

- [x] 新增 tests/test_chapter_flow.gd，验证新开/继续第二关用balcony环境、两关状态隔离、锁定/失败切换保留当前关。
- [x] Game集中切换关卡，注入save_root；开始、重开和继续均解析注册环境；通关卡可进入下一关；暂停可保存返回章节菜单。
- [x] HUD章节状态使用同一save_root；切关刷新章节标题，不读取真实用户档干扰测试；第二关不播放第一关椅座教学。
- [x] 使用真实窗口回放第二关、第一章回归；存读后关卡ID/植物/guide一致。
- [x] 独立代码复审，修正重要问题，更新README/验收报告并阶段性本地Git提交。

## 执行命令

工作目录 D:/game/GameDev/Projects/Grow。使用 `./tools/Invoke-Tests.ps1 -Suite <套件名>`；窗口验证使用相同引擎的脚本入口，输出到唯一test-results目录。遇到SCRIPT ERROR、ERROR或FAIL均视为失败，不能只检查Godot退出码。

## 完成门槛

正常第一关存档能继续；未完成第一关不能进入第二关；有效完成后永久开放。第二关两路真实通关，标题/暂停/通关入口齐全，分关继续与重开不串档；白盒显示和碰撞对应；相关回归通过。性能波动与原有未覆盖的真人验收单列，不以它们替代本轮功能验证。

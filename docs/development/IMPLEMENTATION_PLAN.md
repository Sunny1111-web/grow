# Grow P0 开发计划

> 实施方式：按 subagent-driven-development 分工与审查；核心行为先写失败测试，再实现，再用真实 Godot 验证。用户已要求完成开发并阶段性提交 Git，本计划直接执行。

**目标：** 完成设计文档定义的 Windows 单机第一章，从固定种子生长到窗外，提供可恢复的失败与可独立运行的导出包。

**架构：** 植物为纯数据树，候选命令在副本上求解、确认后原子提交。水、光、结构、环境几何各自有确定性求解器；Godot 场景负责输入、呈现、教学和音频。存档为不可变世代。

**技术：** Godot 4.7.2、GDScript、Compatibility，原生 headless 测试入口，无运行时第三方依赖。

## 全局约束

- 依据 docs/design-v1 中 GDD、TDD、美术指南和 PM；P0 全部机制是交付范围，P1/P2 不属于当前承诺。
- 逻辑坐标 y 向上，1u=100px；显示统一转换。模拟固定 0.1 秒，所有收益与损伤一起冻结/加速。
- 初始 E=30、上限40；根4、藤5、叶3、地上第二分枝附加4、强化6；修剪免费返还0。
- 段长根0.8u、藤1u；400活边、100活叶、200历史表现槽；水同含水层取最大Q，W1=12、W2=20。
- 严禁直接删除、覆盖既有文件内容。修订前完整迁移至 C:/backup/当日年月日 的唯一目标，再写新文件；追加 C:/backup/log.txt 的原路径与目标路径。测试和构建使用唯一结果目录。
- 分阶段本地 Git 提交，禁止自动推送。测试通过仅证明其覆盖范围，不能替代首玩、视觉、导出和性能验收。

## 任务与阶段门禁

### 阶段 0：可复现的工程与设计基线

- [ ] 提交现有正式设计、上下文、图示、计划和忽略规则，建立 grow-p0 开发工作区。
- [ ] 创建 project.godot、空主场景和 tests/run_tests.gd，测试 runner 在缺少核心模型时明确退出1。
- [ ] 建立纯数据接口和安全写入工具，使用独立文件边界分工。
- [ ] headless 导入与测试入口能被本机 Godot 加载；记录引擎 build。

### 阶段 1：树、环境与资源求解

文件：scripts/core/plant_state.gd、growth_solver.gd、environment.gd、water_solver.gd、support_solver.gd、light_solver.gd；tests/test_core.gd、test_geometry.gd、test_solvers.gd。

- [ ] 用初始30E、唯一ID、树连通、深拷贝隔离测试建立 PlantState。
- [ ] 用薄墙、全段土壤、0.8/1u长度、同输入确定性测试建立 Environment/GrowthSolver。
- [ ] 水完整手算13.5537、W1/W2不叠加、最远叶比例0.84945、剪接点回退，证明共享预算与路径损耗。
- [ ] 三水平藤末叶 risk>1.5、强化首段后0.75、锚点阻断负载，证明结构求解。
- [ ] 自叶不遮光、墙全遮、每层叶0.5、光区取max，证明光求解。
- [ ] 检查测试失败原因是行为缺失，实现后同命令通过；审查并提交阶段1。

### 阶段 2：可操作的核心循环

文件：scripts/core/command_service.gd、simulation.gd、scripts/game.gd、scripts/view/world_view.gd、scripts/view/hud.gd、scenes/main.tscn。

- [ ] 写预览不改状态、旧revision拒绝、command_id去重、槽位、资源与上限测试。
- [ ] 实现根藤叶强化、分叉、锚点、修剪子树、一次侧芽优惠、历史保存。
- [ ] 写r=0/0.5/1的6/12/24积分与risk1.25的8秒断裂测试；实现10Hz模拟、嵌套冻结及F规则。
- [ ] 接入鼠标选择/拖拽与两次点击确认、Tab重叠选择、快捷键、预览影响、中文反馈、相机。
- [ ] 以实际命令回放两根三藤一叶，证明成本26且正常产能；保存运行截图与流程证据，审查并提交阶段2。

### 阶段 3：恢复、保存与完整关卡

文件：scripts/core/save_service.gd、scripts/core/level_validator.gd、scripts/view/tutorial.gd、tests/test_recovery.gd、test_save.gd、test_journey.gd。

- [ ] 测试所有能量状态可退守、满上限可退守、重复20次不累计、18E恢复首叶；实现固定2根1应急子叶。
- [ ] 实现感知揭示、地下连续提示、水壶一次记忆、当前健康活藤抵达窗外3模拟秒结尾。
- [ ] 测试不可变世代、校验、损坏代回退、未来版本拒绝、无效拓扑拒绝；实现自动/手动保存与继续。
- [ ] 关卡检查器检查ID、预算、安全路线、土壤、光方向、缝隙、锚点和出口。
- [ ] 完整从新游戏到结尾回放，危机修剪恢复回放，菜单与输入冻结检查，审查并提交阶段3。

### 阶段 4：视觉、音频与 Windows 交付

文件：assets/、scripts/view/、export_presets.cfg、tools/、README.md、docs/development/ACCEPTANCE.md。

- [ ] 按美术指南制作植物、废墟、光水、伤痕、UI和状态表现，加入可独立调节音量的环境/动作音。
- [ ] 真实窗口截图检查1080p与缩放排版、点击区域、预览与植物一致、颜色外的状态提示。
- [ ] 400边/100叶/200历史压力基准，记录机器、帧/逻辑/预览/加载p95，解决超预算项。
- [ ] 安装匹配本地模板至新目录，导出唯一版本Windows包；脱离编辑器启动并通关验证。
- [ ] 提供操作说明、变更记录、许可表与已知限制；根据规格逐项审查剩余门禁，人工新玩家测试结果必须单列，禁止虚构。
- [ ] 最终审查并提交交付版本，保留所有历史；未验证项目留在验收账本，不能声称全部完成。

## 测试命令

```powershell
& 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe' --headless --path '<开发工作区>' --editor --import
& 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe' --headless --path '<开发工作区>' --script res://tests/run_tests.gd
```

测试入口打印每项断言与合计，任一失败退出1。独立模块测试接受脚本参数。阶段状态和提交哈希追加记录在 PROGRESS.md，详细边界约定见 CORE_CONTRACT.md。

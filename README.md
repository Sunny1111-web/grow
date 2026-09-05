# Grow · 向光而生

Godot 4.7.2 / GDScript / Compatibility。一个以生长代替移动、以修剪重新分配资源的二维探索游戏。

开发分支 `grow-p0`，工作区位于原 Grow 仓库的 `.worktrees/grow-p0`。正式规格在 [docs/design-v1](docs/design-v1/README.md)，实施进展在 [开发账本](docs/development/PROGRESS.md)。当前版本已打通第一章开局、通关、存档与继续流程，音频与音量设置、历史合批、关卡检查器与性能门禁已落地，Windows 独立包已发布并通过脱离编辑器的人工通关验证。

## 版本记录

- **0.1.1（2026-09-06）**：稳定性与体验完善。存档版本保护（未来/异规则存档拒绝加载并锁定写入，不会被旧规则进度覆盖；schema 1 存档自动迁移）；预览候选指纹校验与锚点深拷贝隔离（改写候选无法提交）；结尾运镜输入闸断与模态感知释放（空格/Esc/切窗不再永久暂停或跳过结尾卡）；接水/攀附/W2/危机提示即时落盘；完整预览 p95≤8ms 进测试门禁（弧长缓存+候选指纹+光照复用）；感知高亮选中供水路径、遮光叶标记与 HUD 选中状态行；界面缩放/感知切换/低动态设置；第一章 5 步新手引导（可重看、可跳过、随存档保存、无进展追加帮助）。第二关《断裂的阳台》白盒原型：关卡注册表、章节解锁、分关存档与两关 13 项检查器。已知限制见 [人工验证清单](docs/development/MANUAL_CHECKS.md)。
- **0.1.0（2026-09-05）**：P0 第一章「空房间」。两根接水、三藤开局、锚点攀附、W2 线索链、修剪与伤痕、退守种子、不可变世代存档、窗外通关与镜头回顾。程序化音频（7 动作音 + 循环环境声）与暂停菜单音量设置；200 表现槽历史合批；关卡检查器 13 项报告（`tools/validate_level.gd`）；性能达逻辑步 p95≤3ms、全量求解 p95≤8ms。Windows x86_64 独立包（`build/grow-0.1.0-windows/Grow.exe`，嵌入 PCK）经脱离编辑器真人通关验证（第75代存档校验和匹配、won=true、零退守一次通关）。已知限制：程序绘制美术路线、性能整帧 p95 待正式采样、存档断电持久性不作保证。

## 独立包

发布物为 `build/grow-0.1.0-windows/Grow.exe`（x86_64，嵌入数据包，无外部依赖），双击即玩。重新导出：

```powershell
& 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'd:/game/GameDev/Projects/Grow/.worktrees/grow-p0' --export-release 'Windows Desktop'
```

导出模板为同版本 `Godot_v4.7.2-stable_export_templates.tpz` 解压至 Godot 用户模板目录。资产许可见 [assets/LICENSES.md](assets/LICENSES.md)。

## 启动（开发）

用本机 Godot 打开 `project.godot` 并按 F5，或在本目录运行：

```powershell
& 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe' --path .
```

点击“开始生长”。从种子向下拖出两段根接水，再选回种子，向上穿过裂缝、向右上和右侧攀上椅座。长出叶子后获得持续能量。

| 操作 | 输入 |
| --- | --- |
| 根 / 藤 / 叶 / 强化 | 1 / 2 / 3 / 4，或底部按钮 |
| 根与藤生长 | 从节点按住左键拖出方向，松开确认 |
| 叶与强化 | 选择工具显示预览，再次点击目标确认 |
| 取消预览 | 右键或 Esc |
| 修剪 | 按住 Shift，点击高亮叶或枝 |
| 感知 | 按住空格 |
| 催生 | 按住 F，同时加速收入与风险，到够用或危险时自动停止 |
| 平移 / 缩放 / 回选中点 | 中键拖动 / 滚轮 / Home |
| 重叠目标切换 | Tab |
| 保存 / 继续 | F5 或暂停菜单保存；标题页按章节继续上次进度 |
| 暂停 / 退守种子 | Esc 或右上按钮；暂停菜单提供退守预览 |

设置（暂停菜单）：界面缩放、感知方式（按住空格 / 点击切换）、低动态效果，均随 `settings.cfg` 持久化。通关第一章后，标题页解锁第二章《断裂的阳台》（白盒原型）。

## 验证

```powershell
./tools/Invoke-Tests.ps1
./tools/Invoke-Tests.ps1 -Suite commands
./tools/Invoke-Tests.ps1 -OpeningWindow
./tools/Invoke-Tests.ps1 -JourneyWindow
```

脚本把日志和截图写入唯一的 `test-results/run-*`，遇到 Godot 脚本/渲染错误或失败断言都会返回非零。窗口回放通过实际输入处理器完成首叶，并核对器官数与产能；完整窗口回放进一步验证第二水源、支点与强化、健康足水3秒的窗外结尾、镜头回顾以及保存后继续。它们不能替代新玩家测试。

存档默认在 Godot 的 `user://saves/chapter1`，每代使用新文件；F5、每10条有效命令、首片有效叶、退守、记忆、结尾与正常退出会保存。坏代会回退并提示，未来格式会拒绝加载。测试和窗口回放使用 `test-results` 内的独立存档目录。

所有修订先完整备份原件至 `C:/backup/当日年月日` 并追加迁移日志，不直接删除旧内容。Git 按阶段提交，仅本地，不自动推送。

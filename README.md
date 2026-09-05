# Grow · 向光而生

Godot 4.7.2 / GDScript / Compatibility。一个以生长代替移动、以修剪重新分配资源的二维探索游戏。

开发分支 `grow-p0`，工作区位于原 Grow 仓库的 `.worktrees/grow-p0`。正式规格在 [docs/design-v1](docs/design-v1/README.md)，实施进展在 [开发账本](docs/development/PROGRESS.md)。当前为开发中的可操作版本，尚未完成全部关卡与发布验收。

## 启动

用本机 Godot 打开 `project.godot` 并按 F6/F5（运行整个项目用 F5），或在本目录运行：

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
| 暂停 / 退守种子 | Esc 或右上按钮；暂停菜单提供退守预览 |

## 验证

```powershell
./tools/Invoke-Tests.ps1
./tools/Invoke-Tests.ps1 -Suite commands
./tools/Invoke-Tests.ps1 -OpeningWindow
```

脚本把日志和截图写入唯一的 `test-results/run-*`，遇到 Godot 脚本/渲染错误或失败断言都会返回非零。窗口回放通过实际输入处理器完成首叶，并核对器官数与产能；它不能替代新玩家测试。

所有修订先完整备份原件至 `C:/backup/当日年月日` 并追加迁移日志，不直接删除旧内容。Git 按阶段提交，仅本地，不自动推送。

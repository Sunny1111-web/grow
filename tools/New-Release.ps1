param(
	[string]$Version = '0.1.2',
	[string]$EnginePath = 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe'
)

# 发布流程：导出 release -> 打包 zip -> 输出上传指引。
# 用法: ./tools/New-Release.ps1 -Version 0.1.3
$ErrorActionPreference = 'Stop'
$projectPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stageDir = Join-Path $projectPath "build/grow-$Version-windows"
$zipPath = Join-Path $projectPath "build/grow-$Version-windows.zip"

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
& $EnginePath --headless --path $projectPath --export-release 'Windows Desktop'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $stageDir 'Grow.exe'))) {
	throw 'release 导出失败'
}
Compress-Archive -Path (Join-Path $stageDir 'Grow.exe') -DestinationPath $zipPath -Force
$zip = Get-Item $zipPath
Write-Host ("安装包已生成: {0} ({1:N1} MB)" -f $zip.FullName, ($zip.Length / 1MB))

$notesPath = Join-Path $stageDir 'release-notes.md'
@(
	"## Grow · 向光而生 v$Version",
	'',
	'Windows x86_64 独立包，双击 Grow.exe 即玩，无需安装。',
	'详见仓库内 docs/游戏说明.md。'
) | Set-Content -Path $notesPath -Encoding UTF8
Write-Host "发布说明已生成: $notesPath"

if (Get-Command gh -ErrorAction SilentlyContinue) {
	Write-Host "上传命令:`n  gh release create v$Version `"$zipPath`" --title `"Grow v$Version`" --notes-file `"$notesPath`""
} else {
	Write-Host @'
未检测到 gh CLI。二选一上传:
1) 网页: GitHub 仓库 -> Releases -> Draft a new release
   - Tag: v<版本> (指向 master 最新提交)
   - 标题: Grow v<版本>
   - 描述: 粘贴 release-notes.md 内容
   - 拖入 grow-<版本>-windows.zip -> Publish release
2) 安装 gh 后执行: winget install GitHub.cli; gh auth login
   然后重跑本脚本获取现成上传命令。
'@
}

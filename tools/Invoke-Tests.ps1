param(
    [string]$Suite = '',
    [string]$EnginePath = 'D:/game/GameDev/Tools/GoDot/Godot_v4.7.2-stable_win64_console.exe',
    [switch]$OpeningWindow,
    [switch]$JourneyWindow,
    [switch]$BalconyWindow
)

$ErrorActionPreference = 'Stop'
if (([int][bool]$OpeningWindow + [int][bool]$JourneyWindow + [int][bool]$BalconyWindow) -gt 1) { throw 'Choose one window verification mode.' }
$projectPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
    throw "Godot executable not found: $EnginePath"
}
$runName = 'run-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$resultPath = Join-Path $projectPath ('test-results/' + $runName)
New-Item -ItemType Directory -Path $resultPath | Out-Null
$engineArgs = @('--headless', '--path', $projectPath, '--script', 'res://tests/run_tests.gd')
if ($Suite) { $engineArgs += @('--', "--suite=$Suite") }
if ($OpeningWindow) {
    $imagePath = (Join-Path $resultPath 'first-leaf.png').Replace('\', '/')
    $engineArgs = @('--path', $projectPath, '--script', 'res://tools/capture_opening.gd', '--', "--output=$imagePath")
}
if ($JourneyWindow) {
    $engineArgs = @('--path', $projectPath, '--script', 'res://tools/capture_journey.gd', '--', "--output-dir=$($resultPath.Replace('\', '/'))")
}
if ($BalconyWindow) {
    $engineArgs = @('--path', $projectPath, '--script', 'res://tools/capture_balcony.gd', '--', "--output-dir=$($resultPath.Replace('\', '/'))")
}
$captured = & $EnginePath @engineArgs 2>&1
$processExit = $LASTEXITCODE
$logText = ($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
$logPath = Join-Path $resultPath 'godot.log'
$stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
$writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
try { $writer.WriteLine($logText) } finally { $writer.Dispose() }
Write-Output $logText
Write-Output "Evidence: $resultPath"
# Godot script/render errors can otherwise leave the process exit code at zero.
if ($processExit -ne 0 -or $logText -match '(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)') { exit 1 }
if (-not $OpeningWindow -and -not $JourneyWindow -and -not $BalconyWindow -and $logText -notmatch 'RESULT: \d+ passed, 0 failed') { exit 1 }
if ($OpeningWindow -and $logText -notmatch 'INPUT_OPENING edges=5 leaves=1 income=0.96') { exit 1 }
if ($JourneyWindow -and $logText -notmatch 'INPUT_JOURNEY won=true .* reloaded=true') { exit 1 }
if ($BalconyWindow -and $logText -notmatch 'INPUT_BALCONY routes=2 won=true reloaded=true') { exit 1 }
exit 0

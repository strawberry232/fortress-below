param(
    [string]$GodotPath = $env:GODOT_EXE,
    [string]$PythonPath = 'python',
    [string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$gameProject = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Get-Command $PythonPath -ErrorAction SilentlyContinue)) {
    $PythonPath = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path (Split-Path -Parent $gameProject) ('builds\fortress-v1.8-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$templatePath = Join-Path $gameProject 'tools\export_templates\fortress_2d_4.7.2.exe'
if (-not (Test-Path -LiteralPath $templatePath)) { throw 'Build the custom 2D template first.' }
$releaseProject = Join-Path $OutputRoot 'release_project'
$binaryDirectory = Join-Path $OutputRoot 'windows'
$title = -join @([char]0x5821, [char]0x5792, [char]0x4E4B, [char]0x4E0B)
New-Item -ItemType Directory -Path $binaryDirectory -Force | Out-Null
& $PythonPath (Join-Path $PSScriptRoot 'prepare_release.py') --source $gameProject --output $releaseProject --template $templatePath
if ($LASTEXITCODE -ne 0) { throw 'Release staging failed.' }
& $GodotPath --headless --editor --path $releaseProject --import *> (Join-Path $OutputRoot 'import.log')
if ($LASTEXITCODE -ne 0) { throw 'Release import failed. See import.log.' }
& $GodotPath --headless --path $releaseProject --export-release 'Windows Desktop' (Join-Path $binaryDirectory ($title + '.exe')) *> (Join-Path $OutputRoot 'export.log')
if ($LASTEXITCODE -ne 0) { throw 'Release export failed. See export.log.' }
& $PythonPath (Join-Path $PSScriptRoot 'package_release.py') --project $gameProject --binaries $binaryDirectory --output $OutputRoot
if ($LASTEXITCODE -ne 0) { throw 'Playable archive packaging failed.' }

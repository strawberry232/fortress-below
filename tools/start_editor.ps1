[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_EXE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $GodotPath) {
    $localEnginePath = Join-Path $projectRoot '.gdmcp/godot-path.txt'
    if (Test-Path -LiteralPath $localEnginePath) {
        $GodotPath = (Get-Content -LiteralPath $localEnginePath -Raw).Trim()
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Set GODOT_EXE or pass -GodotPath with the installed Godot executable.'
}
& $GodotPath --headless --path $projectRoot -s 'res://tools/setup_mcp.gd'
if ($LASTEXITCODE -ne 0) {
    throw 'MCP setup failed. Existing settings have been preserved.'
}
& $GodotPath --editor --path $projectRoot

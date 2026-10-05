[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_EXE)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $GodotPath) { $GodotPath = (Get-Content -LiteralPath (Join-Path $projectRoot '.gdmcp/godot-path.txt') -Raw).Trim() }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Godot executable not found.' }
$settings = Get-Content -LiteralPath (Join-Path $projectRoot 'config/mcp_settings.cfg') -Raw
$portMatch = [regex]::Match($settings, '(?m)^http_port=(\d+)\s*$')
if (-not $portMatch.Success) { throw 'The project MCP port is missing.' }
$baseUrl = 'http://127.0.0.1:' + $portMatch.Groups[1].Value
$cli = Join-Path $projectRoot '.gdmcp/bin/gdmcp.exe'
$temporaryRoot = Join-Path $PSScriptRoot ('.tmp_connection_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
$editorProcess = $null
$stdoutPath = Join-Path $temporaryRoot 'editor.log'
$stderrPath = Join-Path $temporaryRoot 'editor-errors.log'
function Invoke-ProjectCli([string[]]$Arguments) {
    $response = & $cli --url $baseUrl --json @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'A gdmcp check failed.' }
    return ($response | ConvertFrom-Json)
}
try {
    & $GodotPath --headless --path $projectRoot -s 'res://tools/setup_mcp.gd'
    if ($LASTEXITCODE -ne 0) { throw 'MCP configuration failed.' }
    $editorProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--editor', '--path', ('"{0}"' -f $projectRoot), 'res://game/scenes/main.tscn') -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $doctor = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($editorProcess.HasExited) { throw 'The test editor exited before MCP became ready.' }
        try { $doctor = Invoke-RestMethod -Uri ($baseUrl + '/cli/v1/doctor') -TimeoutSec 2; break } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $doctor -or -not $doctor.editor_connected) { throw 'The MCP editor connection timed out.' }
    $reportedRoot = [IO.Path]::GetFullPath($doctor.project_path).TrimEnd('\', '/')
    if ($reportedRoot -ne $projectRoot.TrimEnd('\', '/')) { throw 'The MCP server belongs to a different project.' }
    $cliDoctor = Invoke-ProjectCli @('doctor')
    $editorState = Invoke-ProjectCli @('editor', 'state')
    $currentScene = Invoke-ProjectCli @('scenes', 'current')
    if (-not $editorState.ok -or -not $currentScene.ok) { throw 'Editor and scene queries must succeed.' }
    $sceneTree = Invoke-ProjectCli @('scenes', 'tree', '--depth', '3')
    if (-not $sceneTree.ok) { throw 'Scene inspection must succeed.' }
    $sceneList = Invoke-ProjectCli @('scenes', 'list', '--limit', '3')
    if (-not $sceneList.ok) { throw 'Supplementary CLI scene listing must succeed.' }
    $initializeBody = @{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-11-25';capabilities=@{};clientInfo=@{name='gamedemo-check';version='1.0'}}} | ConvertTo-Json -Depth 6
    $initialized = Invoke-RestMethod -Uri ($baseUrl + '/mcp') -Method Post -ContentType 'application/json' -Body $initializeBody -TimeoutSec 5
    if (-not $initialized.result.serverInfo) { throw 'The MCP transport must initialize successfully.' }
    $callBody = @{jsonrpc='2.0';id=2;method='tools/call';params=@{name='get_project_info';arguments=@{}}} | ConvertTo-Json -Depth 6
    $mcpProject = Invoke-RestMethod -Uri ($baseUrl + '/mcp') -Method Post -ContentType 'application/json' -Body $callBody -TimeoutSec 5
    $projectInfo = $mcpProject.result.content[0].text | ConvertFrom-Json
    if ($projectInfo.project_name -ne 'gamedemo') { throw 'The MCP tool must report this game project.' }
    & $GodotPath --headless --path $projectRoot --quit-after 3 *> (Join-Path $temporaryRoot 'game.log')
    if ($LASTEXITCODE -ne 0) { throw 'The 2D main scene did not start successfully.' }
    $runtimeLog = Get-Content -LiteralPath (Join-Path $temporaryRoot 'game.log') -Raw
    if ($runtimeLog -match '(?m)^(SCRIPT ERROR|ERROR):') { throw 'The main scene produced an engine error.' }
    [pscustomobject]@{project=$projectRoot;editor_connected=$cliDoctor.editor_connected;mcp_port=[int]$portMatch.Groups[1].Value;scene_queries='passed';supplementary_cli='passed';mcp_initialize='passed';mcp_tool_call='passed';main_scene_start='passed'} | ConvertTo-Json -Compress
}
finally {
    if ($editorProcess -and -not $editorProcess.HasExited) { Stop-Process -Id $editorProcess.Id; $editorProcess.WaitForExit(5000) | Out-Null }
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $expectedPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemporaryRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Temporary cleanup target is outside the integration test folder.' }
    if ($resolvedTemporaryRoot -notmatch '[\\/]\.tmp_connection_[a-f0-9]+$') { throw 'Unexpected temporary cleanup folder.' }
    Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
}

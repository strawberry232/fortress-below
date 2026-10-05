param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$IconSource,
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class CharacterAlphaAudit {
    public static int[][] Bounds(string path, int frameWidth, int frameHeight, int threshold) {
        using (var image = new Bitmap(path)) {
            var result = new List<int[]>();
            for (int frame = 0; frame < image.Width / frameWidth; frame++) {
                int left = frameWidth, top = frameHeight, right = -1, bottom = -1;
                for (int y = 0; y < frameHeight; y++) {
                    for (int x = 0; x < frameWidth; x++) {
                        if (image.GetPixel(frame * frameWidth + x, y).A < threshold) continue;
                        left = Math.Min(left, x); top = Math.Min(top, y);
                        right = Math.Max(right, x); bottom = Math.Max(bottom, y);
                    }
                }
                result.Add(right < 0 ? new int[0] : new [] {left, top, right + 1, bottom + 1});
            }
            return result.ToArray();
        }
    }
}
'@ -ReferencedAssemblies 'System.Drawing.Common','System.Drawing.Primitives','System.Private.Windows.GdiPlus','System.Private.Windows.Core','System.Collections'

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$authority = Get-Content -LiteralPath (Join-Path $projectPath 'game/data/animations/tiny_rpg_character_metadata.json') -Raw | ConvertFrom-Json
$metadata = Get-Content -LiteralPath (Join-Path $projectPath 'game/data/animations/asset_metadata.json') -Raw | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
$records = [System.Collections.Generic.List[object]]::new()
$checks = 0

function Confirm([bool]$Condition, [string]$Description) {
    $script:checks++
    if (-not $Condition) { $script:errors.Add($Description) }
}

Confirm ($authority.Count -eq 11) 'Expected six Soldier and five Orc source sheets'
foreach ($current in $authority) {
    $resource = $current.resource
    $source = Join-Path $SourceRoot $current.source_relative
    $destination = Join-Path $projectPath $resource.Replace('res://', '')
    $entry = @($metadata.assets | Where-Object path -EQ $resource)
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    Confirm ($sourceHash -eq $destinationHash) ($resource + ': source PNG byte identity')
    Confirm ($sourceHash -eq $current.source_sha256.ToLowerInvariant()) ($resource + ': authoritative source hash')
    Confirm ($destinationHash -eq $current.sha256.ToLowerInvariant()) ($resource + ': authoritative destination hash')
    $image = [System.Drawing.Bitmap]::new($destination)
    $width = $image.Width
    $height = $image.Height
    $image.Dispose()
    $measuredBounds = [CharacterAlphaAudit]::Bounds($destination, 100, 100, 192)
    $expectedBounds = @($current.alpha_body_bounds | ForEach-Object { ,@($_[0], $_[1], ($_[2] + 1), ($_[3] + 1)) })
    Confirm ($width -eq (100 * $current.frames) -and $height -eq 100) ($resource + ': PNG size and single-row frame count')
    Confirm (($measuredBounds | ConvertTo-Json -Depth 8 -Compress) -eq ($expectedBounds | ConvertTo-Json -Depth 8 -Compress)) ($resource + ': measured opaque-body alpha bounds')
    Confirm ($entry.Count -eq 1) ($resource + ': current metadata entry exists once')
    if ($entry.Count -eq 1) {
        $entry = $entry[0]
        $expectedSourcePath = (Split-Path -Leaf $SourceRoot) + '/' + $current.source_relative
        Confirm ($entry.original_path -eq $expectedSourcePath) ($resource + ': current shadow-folder source mapping')
        Confirm ($entry.sha256.ToLowerInvariant() -eq $destinationHash) ($resource + ': metadata hash')
        Confirm ($entry.frame_width -eq 100 -and $entry.frame_height -eq 100 -and $entry.frame_count -eq $current.frames) ($resource + ': metadata frame geometry')
        Confirm ($entry.width -eq $width -and $entry.height -eq $height) ($resource + ': metadata sheet geometry')
        Confirm ($entry.alpha_bounds_threshold -eq 192 -and $entry.alpha_bounds_interval -eq 'right_bottom_exclusive') ($resource + ': metadata alpha convention')
        Confirm (($entry.alpha_bounds_by_frame | ConvertTo-Json -Depth 8 -Compress) -eq ($measuredBounds | ConvertTo-Json -Depth 8 -Compress)) ($resource + ': metadata alpha bounds')
        $isOrc = $resource -match '/tiny_rpg/orc_'
        $expectedRole = 'active_character'
        $expectedRoles = if ($isOrc) { @('defense_enemy') } elseif ($resource -match '/soldier_bow\.png$') { @('dungeon_player', 'tower_archer') } else { @('dungeon_player') }
        Confirm ($entry.foot_y -eq 60 -and $entry.current_role -eq $expectedRole) ($resource + ': accurate active or historical role and foot anchor')
        Confirm (($entry.current_roles -join ',') -eq ($expectedRoles -join ',')) ($resource + ': explicit current gameplay roles')
        Confirm ($current.current_role -eq $expectedRole -and ($current.current_roles -join ',') -eq ($expectedRoles -join ',')) ($resource + ': source authority agrees with gameplay usage')
    }
    $records.Add([ordered]@{
        resource = $resource; source = [System.IO.Path]::GetFullPath($source)
        source_sha256 = $sourceHash; sha256 = $destinationHash
        byte_identical = ($sourceHash -eq $destinationHash)
        width = $width; height = $height; frame_width = 100; frame_height = 100
        frame_count = $current.frames; alpha_threshold = 192
        alpha_bounds_interval = 'right_bottom_exclusive'; alpha_bounds_by_frame = $measuredBounds
    })
}

$iconDestination = Join-Path $projectPath 'game/assets/icons/game_icon.png'
$iconSourceHash = (Get-FileHash -LiteralPath $IconSource -Algorithm SHA256).Hash.ToLowerInvariant()
$iconHash = (Get-FileHash -LiteralPath $iconDestination -Algorithm SHA256).Hash.ToLowerInvariant()
$iconImage = [System.Drawing.Bitmap]::new($iconDestination)
$iconSize = @($iconImage.Width, $iconImage.Height)
$iconImage.Dispose()
Confirm ($iconSourceHash -eq $iconHash) 'Application icon matches its original node_2D tower PNG'
Confirm ($iconSize[0] -eq 16 -and $iconSize[1] -eq 16) 'Application icon remains the original 16x16 PNG'
foreach ($legacy in @($metadata.assets | Where-Object path -Match '/enemies/skeleton_')) {
    Confirm ($legacy.current_role -eq 'active_monster') ($legacy.path + ': original skeleton animations are active again')
}
Confirm (@($metadata.assets | Where-Object path -Match '/enemies/skeleton_').Count -eq 5) 'All five historical skeleton source entries are preserved'

foreach ($retiredPath in @('res://game/assets/tiny_swords/wood.png', 'res://game/assets/tiny_swords/worker.png')) {
    $retired = @($metadata.assets | Where-Object path -EQ $retiredPath)
    Confirm ($retired.Count -eq 1) ($retiredPath + ': retained original audit record')
    if ($retired.Count -eq 1) {
        Confirm ($retired[0].current_usage -eq 'retired_unused' -and @($retired[0].current_roles).Count -eq 0) ($retiredPath + ': removed resource system has no active role')
    }
}
$torch = @($metadata.assets | Where-Object path -EQ 'res://game/assets/tiny_swords/torch.png')
Confirm ($torch.Count -eq 1 -and @($torch[0].current_roles).Count -eq 0 -and $torch[0].current_usage -eq 'retired_unused') 'The Torch goblin is retired from every wave'

$newMonsters = @($metadata.assets | Where-Object path -Match '/dungeon/monsters/')
Confirm ($newMonsters.Count -eq 16) 'Exactly sixteen adopted frames describe the four current source monster types'
foreach ($monster in $newMonsters) {
    $monsterDestination = Join-Path $projectPath $monster.path.Replace('res://', '')
    Confirm (Test-Path -LiteralPath $monster.source_absolute -PathType Leaf) ($monster.path + ': original source exists')
    Confirm (Test-Path -LiteralPath $monsterDestination -PathType Leaf) ($monster.path + ': adopted frame exists')
    if (-not (Test-Path -LiteralPath $monster.source_absolute -PathType Leaf) -or -not (Test-Path -LiteralPath $monsterDestination -PathType Leaf)) { continue }
    $monsterSourceHash = (Get-FileHash -LiteralPath $monster.source_absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    $monsterHash = (Get-FileHash -LiteralPath $monsterDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    Confirm ($monsterSourceHash -eq $monsterHash -and $monsterHash -eq $monster.sha256 -and $monsterSourceHash -eq $monster.source_sha256) ($monster.path + ': original and both metadata hashes agree')
    Confirm ($monster.width -eq 16 -and $monster.height -eq 16 -and $monster.frame_width -eq 16 -and $monster.frame_height -eq 16) ($monster.path + ': actual 16x16 frame geometry')
    Confirm ($monster.runtime_display_scale -eq 4 -and ($monster.foot_anchor -join ',') -eq '8,15') ($monster.path + ': current integer scale and foot anchor')
    $expectedMonsterRoles = if ($monster.monster_kind -eq 'skull') { 'dungeon_enemy,defense_enemy' } else { '' }
    Confirm (($monster.current_roles -join ',') -eq $expectedMonsterRoles) ($monster.path + ': accurate current or superseded role')
    $monsterBounds = [CharacterAlphaAudit]::Bounds($monsterDestination, 16, 16, 1)
    Confirm (($monster.alpha_bounds_by_frame | ConvertTo-Json -Depth 8 -Compress) -eq ($monsterBounds | ConvertTo-Json -Depth 8 -Compress)) ($monster.path + ': actual alpha bounds match adopted metadata')
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Output ('FAIL: ' + $_) }
    Write-Output ('FAILURES=' + $errors.Count + ' CHECKS=' + $checks)
    exit 1
}
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $projectPath 'docs/verification/character-original-asset-audit.json'
}
$audit = [ordered]@{
    audited_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    character_sheet_count = $records.Count; soldier_sheet_count = 6; orc_sheet_count = 5
    checked_assertions = $checks; failures = 0; all_character_pngs_byte_identical = $true
    assets = $records; adopted_dungeon_monster_frames = $newMonsters.Count
    separate_application_icon = [ordered]@{
        resource = 'res://game/assets/icons/game_icon.png'
        source = [System.IO.Path]::GetFullPath($IconSource)
        source_sha256 = $iconSourceHash; sha256 = $iconHash
        byte_identical = ($iconHash -eq $iconSourceHash); width = $iconSize[0]; height = $iconSize[1]
        counted_in_expansion_original_33 = $false
    }
}
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
[System.IO.File]::WriteAllText($OutputPath, ($audit | ConvertTo-Json -Depth 18) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Output ('PASS: characters=' + $records.Count + ' separate_icon=1 checks=' + $checks + ' failures=0')

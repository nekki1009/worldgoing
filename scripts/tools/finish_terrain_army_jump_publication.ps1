[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StageRelative,
    [Parameter(Mandatory = $true)][string]$ReplacementPath,
    [Parameter(Mandatory = $true)][string]$BaselineRecoveryPath,
    [Parameter(Mandatory = $true)][string]$RangedRecoveryPath,
    [Parameter(Mandatory = $true)][string]$MaskRecoveryPath
)

$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$taskStage = [IO.Path]::GetFullPath((Join-Path $taskRoot $StageRelative))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $taskRoot 'output')) + [IO.Path]::DirectorySeparatorChar
$assetRoot = [IO.Path]::GetFullPath((Join-Path $taskRoot 'assets/characters/terrain_lab_army/standard_soldier'))
if (-not $taskStage.StartsWith($outputRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Stage must remain inside project output' }

function Resolve-TaskPath([string]$path) {
    $resolved = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $taskRoot $path }))
    if (-not $resolved.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped project' }
    return $resolved
}
function Resolve-ResourcePath([string]$resource) {
    if (-not $resource.StartsWith('res://')) { throw "Non-project resource: $resource" }
    return Resolve-TaskPath $resource.Substring(6)
}
function Get-TaskHash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant() }
function Read-TaskJson([string]$path) { return Get-Content -LiteralPath (Resolve-TaskPath $path) -Raw | ConvertFrom-Json -AsHashtable }
function Copy-TaskAtomic([string]$source, [string]$target) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $temporary = Join-Path $taskRoot ('.godot-temp/terrain_army_jump_publish/' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    $incoming = Join-Path $temporary 'incoming'
    Copy-Item -LiteralPath $source -Destination $incoming
    if (Test-Path -LiteralPath $target) {
        [IO.File]::Replace($incoming, $target, (Join-Path $temporary 'previous'), $true)
    } else {
        [IO.File]::Move($incoming, $target)
    }
}
function Test-TaskRecovery([string]$path, [bool]$published) {
    $recovery = Read-TaskJson $path
    if ($recovery.new_sources.Count -lt 1 -or $recovery.new_sources.Count -ne $recovery.source_md5.Count -or $recovery.originals.Count -ne $recovery.new_sources.Count) { throw "Recovery is incomplete: $path" }
    $recovery['_backup_md5'] = @{}
    foreach ($source in $recovery.new_sources.Keys) {
        $sourcePath = Resolve-ResourcePath $source
        $targetPath = Resolve-ResourcePath $recovery.new_sources[$source]
        if (-not $sourcePath.StartsWith($taskStage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not $targetPath.StartsWith($assetRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Recovery path escaped task scope: $source" }
        if ((Get-TaskHash $sourcePath) -ne $recovery.source_md5[$source]) { throw "Staged source changed: $source" }
        $backupPath = Resolve-ResourcePath $recovery.originals[$recovery.new_sources[$source]]
        if (-not $backupPath.StartsWith($taskStage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Recovery backup escaped stage: $backupPath" }
        $backupHash = Get-TaskHash $backupPath
        $recovery._backup_md5[$recovery.new_sources[$source]] = $backupHash
        $expectedTargetHash = if ($published) { $recovery.source_md5[$source] } else { $backupHash }
        if ((Get-TaskHash $targetPath) -ne $expectedTargetHash) { throw "Formal target changed after preflight: $targetPath" }
    }
    return $recovery
}
function Restore-TaskRecovery([hashtable]$recovery) {
    $restoreErrors = @()
    foreach ($target in $recovery.originals.Keys) {
        try {
            $backupPath = Resolve-ResourcePath $recovery.originals[$target]
            $targetPath = Resolve-ResourcePath $target
            if ((Get-TaskHash $backupPath) -ne $recovery._backup_md5[$target]) { throw "Rollback backup changed during transaction: $target" }
            Copy-TaskAtomic $backupPath $targetPath
            if ((Get-TaskHash $targetPath) -ne $recovery._backup_md5[$target]) { throw "Rollback bytes differ: $target" }
        } catch {
            $restoreErrors += $_.Exception.Message
        }
    }
    if ($restoreErrors.Count) { throw ($restoreErrors -join ' | ') }
}

$baselineRecovery = Test-TaskRecovery $BaselineRecoveryPath $false
$rangedRecovery = $null
$maskRecovery = $null
$recipeOldMoved = $false
$recipeNewMoved = $false
$rollbackDirectory = Join-Path $taskStage ('rollback_' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

try {
$replacement = Read-TaskJson $ReplacementPath
if ($replacement.status -ne 'READY' -or $replacement.recipes -ne 32 -or $replacement.pages -ne 160 -or $replacement.samples -ne 18688) { throw 'Recipe replacement metadata is incomplete' }
$candidate = Resolve-ResourcePath $replacement.candidate
$destination = Resolve-ResourcePath $replacement.destination
$backup = Resolve-ResourcePath $replacement.backup
$expectedDestination = Join-Path $assetRoot 'recipes/v1'
if (-not $candidate.StartsWith($taskStage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $destination -ne $expectedDestination -or -not $backup.StartsWith($taskStage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Recipe replacement paths escaped exact task scope' }
if (-not (Test-Path -LiteralPath $candidate -PathType Container) -or -not (Test-Path -LiteralPath $destination -PathType Container) -or (Test-Path -LiteralPath $backup)) { throw 'Recipe candidate, destination or fresh backup invariant failed' }
if ($replacement.candidate_files.Count -ne 481) { throw 'Recipe candidate must contain exactly catalog plus 160 manifest/PNG/RES triples' }
$expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($resource in $replacement.candidate_files.Keys) {
    $path = Resolve-ResourcePath $resource
    if (-not $path.StartsWith($candidate + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Candidate file escaped recipe directory: $resource" }
    if ((Get-TaskHash $path) -ne $replacement.candidate_files[$resource]) { throw "Recipe candidate changed after READY: $resource" }
    [void]$expectedFiles.Add($path)
}
$actualFiles = @(Get-ChildItem -LiteralPath $candidate -File -Recurse | ForEach-Object FullName)
if ($actualFiles.Count -ne $expectedFiles.Count) { throw 'Recipe candidate file set changed after READY' }
foreach ($path in $actualFiles) { if (-not $expectedFiles.Contains($path)) { throw "Unexpected recipe candidate file: $path" } }
foreach ($resource in $replacement.source_fingerprints.Keys) {
    if ((Get-TaskHash (Resolve-ResourcePath $resource)) -ne $replacement.source_fingerprints[$resource]) { throw "Recipe source changed after READY: $resource" }
}
$baselineManifestTarget = 'res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json'
$baselineManifestSources = @($baselineRecovery.new_sources.Keys | Where-Object { $baselineRecovery.new_sources[$_] -eq $baselineManifestTarget })
if ($baselineManifestSources.Count -ne 1 -or (Get-TaskHash (Resolve-ResourcePath $baselineManifestSources[0])) -ne $replacement.source_manifest_md5) { throw 'Staged baseline manifest differs from recipe READY' }

$rangedRecovery = Test-TaskRecovery $RangedRecoveryPath $false
$maskRecovery = Test-TaskRecovery $MaskRecoveryPath $false
    & (Join-Path $PSScriptRoot 'finish_equipment_dye_publication.ps1') -RecoveryPath $BaselineRecoveryPath -StageRelative $StageRelative
    if ((Get-TaskHash (Resolve-ResourcePath $baselineManifestTarget)) -ne $replacement.source_manifest_md5) { throw 'Published baseline manifest differs from recipe READY' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    [IO.Directory]::Move($destination, $backup)
    $recipeOldMoved = $true
    [IO.Directory]::Move($candidate, $destination)
    $recipeNewMoved = $true

    & (Join-Path $PSScriptRoot 'finish_equipment_dye_publication.ps1') -RecoveryPath $RangedRecoveryPath -StageRelative $StageRelative
    & (Join-Path $PSScriptRoot 'finish_equipment_dye_publication.ps1') -RecoveryPath $MaskRecoveryPath -StageRelative $StageRelative

    $verify = Join-Path $env:USERPROFILE '.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1'
    $godot = Join-Path $env:USERPROFILE 'Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe'
    $checks = @(
        @{ Script = 'res://scripts/tests/terrain_army_recipe_bake_plan_test.gd'; Extra = @() },
        @{ Script = 'res://scripts/tests/terrain_army_equipment_atlas_test.gd'; Extra = @() },
        @{ Script = 'res://scripts/tests/terrain_army_equipment_batch_admission_test.gd'; Extra = @() },
        @{ Script = 'res://scripts/tests/terrain_army_ranged_atlas_test.gd'; Extra = @() },
        @{ Script = 'res://scripts/tests/weapon_materials_atlas_test.gd'; Extra = @() },
        @{ Script = 'res://scripts/tests/weapon_materials_npc_validate.gd'; Extra = @('--', '--published') },
        @{ Script = 'res://scripts/tests/site_combat_atlas_test.gd'; Extra = @() }
    )
    foreach ($check in $checks) {
        $arguments = @('--script', $check.Script) + @($check.Extra)
        $verificationOutput = @(& $verify -ProjectPath $taskRoot -GodotExecutable $godot -Mode headless -GodotArguments $arguments -TimeoutSeconds 120)
        $verificationExit = $LASTEXITCODE
        $verificationOutput | Write-Output
        if ($verificationExit -ne 0) { throw "Published validation failed: $($check.Script)" }
    }
} catch {
    $failure = $_
    $rollbackErrors = @()
    foreach ($rollbackStep in @(
        { New-Item -ItemType Directory -Path $rollbackDirectory -Force | Out-Null },
        { if ($null -ne $maskRecovery) { Restore-TaskRecovery $maskRecovery } },
        { if ($null -ne $rangedRecovery) { Restore-TaskRecovery $rangedRecovery } },
        {
            if ($recipeNewMoved -and (Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath (Join-Path $rollbackDirectory 'rejected_recipes'))) {
                [IO.Directory]::Move($destination, (Join-Path $rollbackDirectory 'rejected_recipes'))
            }
        },
        {
            if ($recipeOldMoved -and (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $destination)) {
                [IO.Directory]::Move($backup, $destination)
            }
        },
        { Restore-TaskRecovery $baselineRecovery }
    )) {
        try { & $rollbackStep } catch { $rollbackErrors += $_.Exception.Message }
    }
    throw "TERRAIN_ARMY_JUMP_PUBLICATION_ROLLED_BACK: $failure; rollback_errors=$($rollbackErrors -join ' | '); evidence=$rollbackDirectory"
}

Write-Output "TERRAIN_ARMY_JUMP_PUBLICATION=PASS recipes=32 recipe_pages=160 ranged=44 masks=45; backups retained under $taskStage"

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RecoveryPath)
$ErrorActionPreference = 'Stop'
$dyeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$dyeStage = Join-Path $dyeRoot 'output/equipment_palette_policy_20260914'
$dyeAssets = Join-Path $dyeRoot 'assets/characters/terrain_lab_army/standard_soldier'
$dyeRecoveryPath = (Resolve-Path -LiteralPath $RecoveryPath).Path
if (-not $dyeRecoveryPath.StartsWith($dyeStage + [IO.Path]::DirectorySeparatorChar)) { throw 'Recovery must be in the approved task stage' }
$dyeRecovery = Get-Content -LiteralPath $dyeRecoveryPath -Raw | ConvertFrom-Json -AsHashtable
function Resolve-DyePath([string]$resource) {
    if (-not $resource.StartsWith('res://')) { throw 'Non-project resource' }
    $resolved = [IO.Path]::GetFullPath((Join-Path $dyeRoot $resource.Substring(6)))
    if (-not $resolved.StartsWith($dyeRoot + [IO.Path]::DirectorySeparatorChar)) { throw 'Resource escaped project' }
    return $resolved
}
function Get-DyeHash([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant() }
function Copy-DyeAtomic([string]$source, [string]$target) {
    # Replace a directory entry rather than truncate an editor-mapped file.
    # The existing saved baseline is never moved or removed.
    $operation = [Guid]::NewGuid().ToString('N')
    $temporary = Join-Path $dyeRoot ".godot-temp/equipment_dye_publish/$operation"
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    $incoming = Join-Path $temporary 'incoming'
    Copy-Item -LiteralPath $source -Destination $incoming
    if (Test-Path -LiteralPath $target) {
        [IO.File]::Replace($incoming, $target, (Join-Path $temporary 'previous'), $true)
    } else { [IO.File]::Move($incoming, $target) }
}
foreach ($source in $dyeRecovery.new_sources.Keys) {
    $dyeSource = Resolve-DyePath $source
    $dyeTarget = Resolve-DyePath $dyeRecovery.new_sources[$source]
    if (-not $dyeSource.StartsWith($dyeStage + [IO.Path]::DirectorySeparatorChar) -or -not $dyeTarget.StartsWith($dyeAssets + [IO.Path]::DirectorySeparatorChar)) { throw 'Unexpected publication path' }
    if ((Get-DyeHash $dyeSource) -ne $dyeRecovery.source_md5[$source]) { throw 'Staged bytes changed since Godot preflight' }
    if ($dyeRecovery.originals.ContainsKey($dyeRecovery.new_sources[$source])) {
        if ((Get-DyeHash $dyeTarget) -ne (Get-DyeHash (Resolve-DyePath $dyeRecovery.originals[$dyeRecovery.new_sources[$source]]))) { throw 'Destination changed since backup' }
    } elseif (Test-Path -LiteralPath $dyeTarget) { throw 'New destination appeared after preflight' }
    if ($source.EndsWith('.json')) {
        $manifest = Get-Content -LiteralPath $dyeSource -Raw | ConvertFrom-Json -AsHashtable
        if (-not $manifest.source_fingerprints -or $manifest.source_fingerprints.Count -eq 0) { throw 'Missing source fingerprints' }
        foreach ($dependency in $manifest.source_fingerprints.Keys) {
            if ((Get-DyeHash (Resolve-DyePath $dependency)) -ne $manifest.source_fingerprints[$dependency]) { throw "Source changed: $dependency" }
        }
    }
}
# Godot preflight/backup has completed and exited. No metadata is rewritten here.
try {
    foreach ($source in $dyeRecovery.new_sources.Keys) {
        $dyeTarget = Resolve-DyePath $dyeRecovery.new_sources[$source]
        if ((Test-Path -LiteralPath $dyeTarget) -and (Get-DyeHash $dyeTarget) -eq $dyeRecovery.source_md5[$source]) { continue }
        Copy-DyeAtomic (Resolve-DyePath $source) $dyeTarget
        if ((Get-DyeHash $dyeTarget) -ne $dyeRecovery.source_md5[$source]) { throw 'Copied bytes differ' }
    }
} catch {
    foreach ($target in $dyeRecovery.originals.Keys) {
        $dyeOriginal = Resolve-DyePath $dyeRecovery.originals[$target]
        $dyeTarget = Resolve-DyePath $target
        if ((Get-DyeHash $dyeOriginal) -ne (Get-DyeHash $dyeTarget)) { Copy-DyeAtomic $dyeOriginal $dyeTarget }
    }
    throw
}
Write-Output "DYE_NATIVE_COPY=PASS FILES=$($dyeRecovery.new_sources.Count); run the original Godot published-asset validation next"

[CmdletBinding()]
param([string]$BaselineRelative = 'output/medieval_cloth_20260916/baseline')
$ErrorActionPreference = 'Stop'
$clothRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$clothOutput = Join-Path $clothRoot 'output/medieval_cloth_20260916'
$clothAssets = Join-Path $clothRoot 'assets/characters/human/q35'
$clothBaseline = [IO.Path]::GetFullPath((Join-Path $clothRoot $BaselineRelative))
if (-not $clothBaseline.StartsWith([IO.Path]::GetFullPath((Join-Path $clothRoot 'output')) + [IO.Path]::DirectorySeparatorChar)) { throw 'Baseline must be inside project output' }
$clothReport = Get-Content -LiteralPath (Join-Path $clothOutput 'candidate_contract.json') -Raw | ConvertFrom-Json
$clothPairs = @()
foreach ($sex in @('male','female')) {
    $record = @($clothReport | Where-Object { $_.sex -eq $sex -and -not $_.final })
    if ($record.Count -ne 1 -or $record[0].skirts -ne 3 -or $null -eq $record[0].armor_variants -or $record[0].armor_variants -ne 0) { throw 'Missing current validation without canceled armored-skirt prototypes' }
    foreach ($ext in @('blend','glb','json')) {
        $name = "standard_anime_${sex}_character_pack.$ext"
        $source = if ($ext -eq 'blend') { Join-Path $clothAssets "medieval_cloth/medieval_cloth_$sex.blend" } else { Join-Path $clothAssets "medieval_cloth/candidate_$sex.$ext" }
        $target = Join-Path $clothAssets $name
        $baseline = Join-Path $clothBaseline $name
        if ((Get-FileHash -LiteralPath $target -Algorithm MD5).Hash -ne (Get-FileHash -LiteralPath $baseline -Algorithm MD5).Hash) { throw "Formal source changed since backup: $name" }
        $expected = $record[0].source_md5.$ext
        if ((Get-FileHash -LiteralPath $source -Algorithm MD5).Hash.ToLowerInvariant() -ne $expected) { throw "Candidate changed after validation: $source" }
        $clothPairs += @{ source=$source; target=$target; baseline=$baseline; md5=$expected; name=$name }
    }
}
$clothIncoming = Join-Path $clothOutput ('publication_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $clothIncoming | Out-Null
foreach ($pair in $clothPairs) {
    $incoming = Join-Path $clothIncoming $pair.name
    Copy-Item -LiteralPath $pair.source -Destination $incoming
    if ((Get-FileHash -LiteralPath $incoming -Algorithm MD5).Hash.ToLowerInvariant() -ne $pair.md5) { throw 'Incoming bytes differ' }
}
# Replace directory entries so an open editor never observes truncated GLBs.
# Both the immutable baseline and per-file recovery copies are retained.
$clothReplaced = @()
try {
    foreach ($pair in $clothPairs) {
        if ((Get-FileHash -LiteralPath $pair.target -Algorithm MD5).Hash -ne (Get-FileHash -LiteralPath $pair.baseline -Algorithm MD5).Hash) { throw "Formal source changed during publication: $($pair.name)" }
        [IO.File]::Replace((Join-Path $clothIncoming $pair.name), $pair.target, (Join-Path $clothIncoming ($pair.name + '.previous')), $true)
        $clothReplaced += $pair
        if ((Get-FileHash -LiteralPath $pair.target -Algorithm MD5).Hash.ToLowerInvariant() -ne $pair.md5) { throw "Publication verification failed: $($pair.name)" }
    }
} catch {
    foreach ($pair in $clothReplaced) {
        $restore = Join-Path $clothIncoming ($pair.name + '.restore')
        Copy-Item -LiteralPath $pair.baseline -Destination $restore
        [IO.File]::Replace($restore, $pair.target, (Join-Path $clothIncoming ($pair.name + '.failed')), $true)
    }
    throw
}
Write-Output 'MEDIEVAL_CLOTH_PUBLICATION=PASS six formal files; original backups retained'

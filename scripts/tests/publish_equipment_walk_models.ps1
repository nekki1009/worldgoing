# Explicit six-file publication of a visually reviewed candidate only.
param(
    [ValidatePattern('^v[0-9]+$')][string]$Revision = 'v3',
    [string]$MaleRun = '20260919_115445_137',
    [string]$FemaleRun = '20260919_115555_670',
    [string]$PreviousPublication = '',
    [switch]$SteelMingguang
)
$ErrorActionPreference = 'Stop'
$projectDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$taskDir = Join-Path $projectDir 'output/equipment_walk_fix_20260919'
if ($SteelMingguang) { $taskDir = Join-Path $projectDir 'output/steel_mingguang_walk_20260919' }
$formalDir = Join-Path $projectDir 'assets/characters/human/q35'
$publication = Join-Path $taskDir $(if ($Revision -eq 'v3' -and -not $SteelMingguang) { 'model_publication.json' } else { "model_publication_$Revision.json" })
if (Test-Path -LiteralPath $publication) { throw 'Publication already recorded' }
$freezePath = Join-Path $taskDir $(if ($Revision -eq 'v3' -and -not $SteelMingguang) { 'atlas/after_sources.json' } else { "atlas/after_revision/after_$Revision/after_sources.json" })
if (Test-Path -LiteralPath $freezePath) { throw 'Source freeze already exists; use a fresh reviewed revision' }
$runs = @{ male=$MaleRun; female=$FemaleRun }
$previous = $null
if ($PreviousPublication) {
    if ($PreviousPublication -notmatch '^model_publication(?:_v[0-9]+)?\.json$') { throw 'Explicit prior publication basename required' }
    $previous = Get-Content -LiteralPath (Join-Path $taskDir $PreviousPublication) -Raw | ConvertFrom-Json -AsHashtable
    if (-not $previous.published) { throw 'Previous publication not complete' }
}
$files = @()
foreach ($sex in @('male','female')) {
    $candidateDir = Join-Path $taskDir "combined/$Revision/$sex"
    $report = Get-Content -LiteralPath (Join-Path $candidateDir 'build.json') -Raw | ConvertFrom-Json -AsHashtable
    $runFile = Join-Path $projectDir ('.godot-temp/godot_verify/' + $runs[$sex] + '/result.json')
    $run = Get-Content -LiteralPath $runFile -Raw | ConvertFrom-Json
    if ($run.status -ne 'PASS' -or $run.exit_code -ne 0 -or $run.timed_out -or $run.failure) { throw "Failed native capture $sex" }
    $capture = Get-Content -LiteralPath (Join-Path $taskDir "candidate_$Revision/$sex/result.json") -Raw | ConvertFrom-Json
    $expectedImages = if ($SteelMingguang) { 129 } else { 348 }
    if ($capture.images.Count -ne $expectedImages -or $capture.status -ne 'CAPTURE_COMPLETE') { throw "Incomplete capture $sex" }
    if ($capture.editor_md5 -ne (Get-FileHash -LiteralPath (Join-Path $projectDir 'scripts/ui/human_character_3d_editor.gd') -Algorithm MD5).Hash) { throw 'Editor changed after review' }
    if ($SteelMingguang) {
        if ($report.glb_steel.replaced_meshes.Count -ne 10 -or $report.glb_morph.appended_walk_channels -ne 10 -or -not $report.glb_morph.old_morphs_and_base_accessors_preserved) { throw 'Steel/Mingguang scope changed' }
        $proof = Get-Content -LiteralPath (Join-Path $taskDir "combined/$Revision/native_preservation.json") -Raw | ConvertFrom-Json -AsHashtable
        if ($proof[$sex].after.sha256 -ne $report.candidate_sha256['.glb']) { throw 'Independent native proof differs' }
        $regression = Get-Content -LiteralPath (Join-Path $taskDir "combined/$Revision/visual_regression.json") -Raw | ConvertFrom-Json
        if ($regression.status -ne 'PIXEL_REGRESSION_PASS' -or $regression.differences.Count -ne 0) { throw 'Visual regression not accepted' }
        $review = Get-Content -LiteralPath (Join-Path $taskDir "combined/$Revision/visual_acceptance.json") -Raw | ConvertFrom-Json -AsHashtable
        if ($review.status -ne 'REVIEWED' -or $review.candidate_sha256[$sex] -ne $report.candidate_sha256['.glb']) { throw 'Visual review missing or stale' }
    } elseif ($report.glb.replaced_meshes.Count -ne 30 -or -not $report.glb.original_nodes_skins_materials_images_textures_animations_unchanged) { throw 'Candidate scope changed' }
    foreach ($extension in @('.blend','.glb','.json')) {
        $name = "standard_anime_${sex}_character_pack$extension"
        $source = Join-Path $candidateDir $name
        $target = Join-Path $formalDir $name
        $backup = Join-Path $taskDir "baseline/$name"
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $report.baseline_sha256[$extension]) { throw 'Original immutable baseline changed' }
        if ($previous) {
            $prior = @($previous.files | Where-Object { $_.target -eq $target })
            if ($prior.Count -ne 1) { throw 'Previous publication target differs' }
            $backup = $prior[0].source
            if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $prior[0].after_sha256) { throw 'Previous reviewed model changed' }
        }
        $oldHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        $newHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($oldHash -ne (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash) { throw "Concurrent formal/baseline change: $name" }
        if ($newHash -ne $report.candidate_sha256[$extension]) { throw "Candidate changed: $name" }
        $files += [ordered]@{source=$source;target=$target;backup=$backup;before_sha256=$oldHash;after_sha256=$newHash}
    }
}
foreach ($runId in $runs.Values) {
    $source = Join-Path $projectDir ".godot-temp/godot_verify/$runId"
    $dest = Join-Path $taskDir "verification/$runId"
    if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $source -Destination (Join-Path $taskDir 'verification') -Recurse }
    foreach ($name in @('result.json','stdout.log','stderr.log','combined.log')) {
        if ((Get-FileHash -LiteralPath (Join-Path $source $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $dest $name)).Hash) { throw 'Evidence copy differs' }
    }
}
$replaced = @()
function Replace-VerifiedFile([string]$Source, [string]$Target, [string]$ExpectedHash) {
    $incoming = $Target + '.equipment-walk-incoming'
    if (-not (Test-Path -LiteralPath $incoming)) { Copy-Item -LiteralPath $Source -Destination $incoming }
    if ((Get-FileHash -LiteralPath $incoming -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Staged copy differs' }
    # Atomic replacement avoids truncating a Dropbox-mapped destination. The
    # immutable baseline remains the recovery source, including on failure.
    [IO.File]::Move($incoming, $Target, $true)
}
try {
    foreach ($file in $files) {
        Replace-VerifiedFile $file.source $file.target $file.after_sha256
        $replaced += $file
        if ((Get-FileHash -LiteralPath $file.target -Algorithm SHA256).Hash -ne $file.after_sha256) { throw 'Publication copy differs' }
    }
} catch {
    foreach ($file in $replaced) { Replace-VerifiedFile $file.backup $file.target $file.before_sha256 }
    throw
}
$result = [ordered]@{published=$true;files=$files;native_runs=$runs;review_scope='Six target equipment groups, both bodies, 24-sample front walk, native side/extreme/lining checks; not every equipment-animation combination'}
if ($SteelMingguang) { $result.review_scope = 'Chinese steel, Western steel and Mingguang; both bodies, 24 front walk samples, side/lining, walk-to-low-pose reset and old low-pose pixel regression; not every combination' }
[IO.File]::WriteAllText($publication, ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$snapshotPath = Join-Path $taskDir 'atlas/snapshot.json'
$snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable
$fingerprints = @{}
foreach ($resource in $snapshot.sources.Keys) {
    $fingerprints[$resource] = (Get-FileHash -LiteralPath (Join-Path $projectDir $resource.Substring(6)) -Algorithm MD5).Hash.ToLowerInvariant()
}
$freeze = @{snapshot_md5=(Get-FileHash -LiteralPath $snapshotPath -Algorithm MD5).Hash.ToLowerInvariant();formal_published=$true;source_fingerprints=$fingerprints}
if ($Revision -ne 'v3' -or $SteelMingguang) { $freeze.revision = "after_$Revision" }
New-Item -ItemType Directory -Path (Split-Path -Parent $freezePath) -Force | Out-Null
[IO.File]::WriteAllText($freezePath, ($freeze | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output 'EQUIPMENT_WALK_MODEL_PUBLICATION_PASS 6 formal files; baseline preserved; atlas not modified'

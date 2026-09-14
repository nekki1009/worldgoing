param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 194)]
    [int]$BatchIndex,

    [string]$PlanPath = 'output/terrain_army_missing_gear_20260913/batch_plan.json'
)

# Exactly one explicit immutable staging batch; no unbounded background loop.
$ErrorActionPreference = 'Stop'
$taskProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$taskPlanPath = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $taskProject $PlanPath }))
$taskOutputRoot = Join-Path $taskProject 'output'
if (-not $taskPlanPath.StartsWith($taskOutputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($taskPlanPath) -ne 'batch_plan.json') { throw 'Recipe plan must be a named output/batch_plan.json inside this project' }
$taskPlan = Get-Content -LiteralPath $taskPlanPath -Raw | ConvertFrom-Json
if ($taskPlan.status -ne 'READY' -or @($taskPlan.source_fingerprints.PSObject.Properties).Count -ne 6) { throw 'Recipe sources must be explicitly locked before any full batch' }
$taskManifestPath = Join-Path $taskProject 'assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json'
if ((Get-FileHash -LiteralPath $taskManifestPath -Algorithm MD5).Hash.ToLowerInvariant() -ne $taskPlan.source_manifest_md5) { throw 'Original soldier manifest changed after the recipe plan was locked' }
foreach ($taskSource in $taskPlan.source_fingerprints.PSObject.Properties) {
    if (-not $taskSource.Name.StartsWith('res://')) { throw 'Invalid locked recipe source' }
    $taskSourcePath = [IO.Path]::GetFullPath((Join-Path $taskProject $taskSource.Name.Substring(6)))
    if (-not $taskSourcePath.StartsWith($taskProject + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Locked recipe source escapes the project' }
    if ((Get-FileHash -LiteralPath $taskSourcePath -Algorithm MD5).Hash.ToLowerInvariant() -ne $taskSource.Value) { throw "Recipe source changed after lock: $($taskSource.Name)" }
}
$taskBatch = $taskPlan.batches[$BatchIndex]
if ($null -eq $taskBatch -or [int]$taskBatch.index -ne $BatchIndex) { throw 'Unknown recipe batch index' }
$taskBakerArgs = @(
    '--script', 'res://scripts/tools/bake_terrain_army_soldier.gd', '--',
    "--recipe-mask=$($taskBatch.mask)", "--recipe-output=$($taskBatch.output)",
    '--recipe-clips=all', '--recipe-directions=all',
    "--recipe-first=$($taskBatch.first)", "--recipe-count=$($taskBatch.count)"
)
if ($null -ne $taskBatch.iron) { $taskBakerArgs += "--recipe-iron=$($taskBatch.iron)" }
$taskExpected = @('manifest.json', 'page_000.png', 'page_000.res') | ForEach-Object {
    $taskBatch.output.Replace('res://', '') + '/' + $_
}
$taskVerifyOutput = & (Join-Path $env:USERPROFILE '.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1') `
    -ProjectPath $taskProject `
    -GodotExecutable (Join-Path $env:USERPROFILE 'Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe') `
    -Mode visual -GodotArguments $taskBakerArgs -TimeoutSeconds 25 -ExpectedOutput $taskExpected
$taskExitCode = $LASTEXITCODE
$taskVerifyOutput | Write-Output
$taskResultLine = @($taskVerifyOutput | Where-Object { $_ -is [string] -and $_.StartsWith('RESULT=') })
if ($taskResultLine.Count -ne 1) { throw 'Canonical verifier did not return exactly one result record' }
$taskResultPath = $taskResultLine[0].Substring(7)
$taskResultDir = Split-Path -Parent $taskResultPath
$taskEvidenceDir = Join-Path $taskProject ($taskBatch.output.Replace('res://', '') + '/verification')
New-Item -ItemType Directory -Path $taskEvidenceDir -Force | Out-Null
foreach ($taskLogName in @('result.json', 'stdout.log', 'stderr.log', 'combined.log')) {
    Copy-Item -LiteralPath (Join-Path $taskResultDir $taskLogName) -Destination (Join-Path $taskEvidenceDir $taskLogName)
}
exit $taskExitCode

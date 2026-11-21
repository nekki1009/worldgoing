[CmdletBinding()]
param(
    [ValidateSet('c2','c3','normal')][string]$Suite = 'c2',
    [ValidateSet('','B','D')][string]$Fixture = '',
    [string]$GodotExecutable = $env:GODOT,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 900,
    [ValidateRange(960,3600)][int]$GpuTimeoutSeconds = 1020,
    [string]$AtlasRoot = 'res://output/crowd_c2_c3_20261001/atlas'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$runId = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + $Suite
$category = if ($Suite -eq 'c3') { 'out_c3' } else { 'out_c2' }
$outputRoot = Join-Path $projectRoot ('native\crowd10k\' + $category + '\' + $runId)
New-Item -ItemType Directory -Path $outputRoot | Out-Null
New-Item -ItemType File -Path (Join-Path $outputRoot '.gdignore') | Out-Null
$sitesRoot = Join-Path $env:APPDATA 'Godot\app_userdata\worldgoing\sites'
function Get-SaveSnapshot {
    $entries = @()
    if (Test-Path -LiteralPath $sitesRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $sitesRoot -Recurse -File -Force) {
            $relative = $file.FullName.Substring($sitesRoot.Length).TrimStart('\')
            if ($relative -eq 'crowd_test' -or $relative.StartsWith('crowd_test\')) { continue }
            $entries += [pscustomobject]@{path=$relative;size=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }
    }
    return @($entries | Sort-Object path)
}
$before = @(Get-SaveSnapshot)
$before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot 'user_sites_before.json') -Encoding UTF8
$backupRoot = Join-Path $outputRoot 'backup_user_sites'
New-Item -ItemType Directory -Path $backupRoot | Out-Null
if (Test-Path -LiteralPath $sitesRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $sitesRoot -Recurse -File -Force) {
        $relative = $file.FullName.Substring($sitesRoot.Length).TrimStart('\')
        $destination = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
if ([string]::IsNullOrEmpty($GodotExecutable)) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE 'Godot_v4.7.2-stable_mono_win64') -Filter '*console*.exe' -File | Select-Object -First 1
    if ($null -eq $candidate) { throw 'Set GODOT to the Godot console executable.' }
    $GodotExecutable = $candidate.FullName
}
$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
$outputResource = 'res://native/crowd10k/' + $category + '/' + $runId
$phases = [System.Collections.Generic.List[object]]::new()
$exitCode = 1
function Invoke-AcceptancePhase([string]$Name, [string]$TestSuite, [string[]]$ExtraArguments, [bool]$CrowdEnabled, [string]$ScriptResource = 'res://scripts/tests/crowd_c2_c3_test.gd', [bool]$Gpu = $false) {
    $phaseRoot = Join-Path $outputRoot $Name
    New-Item -ItemType Directory -Path $phaseRoot | Out-Null
    $phaseRunId = $runId + '_' + $Name
    $phaseTimeout = if ($Gpu) { $GpuTimeoutSeconds } else { $TimeoutSeconds }
    $arguments = @('--path',$projectRoot,'--script',$ScriptResource)
    if ($Gpu) { $arguments += @('--position','-10000,-10000') } else { $arguments += '--headless' }
    $arguments += @('--','--crowd-test',$phaseRunId,'--crowd-suite',$TestSuite,'--crowd-output',($outputResource + '/' + $Name),'--crowd-atlas-root',$AtlasRoot)
    if ($CrowdEnabled) { $arguments += '--crowd' }
    $arguments += $ExtraArguments
    $quoted = @($arguments | ForEach-Object { '"' + ($_ -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1') + '"' })
    $stdout = Join-Path $phaseRoot 'stdout.log'
    $stderr = Join-Path $phaseRoot 'stderr.log'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $GodotExecutable -ArgumentList $quoted -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit($phaseTimeout * 1000)) {
        $process.Kill()
        $process.WaitForExit()
        $code = 124
    } else {
        $process.Refresh()
        $code = $process.ExitCode
    }
    $timer.Stop()
    $errors = @(Select-String -LiteralPath $stderr -Pattern 'ERROR:|SCRIPT ERROR|Parse Error' -ErrorAction SilentlyContinue | Where-Object { $_.Line -notmatch 'Failed to read the root certificate store' })
    if ($errors.Count -gt 0) { $code = 1 }
    $successPattern = if ($Gpu) { '^CROWD_CAPTIVITY_ATLAS_PASS cases=12 ' } else { '^GATE OK' }
    if ($code -eq 0 -and -not (Select-String -LiteralPath $stdout -Pattern $successPattern -Quiet)) { $code = 2 }
    $phase = [pscustomobject]@{name=$Name;run_id=$phaseRunId;suite=$TestSuite;exit_code=$code;elapsed_ms=$timer.Elapsed.TotalMilliseconds;timeout_seconds=$phaseTimeout;gpu=$Gpu;script=$ScriptResource;atlas_root=$AtlasRoot;crowd_startup=$CrowdEnabled;stdout=$stdout;stderr=$stderr}
    $phases.Add($phase)
    $phase | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $phaseRoot 'result.json') -Encoding UTF8
    return $code
}
try {
    if ($Suite -ne 'normal') {
        Write-Host 'Preparing the source-verified shared crowd atlas cache; the first run can take several minutes.'
        $exitCode = Invoke-AcceptancePhase 'atlas_prepare' 'atlas' @() $false 'res://scripts/tests/crowd_c2_captivity_atlas_fixture.gd' $true
        if ($exitCode -ne 0) { throw ('GPU atlas preparation failed with exit ' + $exitCode) }
    }
    if ($Suite -eq 'c2' -and [string]::IsNullOrEmpty($Fixture)) {
        $exitCode = Invoke-AcceptancePhase 'ui_commands' 'c2-ui' @('--crowd-ui-motion') $true 'res://scripts/tests/crowd_c2_ui_test.gd'
        if ($exitCode -ne 0) { throw ('Formal UI command checks failed with exit ' + $exitCode) }
    }
    $initialArguments = @()
    if (($Suite -eq 'c2' -and [string]::IsNullOrEmpty($Fixture)) -or $Suite -eq 'normal') { $initialArguments += '--crowd-close-current' }
    $selectedFixture = $Fixture
    if ($Suite -eq 'c3' -and [string]::IsNullOrEmpty($selectedFixture)) { $selectedFixture = 'D' }
    if ($selectedFixture) { $initialArguments += @('--crowd-fixture',$selectedFixture) }
    $exitCode = Invoke-AcceptancePhase 'initial' $Suite $initialArguments ($Suite -ne 'normal')
    if ($exitCode -eq 0 -and $Suite -eq 'c2' -and [string]::IsNullOrEmpty($Fixture)) {
        $exitCode = Invoke-AcceptancePhase 'close_archive' 'c2' @('--crowd-close-archive') $true
        if ($exitCode -eq 0) { $exitCode = Invoke-AcceptancePhase 'battle_B' 'c2' @('--crowd-fixture','B') $true }
        if ($exitCode -eq 0) { $exitCode = Invoke-AcceptancePhase 'disengage_D' 'c2' @('--crowd-fixture','D') $true }
    }
    if ($exitCode -eq 0 -and $Suite -eq 'normal') {
        $exitCode = Invoke-AcceptancePhase 'close_archive' 'normal' @('--crowd-close-archive') $false
    }
    if ($exitCode -eq 0 -and $Suite -eq 'c3') {
        $baselineFile = Join-Path $outputRoot 'initial\baseline.json'
        $referenceFile = Join-Path $outputRoot 'initial\baseline_reference.json'
        if (-not (Test-Path -LiteralPath $baselineFile) -or -not (Test-Path -LiteralPath $referenceFile)) { throw 'C3 initial phase did not produce its immutable baseline.' }
        $reference = Get-Content -LiteralPath $referenceFile -Raw | ConvertFrom-Json
        $expectedHash = [string]$reference.baseline_sha256
        foreach ($phase in @(@{name='restart';crowd=$true;corrupt=$false}, @{name='ordinary';crowd=$false;corrupt=$false}, @{name='corrupt';crowd=$false;corrupt=$true})) {
            $actualHash = (Get-FileHash -LiteralPath $baselineFile -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -cne $expectedHash) { throw ('GATE FAIL: immutable baseline changed; expected=' + $expectedHash + ' actual=' + $actualHash) }
            $extra = @('--crowd-baseline-copy',($outputResource + '/initial/baseline.json'),'--crowd-reference',($outputResource + '/initial/baseline_reference.json'))
            if ($phase.corrupt) { $extra += '--crowd-corrupt-load' }
            $exitCode = Invoke-AcceptancePhase $phase.name 'c3-restart' $extra $phase.crowd
            if ($exitCode -ne 0) { break }
        }
        if ($exitCode -eq 0) {
            $exitCode = Invoke-AcceptancePhase 'legacy_source' 'normal' @() $false
            if ($exitCode -eq 0) {
                $legacySource = Join-Path $sitesRoot ('crowd_test\' + $runId + '_legacy_source\current.json')
                $legacyCopy = Join-Path $outputRoot 'legacy_fixture.json'
                Copy-Item -LiteralPath $legacySource -Destination $legacyCopy
                $exitCode = Invoke-AcceptancePhase 'legacy_load' 'c3-legacy' @('--crowd-reload-copy',($outputResource + '/legacy_fixture.json')) $true
            }
        }
        $actualHash = (Get-FileHash -LiteralPath $baselineFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne $expectedHash) { $exitCode = 2 }
    }
} catch {
    $exitCode = 1
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $outputRoot 'launcher_error.log') -Encoding UTF8
    Write-Output ('GATE FAIL: ' + $_.Exception.Message)
} finally {
    $after = @(Get-SaveSnapshot)
    $after | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputRoot 'user_sites_after.json') -Encoding UTF8
    $unchanged = ($before | ConvertTo-Json -Depth 4 -Compress) -ceq ($after | ConvertTo-Json -Depth 4 -Compress)
    if (-not $unchanged) { $exitCode = 2; Write-Output 'GATE FAIL: formal user saves changed' }
    [pscustomobject]@{run_id=$runId;suite=$Suite;fixture=$selectedFixture;exit_code=$exitCode;formal_saves_unchanged=$unchanged;godot=$GodotExecutable;timeout_seconds_per_process=$TimeoutSeconds;gpu_timeout_seconds=$GpuTimeoutSeconds;atlas_root=$AtlasRoot;phases=$phases.ToArray()} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outputRoot 'result.json') -Encoding UTF8
    if ($Suite -eq 'c3') { $phases.ToArray() | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $outputRoot 'saveload.json') -Encoding UTF8 }
}
Write-Output ('RESULT=' + (Join-Path $outputRoot 'result.json'))
Write-Output $(if ($exitCode -eq 0) { 'GATE OK' } else { 'GATE FAIL: exit ' + $exitCode })
exit $exitCode

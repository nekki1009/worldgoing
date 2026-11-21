param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$StopFile,
    [string]$TargetScript = 'res://scripts/tests/region_lab_async_test.gd',
    [string]$TargetMode = '--mode=lifecycle',
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 190
)

$ErrorActionPreference = 'Stop'
$startedAt = Get-Date
$deadline = $startedAt.AddSeconds($TimeoutSeconds)
$targetPid = 0
$targetName = ''
$targetStartedAt = $null
$samples = [Collections.Generic.List[object]]::new()
$gpuSamples = 0
$gpuFailure = ''

while ((Get-Date) -lt $deadline) {
    $pollStartedAt = Get-Date
    if (Test-Path -LiteralPath $StopFile -PathType Leaf) { break }
    if ($targetPid -eq 0) {
        $targetCandidates = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notmatch '_console\.exe$' -and
                $_.CreationDate -ge $startedAt.AddSeconds(-2) -and
                $_.CommandLine -and
                $_.CommandLine.IndexOf($TargetScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($TargetMode, [StringComparison]::OrdinalIgnoreCase) -ge 0
            })
        if ($targetCandidates.Count -gt 1) {
            $gpuFailure = 'AMBIGUOUS_TARGET_PROCESSES'
            break
        }
        if ($targetCandidates.Count -eq 1) {
            $targetPid = [int]$targetCandidates[0].ProcessId
            $targetName = [string]$targetCandidates[0].Name
            $targetStartedAt = $targetCandidates[0].CreationDate
        }
    }
    if ($targetPid -ne 0) {
        $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        if ($null -eq $process) { break }
        try {
            $peakWorkingSet = [long]$process.PeakWorkingSet64
            $peakPagedMemory = [long]$process.PeakPagedMemorySize64
        } catch {
            $process.Dispose()
            break
        }
        $process.Dispose()
        $dedicated = $null
        $shared = $null
        try {
            $counter = Get-Counter -Counter '\GPU Process Memory(*)\Dedicated Usage', '\GPU Process Memory(*)\Shared Usage' -ErrorAction Stop
            $gpu = @($counter.CounterSamples | Where-Object {
                $_.InstanceName -match "^pid_${targetPid}_"
            })
            if ($gpu.Count -gt 0) {
                $dedicated = [long](($gpu | Where-Object { $_.Path -match '\\Dedicated Usage$' } |
                    Measure-Object -Property CookedValue -Sum).Sum)
                $shared = [long](($gpu | Where-Object { $_.Path -match '\\Shared Usage$' } |
                    Measure-Object -Property CookedValue -Sum).Sum)
                $gpuSamples++
            }
        } catch {
            if ($gpuFailure -eq '') { $gpuFailure = $_.Exception.Message }
        }
        $samples.Add([ordered]@{
            at = (Get-Date).ToString('o')
            peak_working_set_bytes = $peakWorkingSet
            peak_paged_memory_bytes = $peakPagedMemory
            gpu_dedicated_bytes = $dedicated
            gpu_shared_bytes = $shared
        })
    }
    $remainingMs = 1000 - [int]((Get-Date) - $pollStartedAt).TotalMilliseconds
    if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
}

function Get-MaxSample([string]$Name) {
    $values = @($samples | ForEach-Object { $_[$Name] } | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    return [long](($values | Measure-Object -Maximum).Maximum)
}

$peakWorking = Get-MaxSample 'peak_working_set_bytes'
$peakPaged = Get-MaxSample 'peak_paged_memory_bytes'
$maxDedicated = Get-MaxSample 'gpu_dedicated_bytes'
$maxShared = Get-MaxSample 'gpu_shared_bytes'
$result = [ordered]@{
    status = if ($samples.Count -eq 0) { 'TARGET_NOT_SAMPLED' } else { 'SAMPLED' }
    target_script = $TargetScript
    target_mode = $TargetMode
    pid = if ($targetPid -eq 0) { $null } else { $targetPid }
    process_name = $targetName
    process_started_at = $targetStartedAt
    sampler_started_at = $startedAt.ToString('o')
    interval_seconds = 1
    sample_count = $samples.Count
    peak_working_set_bytes_observed = $peakWorking
    peak_paged_memory_bytes_observed = $peakPaged
    gpu_process_counter_sample_count = $gpuSamples
    gpu_dedicated_bytes_max_observed = $maxDedicated
    gpu_shared_bytes_max_observed = $maxShared
    gpu_counter_note = if ($gpuSamples -eq 0) { 'N/A: no matching per-process GPU counter sample' } else { 'Windows GPU Process Memory performance counter, PID-matched, sampled once per second' }
    gpu_counter_error = $gpuFailure
    samples = $samples.ToArray()
}
$parentDir = Split-Path -Parent $OutputPath
if ($parentDir -and !(Test-Path -LiteralPath $parentDir -PathType Container)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output ("REGION_LAB_PROCESS_MEMORY=" + $result.status + " PID=" + $targetPid + " SAMPLES=" + $samples.Count + " GPU_SAMPLES=" + $gpuSamples)
Write-Output ("RESULT=" + $OutputPath)

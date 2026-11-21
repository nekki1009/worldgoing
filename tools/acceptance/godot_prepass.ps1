<#
.SYNOPSIS
    Fast-fail Godot pre-pass for triage. NOT an acceptance run.

.DESCRIPTION
    Launches Godot exactly like the canonical verify_godot.ps1 (same mode flags,
    isolated APPDATA/LOCALAPPDATA/TEMP under the run folder) but streams the
    output line by line so it can:
      - stop a few seconds after the FIRST failure line (SCRIPT ERROR, Parse
        Error, assertion, crash marker, or a test-base *_FAIL: line),
      - stop when the log exceeds -MaxLogMB,
      - collapse consecutive identical lines (counted, not written),
      - still honour -TimeoutSeconds as the hard ceiling.
    Only the process it started is ever killed (tracked by PID; never by name).
    Results go to <OutRoot>\<runId>\prepass.json plus prepass.log and are
    marked "acceptance": false. A formal receipt still requires the unchanged
    canonical helper; use this pass to find the first error cheaply, confirm a
    fix, or pick cluster representatives before spending a canonical slot.

.EXAMPLE
    .\tools\acceptance\godot_prepass.ps1 -ProjectPath D:\worldgoing -Mode headless `
        -GodotArguments @('--script','res://scripts/tests/site_workflow_test.gd') -TimeoutSeconds 120
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [ValidateSet('headless', 'visual')]
    [string]$Mode = 'headless',

    [string]$GodotExecutable = 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe',

    [string[]]$GodotArguments = @(),

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,

    # Seconds to keep reading after the first failure line so the test's own
    # report/backtrace lands in the log before the process is stopped.
    [ValidateRange(0, 600)]
    [int]$GraceSeconds = 5,

    [switch]$NoStopOnFirstError,

    [ValidateRange(1, 4096)]
    [int]$MaxLogMB = 20,

    # Where pre-pass folders go. Default keeps them apart from canonical receipts.
    [string]$OutRoot = '',

    [string]$Label = ''
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
if (!(Test-Path -LiteralPath (Join-Path $project 'project.godot') -PathType Leaf)) { throw "Not a Godot project: $project" }
if (!(Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    $cmd = Get-Command -Name $GodotExecutable -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw "Godot executable not found: $GodotExecutable" }
    $GodotExecutable = $cmd.Source
}
if (!$OutRoot) { $OutRoot = Join-Path $project '.godot-temp\godot_prepass' }

$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
if ($Label) { $runId = "${runId}_" + ($Label -replace '[^\w\-]', '_') }
$runRoot = Join-Path $OutRoot $runId
$appData = Join-Path $runRoot 'appdata'; $localAppData = Join-Path $runRoot 'localappdata'; $temp = Join-Path $runRoot 'temp'
New-Item -ItemType Directory -Force -Path $appData, $localAppData, $temp | Out-Null
$logPath = Join-Path $runRoot 'prepass.log'
$resultPath = Join-Path $runRoot 'prepass.json'

$arguments = New-Object System.Collections.Generic.List[string]
if ($Mode -eq 'headless') { $arguments.Add('--headless') }
$arguments.Add('--path'); $arguments.Add($project)
foreach ($a in $GodotArguments) { $arguments.Add([string]$a) }

function ConvertTo-ProcessArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

$failurePattern = 'SCRIPT ERROR|Parse Error|assert(?:ion)?(?: failed|_failed)|Segmentation fault|signal\s*11|-1073741819|3221225477|ERROR:'
$noisePattern = 'Failed to read the root certificate store'

$old = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA; TEMP = $env:TEMP; TMP = $env:TMP }
$env:APPDATA = $appData; $env:LOCALAPPDATA = $localAppData; $env:TEMP = $temp; $env:TMP = $temp

$queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$timer = [Diagnostics.Stopwatch]::StartNew()
$process = $null; $pid_ = $null
$stopReason = ''; $firstFailure = $null; $firstFailureAt = $null
$bytes = 0L; $lines = 0L; $written = 0L; $suppressed = 0L
$lastLine = $null; $repeat = 0
$exitCode = $null; $timedOut = $false
$writer = New-Object System.IO.StreamWriter($logPath, $false, (New-Object System.Text.UTF8Encoding($false)))
$events = @()

function Write-Line {
    param([string]$Text)
    $script:lines++
    $script:bytes += [Text.Encoding]::UTF8.GetByteCount($Text) + 2
    if ($Text -eq $script:lastLine) {
        $script:repeat++
        $script:suppressed++
        return
    }
    if ($script:repeat -gt 0) {
        $writer.WriteLine("   [prepass: previous line repeated $($script:repeat) more times]")
        $script:repeat = 0
    }
    $script:lastLine = $Text
    $writer.WriteLine($Text)
    $script:written++
}

try {
    $si = New-Object Diagnostics.ProcessStartInfo
    $si.FileName = $GodotExecutable
    $si.UseShellExecute = $false
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError = $true
    $si.CreateNoWindow = $true
    if ($null -ne $si.ArgumentList) { foreach ($a in $arguments) { [void]$si.ArgumentList.Add($a) } }
    else { $si.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ') }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $si
    $events += Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $queue -Action { if ($null -ne $EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
    $events += Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $queue -Action { if ($null -ne $EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
    if (!$process.Start()) { throw 'Godot process did not start' }
    $pid_ = $process.Id
    $process.BeginOutputReadLine(); $process.BeginErrorReadLine()

    $deadline = $timer.Elapsed.TotalSeconds + $TimeoutSeconds
    while ($true) {
        while ($queue.Count -gt 0) {
            $line = [string]$queue.Dequeue()
            Write-Line $line
            if ($null -eq $firstFailure -and $line -match $failurePattern -and $line -notmatch $noisePattern) {
                $firstFailure = $line
                $firstFailureAt = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
                $writer.WriteLine("   [prepass: FIRST FAILURE at ${firstFailureAt}s]")
            }
        }
        if ($process.HasExited) { break }
        $now = $timer.Elapsed.TotalSeconds
        if ($now -ge $deadline) { $stopReason = 'TIMEOUT'; $timedOut = $true; break }
        if ($bytes -gt $MaxLogMB * 1MB) { $stopReason = 'LOG_CAP'; break }
        if (!$NoStopOnFirstError -and $null -ne $firstFailure -and ($now - $firstFailureAt) -ge $GraceSeconds) { $stopReason = 'FIRST_ERROR'; break }
        Start-Sleep -Milliseconds 100
    }

    if ($stopReason -and !$process.HasExited) {
        # Kill only the process this script started, by PID.
        try { $victim = Get-Process -Id $pid_ -ErrorAction Stop; if ($victim.StartTime -le (Get-Date)) { $victim.Kill() } } catch { }
        $process.WaitForExit(10000) | Out-Null
    }
    if (!$stopReason) { $process.WaitForExit() }
    Start-Sleep -Milliseconds 300
    while ($queue.Count -gt 0) { Write-Line ([string]$queue.Dequeue()) }
    if (!$stopReason) { $exitCode = $process.ExitCode }
} catch {
    $stopReason = 'LAUNCH_ERROR'
    if ($null -eq $firstFailure) { $firstFailure = $_.Exception.Message }
} finally {
    foreach ($e in $events) { Unregister-Event -SourceIdentifier $e.Name -ErrorAction SilentlyContinue }
    if ($repeat -gt 0) { $writer.WriteLine("   [prepass: previous line repeated $repeat more times]") }
    if ($stopReason) { $writer.WriteLine("   [prepass: STOPPED reason=$stopReason]") }
    $writer.Dispose()
    foreach ($k in $old.Keys) { if ($null -ne $old[$k]) { Set-Item -Path "Env:$k" -Value $old[$k] } else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
    if ($null -ne $process) { $process.Dispose() }
}
$timer.Stop()

$status = if ($stopReason -eq 'TIMEOUT') { 'TIMEOUT' }
          elseif ($stopReason -eq 'FIRST_ERROR') { 'FAIL_EARLY' }
          elseif ($stopReason -eq 'LOG_CAP') { 'FAIL_LOGCAP' }
          elseif ($stopReason -eq 'LAUNCH_ERROR') { 'LAUNCH_ERROR' }
          elseif ($null -ne $firstFailure -or $exitCode -ne 0) { 'FAIL' }
          else { 'PASS_PREPASS' }

$result = [ordered]@{
    acceptance        = $false
    note              = 'Triage pre-pass only. A formal receipt requires the unchanged canonical verify_godot.ps1.'
    status            = $status
    mode              = $Mode
    executable        = $GodotExecutable
    arguments         = @($arguments)
    pid               = $pid_
    exit_code         = $exitCode
    timed_out         = $timedOut
    stop_reason       = $stopReason
    duration_seconds  = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
    first_failure     = $firstFailure
    first_failure_at  = $firstFailureAt
    lines_total       = $lines
    lines_written     = $written
    lines_suppressed  = $suppressed
    log_bytes_seen    = $bytes
    log               = $logPath
    max_log_mb        = $MaxLogMB
    grace_seconds     = $GraceSeconds
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8

Write-Output ("GODOT_PREPASS=$status MODE=$Mode EXIT=" + ($(if ($null -eq $exitCode) { 'none' } else { $exitCode })) + " DURATION=" + $result.duration_seconds + "s STOP=" + $(if ($stopReason) { $stopReason } else { 'exit' }))
Write-Output ("RESULT=" + $resultPath)
if ($null -ne $firstFailure) { Write-Output ("FIRST_FAILURE=" + $firstFailure) }
Write-Output ("LINES total=$lines written=$written suppressed=$suppressed bytes=$bytes")
if ($status -eq 'PASS_PREPASS') { exit 0 }
exit 1

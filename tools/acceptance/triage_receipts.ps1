<#
.SYNOPSIS
    Classify Godot verification receipts (result.json) into failure groups.

.DESCRIPTION
    Read-only. Scans one or more run roots for result.json written by the
    canonical verify_godot.ps1 (or copies of those runs), derives the test id,
    a normalized first-failure signature and a category, then writes:
      <OutDir>\triage.json  - every run with its category/signature + summaries
      <OutDir>\triage.md    - human summary: categories, clusters, duplicates,
                              log floods, stale-test candidates, timeouts
    Categories (first match wins):
      TIMEOUT            timed_out = true
      GPU_DESCRIPTOR     descriptor heap exhaustion (visual mode resource)
      DICT_RECURSION     "Maximum dictionary recursion reached"
      LEAK_AT_EXIT       RID/resource leaks or "still in use at exit"
      TEARDOWN_NOISE     "material is null" style teardown errors
      PARSE_STALE        Parse Error / super class path cannot be resolved
      API_MISMATCH       invalid access / nonexistent function / typed array
      INITIAL_WORLD      REGION_INITIAL_WORLD_TRANSACTION_FAIL (fixture base)
      ASSERT             SCRIPT ERROR: Assertion failed
      NO_MESSAGE         FAIL with empty failure line (exit code only)
      OTHER_ERROR        anything else
    An optional stale registry (tools/acceptance/stale_tests.json) marks tests
    as STALE/QUARANTINED so they are reported separately and never counted as
    product defects.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RunsRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$StaleRegistry = '',

    [double]$FloodMB = 50,

    [int]$Top = 25
)

$ErrorActionPreference = 'Stop'

function Get-Category {
    param([string]$Failure, [bool]$TimedOut)
    if ($TimedOut) { return 'TIMEOUT' }
    if ([string]::IsNullOrWhiteSpace($Failure)) { return 'NO_MESSAGE' }
    if ($Failure -match 'descriptor heap') { return 'GPU_DESCRIPTOR' }
    if ($Failure -match 'Maximum dictionary recursion') { return 'DICT_RECURSION' }
    if ($Failure -match 'leaked at exit|still in use at exit|ObjectDB instances leaked') { return 'LEAK_AT_EXIT' }
    if ($Failure -match 'Parameter "material" is null|Resumed function .* after await') { return 'TEARDOWN_NOISE' }
    if ($Failure -match 'Parse Error|Could not resolve super class') { return 'PARSE_STALE' }
    if ($Failure -match 'Invalid access to property|Nonexistent function|on a null value|Invalid operands|Invalid call|Trying to assign an array|Invalid get index|Invalid set index|Invalid type in function') { return 'API_MISMATCH' }
    if ($Failure -match 'REGION_INITIAL_WORLD_TRANSACTION_FAIL') { return 'INITIAL_WORLD' }
    if ($Failure -match 'Assertion failed') { return 'ASSERT' }
    return 'OTHER_ERROR'
}

function Get-Signature {
    param([string]$Failure)
    if ([string]::IsNullOrWhiteSpace($Failure)) { return '' }
    $s = $Failure -replace '\d+', '#'
    $s = $s -replace '\s+', ' '
    if ($s.Length -gt 110) { $s = $s.Substring(0, 110) }
    return $s.Trim()
}

function Get-TestId {
    param($Arguments)
    $args = @($Arguments | ForEach-Object { [string]$_ })
    $script = $args | Where-Object { $_ -match '\.gd$' } | Select-Object -First 1
    if ($script) { return ($script -replace '^res://scripts/tests/', '' -replace '\.gd$', '') }
    $scene = $args | Where-Object { $_ -match '\.tscn$' } | Select-Object -First 1
    if ($scene) { return $scene }
    return ($args -join ' ')
}

$stale = @{}
if ($StaleRegistry -and (Test-Path -LiteralPath $StaleRegistry)) {
    $reg = Get-Content -LiteralPath $StaleRegistry -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in @($reg.tests)) { $stale[[string]$e.test] = $e }
}

$runs = New-Object System.Collections.Generic.List[object]
foreach ($root in $RunsRoot) {
    if (!(Test-Path -LiteralPath $root)) { Write-Warning "Missing root: $root"; continue }
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter result.json -File) {
        try { $j = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { Write-Warning "Unreadable: $($file.FullName)"; continue }
        $dir = $file.Directory
        $logBytes = 0
        foreach ($l in Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter *.log -ErrorAction SilentlyContinue) { $logBytes += $l.Length }
        $failure = [string]$j.failure
        $timedOut = [bool]$j.timed_out
        $test = Get-TestId $j.arguments
        $cat = Get-Category $failure $timedOut
        $staleEntry = $null
        if ($stale.ContainsKey($test)) { $staleEntry = $stale[$test]; $cat = 'STALE_REGISTERED' }
        $ts = $null
        if ($dir.Name -match '(\d{8})_(\d{6})_\d{3}$') {
            try { $ts = [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', $null) } catch { }
        }
        $runs.Add([pscustomobject]@{
            run        = $dir.Name
            path       = $dir.FullName
            started    = $ts
            test       = $test
            mode       = [string]$j.mode
            status     = [string]$j.status
            exit_code  = $j.exit_code
            timed_out  = $timedOut
            duration   = [double]$j.duration_seconds
            failure    = $failure
            signature  = (Get-Signature $failure)
            category   = $cat
            log_mb     = [Math]::Round($logBytes / 1MB, 2)
            flood      = ($logBytes -gt $FloodMB * 1MB)
            stale_note = if ($staleEntry) { [string]$staleEntry.reason } else { '' }
        })
    }
}

if ($runs.Count -eq 0) { throw "No result.json found under: $($RunsRoot -join ', ')" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$fails = @($runs | Where-Object { $_.status -ne 'PASS' })
$passByTest = @{}
foreach ($g in ($runs | Where-Object status -eq 'PASS' | Group-Object test)) {
    $d = @($g.Group | ForEach-Object { $_.duration } | Sort-Object)
    $passByTest[$g.Name] = [pscustomobject]@{ n = $d.Count; p50 = $d[[int]($d.Count / 2)]; max = $d[-1] }
}

$categories = @($fails | Group-Object category | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{
        category = $_.Name
        runs     = $_.Count
        hours    = [Math]::Round((($_.Group | Measure-Object duration -Sum).Sum) / 3600, 2)
        log_mb   = [Math]::Round((($_.Group | Measure-Object log_mb -Sum).Sum), 0)
        tests    = @($_.Group | Select-Object -ExpandProperty test -Unique).Count
    }
})

# Clusters: same signature across tests -> one representative (fastest failing run's test).
$clusters = @($fails | Where-Object { $_.signature } | Group-Object signature | Where-Object { @($_.Group | Select-Object -ExpandProperty test -Unique).Count -ge 2 } | Sort-Object Count -Descending | ForEach-Object {
    $tests = @($_.Group | Select-Object -ExpandProperty test -Unique)
    $rep = ($_.Group | Sort-Object duration | Select-Object -First 1).test
    [pscustomobject]@{
        signature      = $_.Name
        category       = $_.Group[0].category
        runs           = $_.Count
        tests          = $tests
        representative = $rep
        hours          = [Math]::Round((($_.Group | Measure-Object duration -Sum).Sum) / 3600, 2)
    }
})

# Duplicates: same test + same signature run more than once (identical outcome reruns).
$dupes = @($fails | Where-Object { $_.signature } | Group-Object test, signature | Where-Object Count -ge 2 | ForEach-Object {
    $sorted = $_.Group | Sort-Object started
    [pscustomobject]@{
        test         = $sorted[0].test
        signature    = $sorted[0].signature
        runs         = $_.Count
        wasted_hours = [Math]::Round((($sorted | Select-Object -Skip 1 | Measure-Object duration -Sum).Sum) / 3600, 2)
    }
} | Sort-Object wasted_hours -Descending)

$floods = @($runs | Where-Object flood | Sort-Object log_mb -Descending)

$timeouts = @($fails | Where-Object timed_out | Group-Object test | ForEach-Object {
    $p = $passByTest[$_.Name]
    [pscustomobject]@{
        test          = $_.Name
        timeouts      = $_.Count
        timeout_dur   = [Math]::Round(($_.Group | Measure-Object duration -Maximum).Maximum)
        pass_runs     = if ($p) { $p.n } else { 0 }
        pass_max_s    = if ($p) { [Math]::Round($p.max, 1) } else { $null }
        verdict       = if ($p -and $p.max * 3 -lt ($_.Group | Measure-Object duration -Minimum).Minimum) { 'HANG_OR_FLOOD (passes far faster elsewhere)' } elseif ($p) { 'LOAD_OR_REGRESSION' } else { 'NEVER_PASSED' }
    }
} | Sort-Object timeouts -Descending)

$staleCandidates = @($fails | Where-Object { $_.category -in @('PARSE_STALE', 'API_MISMATCH') } | Group-Object test | ForEach-Object {
    [pscustomobject]@{ test = $_.Name; runs = $_.Count; category = $_.Group[0].category; example = $_.Group[0].failure }
} | Sort-Object runs -Descending)

$summary = [ordered]@{
    generated_at   = (Get-Date).ToString('s')
    roots          = $RunsRoot
    runs           = $runs.Count
    pass           = @($runs | Where-Object status -eq 'PASS').Count
    fail           = $fails.Count
    total_hours    = [Math]::Round((($runs | Measure-Object duration -Sum).Sum) / 3600, 2)
    pass_hours     = [Math]::Round((($runs | Where-Object status -eq 'PASS' | Measure-Object duration -Sum).Sum) / 3600, 2)
    fail_hours     = [Math]::Round((($fails | Measure-Object duration -Sum).Sum) / 3600, 2)
    timeout_hours  = [Math]::Round((($fails | Where-Object timed_out | Measure-Object duration -Sum).Sum) / 3600, 2)
    log_gb         = [Math]::Round((($runs | Measure-Object log_mb -Sum).Sum) / 1024, 2)
    flood_runs     = $floods.Count
    flood_log_gb   = [Math]::Round((($floods | Measure-Object log_mb -Sum).Sum) / 1024, 2)
    duplicate_runs = ($dupes | Measure-Object runs -Sum).Sum
    duplicate_hours= [Math]::Round((($dupes | Measure-Object wasted_hours -Sum).Sum), 2)
    distinct_tests = @($runs | Select-Object -ExpandProperty test -Unique).Count
}

$out = [ordered]@{
    summary          = $summary
    categories       = $categories
    clusters         = $clusters
    duplicates       = $dupes
    floods           = @($floods | Select-Object run, test, status, duration, log_mb, failure)
    timeouts         = $timeouts
    stale_candidates = $staleCandidates
    runs             = @($runs | Select-Object run, started, test, mode, status, exit_code, timed_out, duration, category, signature, log_mb, flood, stale_note, path)
}
$out | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'triage.json') -Encoding UTF8

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Receipt triage ($($summary.generated_at))")
[void]$md.AppendLine()
[void]$md.AppendLine("- Roots: " + ($RunsRoot -join '; '))
[void]$md.AppendLine("- Runs: $($summary.runs) (PASS $($summary.pass), FAIL $($summary.fail)); distinct tests $($summary.distinct_tests)")
[void]$md.AppendLine("- Godot hours: $($summary.total_hours) (PASS $($summary.pass_hours), FAIL $($summary.fail_hours), of which timeouts $($summary.timeout_hours))")
[void]$md.AppendLine("- Logs: $($summary.log_gb) GB; flood runs (> $FloodMB MB): $($summary.flood_runs) holding $($summary.flood_log_gb) GB")
[void]$md.AppendLine("- Identical-outcome reruns: $($summary.duplicate_runs) runs, $($summary.duplicate_hours) h beyond the first run")
[void]$md.AppendLine()
[void]$md.AppendLine('## Failure categories')
[void]$md.AppendLine()
[void]$md.AppendLine('| Category | Runs | Hours | Log MB | Tests |'); [void]$md.AppendLine('|---|---|---|---|---|')
foreach ($c in $categories) { [void]$md.AppendLine("| $($c.category) | $($c.runs) | $($c.hours) | $($c.log_mb) | $($c.tests) |") }
[void]$md.AppendLine()
[void]$md.AppendLine("## Shared first-error clusters (top $Top)")
[void]$md.AppendLine()
[void]$md.AppendLine('| Tests | Runs | Hours | Representative | Signature |'); [void]$md.AppendLine('|---|---|---|---|---|')
foreach ($c in ($clusters | Select-Object -First $Top)) { [void]$md.AppendLine("| $($c.tests.Count) | $($c.runs) | $($c.hours) | $($c.representative) | $($c.signature -replace '\|','\|') |") }
[void]$md.AppendLine()
[void]$md.AppendLine("## Identical-outcome reruns (top $Top)")
[void]$md.AppendLine()
[void]$md.AppendLine('| Test | Runs | Wasted h | Signature |'); [void]$md.AppendLine('|---|---|---|---|')
foreach ($d in ($dupes | Select-Object -First $Top)) { [void]$md.AppendLine("| $($d.test) | $($d.runs) | $($d.wasted_hours) | $($d.signature -replace '\|','\|') |") }
[void]$md.AppendLine()
[void]$md.AppendLine("## Log floods (top $Top)")
[void]$md.AppendLine()
[void]$md.AppendLine('| Run | Status | Seconds | Log MB | First failure |'); [void]$md.AppendLine('|---|---|---|---|---|')
foreach ($f in ($floods | Select-Object -First $Top)) { [void]$md.AppendLine("| $($f.run) | $($f.status) | $([Math]::Round($f.duration)) | $($f.log_mb) | $(($f.failure -replace '\|','\|').Substring(0, [Math]::Min(90, $f.failure.Length))) |") }
[void]$md.AppendLine()
[void]$md.AppendLine('## Timeouts by test')
[void]$md.AppendLine()
[void]$md.AppendLine('| Test | Timeouts | Timeout s | PASS runs | PASS max s | Verdict |'); [void]$md.AppendLine('|---|---|---|---|---|---|')
foreach ($t in ($timeouts | Select-Object -First $Top)) { [void]$md.AppendLine("| $($t.test) | $($t.timeouts) | $($t.timeout_dur) | $($t.pass_runs) | $($t.pass_max_s) | $($t.verdict) |") }
[void]$md.AppendLine()
[void]$md.AppendLine('## Stale-test candidates (parse / API mismatch)')
[void]$md.AppendLine()
[void]$md.AppendLine('| Test | Runs | Category | Example |'); [void]$md.AppendLine('|---|---|---|---|')
foreach ($s in ($staleCandidates | Select-Object -First $Top)) { [void]$md.AppendLine("| $($s.test) | $($s.runs) | $($s.category) | $(($s.example -replace '\|','\|').Substring(0, [Math]::Min(100, $s.example.Length))) |") }
$md.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'triage.md') -Encoding UTF8

Write-Output ("TRIAGE runs=$($summary.runs) pass=$($summary.pass) fail=$($summary.fail) hours=$($summary.total_hours) timeout_h=$($summary.timeout_hours) dup_h=$($summary.duplicate_hours) log_gb=$($summary.log_gb)")
Write-Output ("OUT=" + (Join-Path $OutDir 'triage.md'))

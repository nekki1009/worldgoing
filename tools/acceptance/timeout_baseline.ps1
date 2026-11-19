<#
.SYNOPSIS
    Per-test duration baselines from receipts, for reference only.

.DESCRIPTION
    Read-only. From PASS receipts it computes p50/max duration per test; from
    the test source it reads the in-test deadline (Time.get_ticks_msec() + N).
    It then lists:
      - reference_timeout_s : a load-tolerant reference value
                              max(MinSeconds, ceil(pass_max * Multiplier * LoadFactor), deadline_s + DeadlineMargin)
      - deadline_mismatch   : a verifier timeout shorter than the in-test
                              deadline, which kills Godot before the test
                              prints its own report (diagnostics lost)
      - hang_suspects       : timed-out runs on tests whose PASS max is far
                              below the timeout (not load: a hang or a flood)
    These numbers are reference material. Acceptance timeouts are not relaxed
    by this script; any change is a command-center / Nekki decision.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TriageJson,

    [string]$TestsRoot = 'D:\worldgoing\scripts\tests',

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [double]$Multiplier = 2.0,
    [double]$LoadFactor = 1.3,
    [int]$MinSeconds = 60,
    [int]$DeadlineMargin = 30
)

$ErrorActionPreference = 'Stop'
$t = Get-Content -LiteralPath $TriageJson -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$deadlines = @{}
foreach ($f in Get-ChildItem -LiteralPath $TestsRoot -Filter *.gd -File) {
    $m = Select-String -LiteralPath $f.FullName -Pattern 'get_ticks_msec\(\)\s*\+\s*(\d+)' | Select-Object -First 1
    if ($m) { $deadlines[$f.BaseName] = [int]$m.Matches[0].Groups[1].Value / 1000.0 }
}
# Inherit a base script's deadline when the test itself has none.
foreach ($f in Get-ChildItem -LiteralPath $TestsRoot -Filter *_test.gd -File) {
    if ($deadlines.ContainsKey($f.BaseName)) { continue }
    $ext = Select-String -LiteralPath $f.FullName -Pattern '^extends\s+"res://scripts/tests/([^"]+)\.gd"' | Select-Object -First 1
    if ($ext) { $base = $ext.Matches[0].Groups[1].Value; if ($deadlines.ContainsKey($base)) { $deadlines[$f.BaseName] = $deadlines[$base] } }
}

$rows = @()
foreach ($g in ($t.runs | Group-Object test)) {
    $pass = @($g.Group | Where-Object status -eq 'PASS' | ForEach-Object { [double]$_.duration } | Sort-Object)
    $to = @($g.Group | Where-Object timed_out)
    $dl = if ($deadlines.ContainsKey($g.Name)) { [double]$deadlines[$g.Name] } else { $null }
    $passMax = if ($pass.Count) { $pass[-1] } else { $null }
    $passP50 = if ($pass.Count) { $pass[[int]($pass.Count / 2)] } else { $null }
    $usedTimeout = if ($to.Count) { [Math]::Round(($to | Measure-Object duration -Minimum).Minimum) } else { $null }
    $ref = $MinSeconds
    if ($passMax) { $ref = [Math]::Max($ref, [Math]::Ceiling($passMax * $Multiplier * $LoadFactor)) }
    if ($dl) { $ref = [Math]::Max($ref, [Math]::Ceiling($dl + $DeadlineMargin)) }
    $rows += [pscustomobject]@{
        test                = $g.Name
        runs                = $g.Count
        pass_runs           = $pass.Count
        pass_p50_s          = if ($passP50) { [Math]::Round($passP50, 1) } else { $null }
        pass_max_s          = if ($passMax) { [Math]::Round($passMax, 1) } else { $null }
        timeouts            = $to.Count
        timeout_used_s      = $usedTimeout
        in_test_deadline_s  = $dl
        reference_timeout_s = $ref
        deadline_mismatch   = ($dl -and $usedTimeout -and $usedTimeout -lt $dl)
        hang_suspect        = ($to.Count -gt 0 -and $passMax -and ($passMax * 3) -lt $usedTimeout)
    }
}
$rows = $rows | Sort-Object -Property @{ Expression = 'timeouts'; Descending = $true }, @{ Expression = 'runs'; Descending = $true }
$rows | Export-Csv -LiteralPath (Join-Path $OutDir 'timeout_baseline.csv') -NoTypeInformation -Encoding UTF8
[ordered]@{
    generated_at      = (Get-Date).ToString('s')
    parameters        = @{ multiplier = $Multiplier; load_factor = $LoadFactor; min_seconds = $MinSeconds; deadline_margin = $DeadlineMargin }
    note              = 'Reference only. Acceptance timeouts are not changed by this file.'
    tests             = $rows.Count
    deadline_mismatch = @($rows | Where-Object deadline_mismatch)
    hang_suspects     = @($rows | Where-Object hang_suspect)
    rows              = $rows
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'timeout_baseline.json') -Encoding UTF8
Write-Output ("TIMEOUT_BASELINE tests=$($rows.Count) deadline_mismatch=$(@($rows | Where-Object deadline_mismatch).Count) hang_suspects=$(@($rows | Where-Object hang_suspect).Count)")
Write-Output ("OUT=" + (Join-Path $OutDir 'timeout_baseline.csv'))

<#
.SYNOPSIS
    Order a batch of tests so the Godot slot is spent where it tells us most.

.DESCRIPTION
    Read-only. Takes a list of tests (one per line, or a JSON array of objects
    with an "id"/"script" field such as the CC-001 row file) and the latest
    triage.json, and emits an ordered plan:
      tier 1  PREVIOUS_PASS   last known result PASS, fastest first (cheap regression check)
      tier 2  REPRESENTATIVE  one test per shared first-error cluster (fastest failing run)
      tier 3  UNIQUE_FAIL     failing tests whose first error is unique
      tier 4  DEFERRED        other members of a cluster: run only after the
                              representative passes (same first error expected)
      tier 5  TIMEOUT_LAST    tests whose last result timed out (most expensive)
      tier 6  UNKNOWN         no receipt yet
    Tests in the stale registry are listed under QUARANTINED and left out of
    the ordered plan unless -IncludeStale is given.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TriageJson,

    [Parameter(Mandatory = $true)]
    [string]$TestList,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [string]$StaleRegistry = '',

    [switch]$IncludeStale
)

$ErrorActionPreference = 'Stop'
$t = Get-Content -LiteralPath $TriageJson -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Normalize-TestId { param([string]$s) return ($s -replace '^res://scripts/tests/', '' -replace '\.gd$', '').Trim() }

$wanted = @()
$raw = Get-Content -LiteralPath $TestList -Raw -Encoding UTF8
if ($raw.TrimStart().StartsWith('[') -or $raw.TrimStart().StartsWith('{')) {
    $j = $raw | ConvertFrom-Json
    $items = if ($j -is [array]) { $j } elseif ($j.rows) { $j.rows } else { @($j) }
    foreach ($i in $items) {
        $id = if ($i.script) { $i.script } elseif ($i.id) { $i.id } elseif ($i.test) { $i.test } else { [string]$i }
        $wanted += [pscustomobject]@{ test = (Normalize-TestId $id); row = $i.row; serial = $i.serial_index; mode = $i.mode; timeout = $i.timeout_seconds }
    }
} else {
    foreach ($line in ($raw -split "`r?`n")) { if ($line.Trim() -and !$line.StartsWith('#')) { $wanted += [pscustomobject]@{ test = (Normalize-TestId $line); row = $null; serial = $null; mode = $null; timeout = $null } } }
}

$stale = @{}
if ($StaleRegistry -and (Test-Path -LiteralPath $StaleRegistry)) {
    foreach ($e in @((Get-Content -LiteralPath $StaleRegistry -Raw -Encoding UTF8 | ConvertFrom-Json).tests)) { $stale[[string]$e.test] = [string]$e.reason }
}

# Latest run per test.
$latest = @{}
foreach ($g in ($t.runs | Group-Object test)) { $latest[$g.Name] = ($g.Group | Sort-Object { [string]$_.started }, run | Select-Object -Last 1) }
$clusterOf = @{}; $repOf = @{}
foreach ($c in @($t.clusters)) { foreach ($x in @($c.tests)) { $clusterOf[[string]$x] = [string]$c.signature; $repOf[[string]$c.signature] = [string]$c.representative } }

$plan = @(); $quarantined = @()
foreach ($w in $wanted) {
    if ($stale.ContainsKey($w.test) -and !$IncludeStale) { $quarantined += [pscustomobject]@{ test = $w.test; reason = $stale[$w.test] }; continue }
    $l = $latest[$w.test]
    $tier = 6; $label = 'UNKNOWN'; $why = 'no receipt'; $dur = 999999
    if ($l) {
        $dur = [double]$l.duration
        if ($l.status -eq 'PASS') { $tier = 1; $label = 'PREVIOUS_PASS'; $why = "last PASS in $([Math]::Round($dur))s" }
        elseif ($l.timed_out) { $tier = 5; $label = 'TIMEOUT_LAST'; $why = "last run timed out after $([Math]::Round($dur))s" }
        elseif ($clusterOf.ContainsKey($w.test)) {
            $sig = $clusterOf[$w.test]
            if ($repOf[$sig] -eq $w.test) { $tier = 2; $label = 'REPRESENTATIVE'; $why = "represents cluster: $sig" }
            else { $tier = 4; $label = 'DEFERRED'; $why = "same first error as $($repOf[$sig]); run after it passes" }
        } else { $tier = 3; $label = 'UNIQUE_FAIL'; $why = "unique first error: $($l.signature)" }
    }
    $plan += [pscustomobject]@{ tier = $tier; label = $label; test = $w.test; row = $w.row; serial = $w.serial; mode = $w.mode; timeout = $w.timeout; last_status = if ($l) { $l.status } else { '' }; last_duration_s = if ($l) { [Math]::Round($dur, 1) } else { $null }; why = $why }
}
$plan = $plan | Sort-Object tier, last_duration_s, test
$i = 0; $plan = $plan | ForEach-Object { $i++; $_ | Add-Member -NotePropertyName order -NotePropertyValue $i -PassThru }

[ordered]@{
    generated_at = (Get-Date).ToString('s')
    source       = $TestList
    counts       = ($plan | Group-Object label | ForEach-Object { [pscustomobject]@{ label = $_.Name; n = $_.Count } })
    quarantined  = $quarantined
    plan         = $plan
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'batch_plan.json') -Encoding UTF8

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Batch plan ($((Get-Date).ToString('s')))"); [void]$md.AppendLine()
foreach ($c in ($plan | Group-Object label)) { [void]$md.AppendLine("- $($c.Name): $($c.Count)") }
if ($quarantined.Count) { [void]$md.AppendLine("- QUARANTINED (stale registry): $($quarantined.Count)") }
[void]$md.AppendLine(); [void]$md.AppendLine('| # | Tier | Test | Row | Last | s | Why |'); [void]$md.AppendLine('|---|---|---|---|---|---|---|')
foreach ($p in $plan) { [void]$md.AppendLine("| $($p.order) | $($p.label) | $($p.test) | $($p.row) | $($p.last_status) | $($p.last_duration_s) | $(($p.why -replace '\|','\|')) |") }
if ($quarantined.Count) { [void]$md.AppendLine(); [void]$md.AppendLine('## Quarantined'); foreach ($q in $quarantined) { [void]$md.AppendLine("- $($q.test): $($q.reason)") } }
$md.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'batch_plan.md') -Encoding UTF8
Write-Output ("BATCH_PLAN tests=$($plan.Count) " + (($plan | Group-Object label | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' ') + " quarantined=$($quarantined.Count)")
Write-Output ("OUT=" + (Join-Path $OutDir 'batch_plan.md'))

<#
.SYNOPSIS
    Report (never delete) duplicate and oversized logs inside archived runs.

.DESCRIPTION
    Read-only by design: this script deletes nothing. For every run folder that
    holds a result.json it measures stdout.log, stderr.log, combined.log and
    the Godot appdata godot.log, detects byte-identical copies (size match
    first, then SHA-256), and reports how much space a dedupe would reclaim.
    With -WriteDigest it ADDS a log_digest.txt next to oversized logs (head,
    tail, collapsed-repeat histogram) so readers do not need to open a
    multi-GB file. Any actual cleanup of receipt copies is a separate,
    explicitly approved step outside this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RunsRoot,

    [string]$ReportPath = '',

    [double]$LargeMB = 50,

    [switch]$WriteDigest,

    [int]$DigestHeadLines = 150,
    [int]$DigestTailLines = 150,
    [int]$DigestScanLines = 400000
)

$ErrorActionPreference = 'Stop'
$logNames = @('stdout.log', 'stderr.log', 'combined.log')

function Get-Digest {
    param([string]$Path)
    $head = New-Object System.Collections.Generic.List[string]
    $tail = New-Object System.Collections.Generic.Queue[string]
    $hist = @{}
    $n = 0L
    $reader = New-Object System.IO.StreamReader($Path, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $n++
            if ($head.Count -lt $DigestHeadLines) { $head.Add($line) }
            $tail.Enqueue($line); if ($tail.Count -gt $DigestTailLines) { [void]$tail.Dequeue() }
            if ($n -le $DigestScanLines) {
                $key = ($line -replace '\d+', '#').Trim()
                if ($key.Length -gt 120) { $key = $key.Substring(0, 120) }
                if ($key) { if ($hist.ContainsKey($key)) { $hist[$key]++ } else { $hist[$key] = 1 } }
            }
        }
    } finally { $reader.Dispose() }
    $top = $hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 25
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# log_digest for $(Split-Path -Leaf $Path)")
    [void]$sb.AppendLine("lines_total=$n  size_bytes=$((Get-Item -LiteralPath $Path).Length)  histogram_scanned_lines=$([Math]::Min($n, $DigestScanLines))")
    [void]$sb.AppendLine(); [void]$sb.AppendLine('## Most repeated line shapes (digits normalised to #)')
    foreach ($t in $top) { [void]$sb.AppendLine(("{0,10}  {1}" -f $t.Value, $t.Key)) }
    [void]$sb.AppendLine(); [void]$sb.AppendLine("## First $($head.Count) lines")
    foreach ($l in $head) { [void]$sb.AppendLine($l) }
    [void]$sb.AppendLine(); [void]$sb.AppendLine("## Last $($tail.Count) lines")
    foreach ($l in $tail) { [void]$sb.AppendLine($l) }
    return $sb.ToString()
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($root in $RunsRoot) {
    if (!(Test-Path -LiteralPath $root)) { Write-Warning "Missing root: $root"; continue }
    foreach ($res in Get-ChildItem -LiteralPath $root -Recurse -Filter result.json -File) {
        $dir = $res.Directory.FullName
        $files = @()
        foreach ($n in $logNames) { $p = Join-Path $dir $n; if (Test-Path -LiteralPath $p) { $files += Get-Item -LiteralPath $p } }
        $godotLog = Get-ChildItem -LiteralPath $dir -Recurse -Filter godot.log -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($godotLog) { $files += $godotLog }
        $total = ($files | Measure-Object Length -Sum).Sum
        $dupBytes = 0L; $dupNames = @()
        # combined.log is written by the canonical helper as stdout + NewLine + stderr,
        # so it is reconstructible whenever its size equals that sum.
        $so = $files | Where-Object Name -eq 'stdout.log'; $se = $files | Where-Object Name -eq 'stderr.log'; $co = $files | Where-Object Name -eq 'combined.log'
        $combinedRedundant = 0L
        if ($so -and $se -and $co -and $co.Length -eq ($so.Length + $se.Length + [Text.Encoding]::UTF8.GetByteCount([Environment]::NewLine))) { $combinedRedundant = $co.Length }
        $godotLogBytes = if ($godotLog) { $godotLog.Length } else { 0L }
        foreach ($g in ($files | Where-Object Length -gt 0 | Group-Object Length | Where-Object Count -ge 2)) {
            $hashes = $g.Group | ForEach-Object { [pscustomobject]@{ file = $_; hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } }
            foreach ($h in ($hashes | Group-Object hash | Where-Object Count -ge 2)) {
                $extra = $h.Group | Select-Object -Skip 1
                foreach ($x in $extra) { $dupBytes += $x.file.Length; $dupNames += $x.file.Name }
            }
        }
        $large = @($files | Where-Object { $_.Length -gt $LargeMB * 1MB })
        $digests = @()
        if ($WriteDigest) {
            foreach ($lf in $large) {
                $digestPath = Join-Path $lf.DirectoryName ("log_digest_" + $lf.BaseName + ".txt")
                if (!(Test-Path -LiteralPath $digestPath)) { (Get-Digest $lf.FullName) | Set-Content -LiteralPath $digestPath -Encoding UTF8 }
                $digests += $digestPath
            }
        }
        $rows.Add([pscustomobject]@{
            run              = $res.Directory.Name
            path             = $dir
            log_mb           = [Math]::Round($total / 1MB, 2)
            duplicate_mb     = [Math]::Round($dupBytes / 1MB, 2)
            duplicate_files  = ($dupNames -join ';')
            combined_redundant_mb = [Math]::Round($combinedRedundant / 1MB, 2)
            godot_log_mb     = [Math]::Round($godotLogBytes / 1MB, 2)
            large_files      = (($large | ForEach-Object { $_.Name }) -join ';')
            digests_written  = ($digests -join ';')
        })
    }
}

$summary = [ordered]@{
    generated_at        = (Get-Date).ToString('s')
    runs                = $rows.Count
    log_gb              = [Math]::Round((($rows | Measure-Object log_mb -Sum).Sum) / 1024, 2)
    reclaimable_dup_gb  = [Math]::Round((($rows | Measure-Object duplicate_mb -Sum).Sum) / 1024, 2)
    combined_redundant_gb = [Math]::Round((($rows | Measure-Object combined_redundant_mb -Sum).Sum) / 1024, 2)
    godot_appdata_log_gb = [Math]::Round((($rows | Measure-Object godot_log_mb -Sum).Sum) / 1024, 2)
    runs_with_large_log = @($rows | Where-Object large_files).Count
    large_log_gb        = [Math]::Round((($rows | Where-Object large_files | Measure-Object log_mb -Sum).Sum) / 1024, 2)
    digests_written     = @($rows | Where-Object digests_written).Count
    deleted             = 0
}
$out = [ordered]@{ summary = $summary; runs = @($rows | Sort-Object log_mb -Descending) }
if (!$ReportPath) { $ReportPath = Join-Path (Get-Location) 'trim_run_logs_report.json' }
$out | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output ("TRIM_REPORT runs=$($summary.runs) log_gb=$($summary.log_gb) identical_dup_gb=$($summary.reclaimable_dup_gb) combined_redundant_gb=$($summary.combined_redundant_gb) godot_appdata_log_gb=$($summary.godot_appdata_log_gb) large_runs=$($summary.runs_with_large_log) large_gb=$($summary.large_log_gb) deleted=0")
Write-Output ("OUT=$ReportPath")

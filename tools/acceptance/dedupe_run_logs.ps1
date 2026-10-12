<#
.SYNOPSIS
    Remove reconstructible duplicate logs from archived run copies (explicitly approved cleanup).

.DESCRIPTION
    For every run folder holding a result.json it removes at most two files:
      - combined.log      only when its size equals stdout.log + NewLine + stderr.log,
                          i.e. the canonical helper's own construction, so it can be
                          rebuilt from the two files that stay;
      - appdata\...\godot.log  Godot's own file log of the same session (same text as
                          stdout+stderr with a header line).
    stdout.log, stderr.log, result.json, prepass files and everything else are never
    touched. Folders younger than -MinAgeMinutes are skipped so a run being archived
    right now is left alone. Nothing is deleted without -Apply; with -Apply every removed
    file is recorded (path, size, sha256) in a deletion receipt JSON before removal.
    Scope is limited to the roots given; the canonical retention area
    .godot-temp\godot_verify is refused.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RunsRoot,

    [Parameter(Mandatory = $true)]
    [string]$ReceiptPath,

    [switch]$Apply,

    [int]$MinAgeMinutes = 10,

    [switch]$KeepGodotLog
)

$ErrorActionPreference = 'Stop'
$nl = [Text.Encoding]::UTF8.GetByteCount([Environment]::NewLine)
$cutoff = (Get-Date).AddMinutes(-$MinAgeMinutes)
$planned = New-Object System.Collections.Generic.List[object]
$skipped = 0

foreach ($root in $RunsRoot) {
    if (!(Test-Path -LiteralPath $root)) { Write-Warning "Missing root: $root"; continue }
    $full = (Resolve-Path -LiteralPath $root).Path
    if ($full -match '\\\.godot-temp\\godot_verify') { throw "Refusing canonical retention area: $full" }
    foreach ($res in Get-ChildItem -LiteralPath $full -Recurse -Filter result.json -File) {
        $dir = $res.Directory
        if ($dir.LastWriteTime -gt $cutoff -or $res.LastWriteTime -gt $cutoff) { $skipped++; continue }
        $so = Get-Item -LiteralPath (Join-Path $dir.FullName 'stdout.log') -ErrorAction SilentlyContinue
        $se = Get-Item -LiteralPath (Join-Path $dir.FullName 'stderr.log') -ErrorAction SilentlyContinue
        $co = Get-Item -LiteralPath (Join-Path $dir.FullName 'combined.log') -ErrorAction SilentlyContinue
        if ($so -and $se -and $co -and $co.Length -gt 0 -and $co.Length -eq ($so.Length + $se.Length + $nl)) {
            $planned.Add([pscustomobject]@{ run = $dir.FullName; file = $co.FullName; kind = 'combined.log'; bytes = $co.Length })
        }
        if (!$KeepGodotLog) {
            $app = Join-Path $dir.FullName 'appdata'
            if (Test-Path -LiteralPath $app) {
                foreach ($g in Get-ChildItem -LiteralPath $app -Recurse -Filter godot.log -File -ErrorAction SilentlyContinue) {
                    if ($g.Length -gt 0) { $planned.Add([pscustomobject]@{ run = $dir.FullName; file = $g.FullName; kind = 'appdata godot.log'; bytes = $g.Length }) }
                }
            }
        }
    }
}

$totalBytes = ($planned | Measure-Object bytes -Sum).Sum
$removed = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]

if ($Apply) {
    # Manifest first: path, size and hash of every file about to be removed.
    foreach ($p in $planned) { $p | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $p.file -Algorithm SHA256).Hash -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReceiptPath) | Out-Null
    [ordered]@{ generated_at = (Get-Date).ToString('s'); stage = 'manifest_before_delete'; roots = $RunsRoot; files = $planned.Count; bytes = $totalBytes; planned = $planned.ToArray() } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
    foreach ($p in $planned) {
        try {
            $hash = $p.sha256
            Remove-Item -LiteralPath $p.file -Force -ErrorAction Stop
            $removed.Add([pscustomobject]@{ file = $p.file; kind = $p.kind; bytes = $p.bytes; sha256 = $hash })
        } catch {
            $errors.Add([pscustomobject]@{ file = $p.file; error = $_.Exception.Message })
        }
    }
}

$receipt = [ordered]@{
    generated_at    = (Get-Date).ToString('s')
    applied         = [bool]$Apply
    roots           = $RunsRoot
    min_age_minutes = $MinAgeMinutes
    rule            = 'combined.log removed only when size == stdout.log + NewLine + stderr.log; appdata godot.log removed; stdout.log, stderr.log, result.json kept'
    runs_skipped_young = $skipped
    planned_files   = $planned.Count
    planned_gb      = [Math]::Round([double]$totalBytes / 1GB, 2)
    removed_files   = $removed.Count
    removed_gb      = [Math]::Round([double](($removed | Measure-Object bytes -Sum).Sum) / 1GB, 2)
    errors          = $errors.ToArray()
    planned         = $planned.ToArray()
    removed         = $removed.ToArray()
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReceiptPath) | Out-Null
$receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
Write-Output ("DEDUPE applied=$([bool]$Apply) planned_files=$($planned.Count) planned_gb=$($receipt.planned_gb) removed_files=$($removed.Count) removed_gb=$($receipt.removed_gb) errors=$($errors.Count) skipped_young=$skipped")
Write-Output ("RECEIPT=$ReceiptPath")

param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$GodotExecutable = 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe',
    [string]$Verifier = 'C:\Users\Nekki\.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1'
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$evidenceRoot = Join-Path $project 'output/site_army_5k_hot_close_20260926'
$pixelRoot = Join-Path $project 'output/site_army_scale_20260914'
$runName = '{0}_{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss_fff'), $PID
$runDir = Join-Path $evidenceRoot ('pixel_occlusion_runs/' + $runName)
$reportPath = Join-Path $evidenceRoot 'pixel_occlusion_smoke.json'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function Get-Sources {
    $paths = @(
        'project.godot', 'scenes/terrain_lab/TerrainLab.tscn',
        'scripts/tests/verify_site_army_hot_pixels.ps1',
        'scripts/tests/site_army_batch_pixels_test.gd',
        'scripts/tests/fixtures/terrain_army_batch_view_phase3.gd.txt',
        'scripts/terrain_lab/terrain_army.gd',
        'scripts/terrain_lab/terrain_army_batch_view.gd',
        'scripts/terrain_lab/terrain_army_equipment_atlas.gd',
        'scripts/terrain_lab/terrain_army_ranged_atlas.gd',
        'scripts/terrain_lab/terrain_army_dye_atlas.gd',
        'scripts/terrain_lab/terrain_renderer.gd',
        'native/army_idle/army_idle.cpp',
        'native/army_idle/bin/army_idle.windows.x86_64.dll'
    )
    $assetRoot = Join-Path $project 'assets/characters/terrain_lab_army/standard_soldier'
    foreach ($asset in Get-ChildItem -LiteralPath $assetRoot -Recurse -File) {
        $paths += $asset.FullName.Substring($project.Length + 1).Replace('\', '/')
    }
    $result = @{}
    foreach ($relative in $paths) {
        $full = Join-Path $project $relative
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Pixel source missing: $relative"
        }
        $result['res://' + $relative.Replace('\', '/')] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $result
}

$report = [ordered]@{
    schema = 1
    status = 'FAIL'
    generated_by = 'res://scripts/tests/verify_site_army_hot_pixels.ps1'
    failure = 'not_started'
    source_sha256 = @{}
    source_unchanged = $false
    verifier_script_path = $Verifier
    verifier_script_sha256 = ''
    verifier_result = ''
    verifier_result_sha256 = ''
    pixel_result = ''
    pixel_result_sha256 = ''
    stdout_marker = $false
    asset_file_count = 0
    run_dir = 'res://output/site_army_5k_hot_close_20260926/pixel_occlusion_runs/' + $runName
}

try {
    $before = Get-Sources
    $report.source_sha256 = $before
    $report.asset_file_count = @($before.Keys | Where-Object { $_ -like 'res://assets/characters/terrain_lab_army/standard_soldier/*' }).Count
    $verifierBefore = (Get-FileHash -LiteralPath $Verifier -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.verifier_script_sha256 = $verifierBefore
    $previous = @{}
    if (Test-Path -LiteralPath $pixelRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $pixelRoot -Directory -Filter 'pixels_*') {
            $path = Join-Path $directory.FullName 'result.json'
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $previous[$path] = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
            }
        }
    }
    $output = & $Verifier -ProjectPath $project -GodotExecutable $GodotExecutable -Mode visual `
        -GodotArguments @('--script', 'res://scripts/tests/site_army_batch_pixels_test.gd') `
        -TimeoutSeconds 120 2>&1 | Out-String
    [IO.File]::WriteAllText((Join-Path $runDir 'wrapper_output.txt'), $output, (New-Object System.Text.UTF8Encoding($false)))
    $match = [regex]::Match($output, '(?m)^RESULT=(.+)\r?$')
    if (-not $match.Success) { throw 'Canonical verifier did not return RESULT path' }
    $canonicalResult = $match.Groups[1].Value.Trim()
    $resultCopy = Join-Path $runDir 'verifier_result.json'
    Copy-Item -LiteralPath $canonicalResult -Destination $resultCopy
    $verifierRecord = Get-Content -LiteralPath $resultCopy -Raw | ConvertFrom-Json
    foreach ($name in @('stdout', 'stderr', 'combined')) {
        if (Test-Path -LiteralPath $verifierRecord.$name -PathType Leaf) {
            Copy-Item -LiteralPath $verifierRecord.$name -Destination (Join-Path $runDir ($name + '.log'))
        }
    }
    $report.verifier_result = $report.run_dir + '/verifier_result.json'
    $report.verifier_result_sha256 = (Get-FileHash -LiteralPath $resultCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    $stdoutPath = Join-Path $runDir 'stdout.log'
    $report.stdout_marker = (Test-Path -LiteralPath $stdoutPath -PathType Leaf) -and
        ((Get-Content -LiteralPath $stdoutPath -Raw) -match 'ARMY_BATCH_PIXELS_PASS')
    if ($verifierRecord.status -ne 'PASS' -or $verifierRecord.mode -ne 'visual' -or
        [int]$verifierRecord.exit_code -ne 0 -or $verifierRecord.timed_out -or
        -not (@($verifierRecord.arguments) -contains 'res://scripts/tests/site_army_batch_pixels_test.gd')) {
        throw 'Canonical visual verifier did not pass the exact pixel test'
    }
    $fresh = @()
    foreach ($directory in Get-ChildItem -LiteralPath $pixelRoot -Directory -Filter 'pixels_*') {
        $path = Join-Path $directory.FullName 'result.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $ticks = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        if (-not $previous.ContainsKey($path) -or $ticks -gt $previous[$path]) { $fresh += $path }
    }
    if ($fresh.Count -ne 1) { throw "Expected one newly written pixel result, found $($fresh.Count)" }
    $pixelCopy = Join-Path $runDir 'pixel_result.json'
    Copy-Item -LiteralPath $fresh[0] -Destination $pixelCopy
    $pixels = Get-Content -LiteralPath $pixelCopy -Raw | ConvertFrom-Json
    $report.pixel_result = $report.run_dir + '/pixel_result.json'
    $report.pixel_result_sha256 = (Get-FileHash -LiteralPath $pixelCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([int]$pixels.checked -lt 100 -or @($pixels.differences).Count -ne 0 -or
        [int]$pixels.sample_parity_checks -le 0 -or $pixels.native_groups_exercised -ne $true -or
        -not $report.stdout_marker) {
        throw 'Pixel/overlap assertions did not pass'
    }
    $after = Get-Sources
    $report.source_unchanged = $before.Count -eq $after.Count
    foreach ($path in $before.Keys) {
        if (-not $after.ContainsKey($path) -or $after[$path] -ne $before[$path]) {
            $report.source_unchanged = $false
            break
        }
    }
    if (-not $report.source_unchanged -or
        (Get-FileHash -LiteralPath $Verifier -Algorithm SHA256).Hash.ToLowerInvariant() -ne $verifierBefore) {
        throw 'Source or canonical verifier changed during the visual run'
    }
    $report.status = 'PASS'
    $report.failure = ''
}
catch {
    $report.failure = $_.Exception.Message
}

[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "HOT_PIXEL_EVIDENCE=$reportPath STATUS=$($report.status)"
if ($report.status -ne 'PASS') { exit 1 }

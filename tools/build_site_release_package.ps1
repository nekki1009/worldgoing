#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$GodotEditor,
    [Parameter(Mandatory)][string]$StagePath
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path.TrimEnd('\')
$editor = (Resolve-Path -LiteralPath $GodotEditor).Path
$stage = [IO.Path]::GetFullPath($StagePath).TrimEnd('\')
$allowed = [IO.Path]::GetFullPath((Join-Path $project 'output/site_movement_plan_r5_20260929')).TrimEnd('\')
if (-not $stage.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "StagePath must be a new child of $allowed"
}
if (Test-Path -LiteralPath $stage) { throw "Refusing to overwrite an existing package: $stage" }
if (-not (Test-Path -LiteralPath (Join-Path $project 'project.godot'))) { throw 'Not a Godot project' }
if (-not (Test-Path -LiteralPath (Join-Path $project 'export_presets.cfg'))) { throw 'Missing export preset' }
$preset = Get-Content -LiteralPath (Join-Path $project 'export_presets.cfg') -Raw
$templateOption = [regex]::Match($preset, '(?m)^custom_template/release="([^"]*)"')
if (-not $templateOption.Success -or -not $templateOption.Groups[1].Value) {
    throw 'A matching Godot 4.7.2 Mono release template must be configured in SiteFormalRelease first'
}
$template = (Resolve-Path -LiteralPath $templateOption.Groups[1].Value).Path

function Get-SourceHashes {
    $hashes = [ordered]@{}
    $files = @(Get-Item -LiteralPath (Join-Path $project 'project.godot'),
        (Join-Path $project 'worldgoing.csproj'), (Join-Path $project 'export_presets.cfg'),
        (Join-Path $project 'output/site_movement_plan_r5_20260929/.gdignore'))
    foreach ($folder in @('scripts', 'scenes', 'native')) {
        $files += @(Get-ChildItem -LiteralPath (Join-Path $project $folder) -File -Recurse |
            Where-Object { $_.Extension -in @('.gd', '.gdignore', '.cs', '.gdshader', '.tscn', '.tres', '.gdextension', '.cpp', '.h', '.inc', '.dll') })
    }
    foreach ($file in ($files | Sort-Object FullName -Unique)) {
        $relative = [IO.Path]::GetRelativePath($project, $file.FullName).Replace('\', '/')
        $hashes["res://$relative"] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $hashes
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null
$isolated = @{
    APPDATA = (Join-Path $stage 'appdata')
    LOCALAPPDATA = (Join-Path $stage 'localappdata')
    TEMP = (Join-Path $stage 'temp')
    TMP = (Join-Path $stage 'temp')
}
foreach ($key in $isolated.Keys) {
    New-Item -ItemType Directory -Path $isolated[$key] -Force | Out-Null
    [Environment]::SetEnvironmentVariable($key, $isolated[$key], 'Process')
}
# Windows Mono console export can wait forever for the shared C# build server.
[Environment]::SetEnvironmentVariable('UseSharedCompilation', 'false', 'Process')
$before = Get-SourceHashes
$before | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'source_hashes_before.json') -Encoding utf8
$exe = Join-Path $stage 'worldgoing.exe'
$stdout = Join-Path $stage 'export.stdout.log'
$stderr = Join-Path $stage 'export.stderr.log'
$process = Start-Process -FilePath $editor -ArgumentList @('--headless', '--path', $project,
    '--export-release', 'SiteFormalRelease', $exe) -WorkingDirectory $project -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit(300000)) {
    $process.Kill($true)
    throw "Release export exceeded 300 seconds; logs retained in $stage"
}
if ($process.ExitCode -ne 0) { throw "Release export failed with exit code $($process.ExitCode); logs retained in $stage" }
if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath (Join-Path $stage 'worldgoing.pck'))) {
    throw 'Release export did not create both EXE and PCK'
}
$after = Get-SourceHashes
if (($before | ConvertTo-Json -Depth 4 -Compress) -ne ($after | ConvertTo-Json -Depth 4 -Compress)) {
    throw 'Sources changed during export; package is not a frozen baseline'
}

# FileAccess and CPU PNG decoding require loose original files outside the PCK.
$sidecars = @(
    'assets/characters/human/q35/standard_anime_male_character_pack.glb',
    'assets/characters/human/q35/standard_anime_female_character_pack.glb',
    'assets/characters/human/q35/combat/combat_props.glb',
    'assets/mounts/horse/standard_horse_pack.glb'
)
foreach ($folder in @('assets/characters/terrain_lab_army/standard_soldier',
        'assets/characters/terrain_lab_army/standard_female', 'assets/vehicles/logistics/v1')) {
    $sidecars += @(Get-ChildItem -LiteralPath (Join-Path $project $folder) -File -Recurse |
        Where-Object { $_.Extension -in @('.png', '.json', '.glb') } |
        ForEach-Object { [IO.Path]::GetRelativePath($project, $_.FullName).Replace('\', '/') })
}
$sidecarHashes = [ordered]@{}
$bytes = 0L
foreach ($relative in ($sidecars | Sort-Object -Unique)) {
    $inputFile = Join-Path $project $relative
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing source sidecar: $relative" }
    $outputFile = Join-Path $stage $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($outputFile)) -Force | Out-Null
    $sourceHash = (Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not (Test-Path -LiteralPath $outputFile)) {
        Copy-Item -LiteralPath $inputFile -Destination $outputFile
    }
    $copyHash = (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceHash -ne $copyHash) { throw "Sidecar copy hash mismatch: $relative" }
    $sidecarHashes[$relative] = $copyHash
    $bytes += (Get-Item -LiteralPath $outputFile).Length
}

# This staging config exists solely because the canonical verifier requires --path.
# The shipped PCK still supplies the actual scripts and TerrainLab scene.
@'
config_version=5
[application]
config/name="worldgoing release validation"
run/main_scene="res://scenes/terrain_lab/TerrainLab.tscn"
config/features=PackedStringArray("4.7", "C#", "Forward Plus")
[dotnet]
project/assembly_name="worldgoing"
[rendering]
rendering_device/driver.windows="d3d12"
'@ | Set-Content -LiteralPath (Join-Path $stage 'project.godot') -Encoding utf8

$dlls = @(Get-ChildItem -LiteralPath $stage -File -Recurse -Filter '*.dll')
if (-not ($dlls | Where-Object Name -eq 'worldgoing.dll')) { throw 'Exported Mono assembly is missing' }
if (-not ($dlls | Where-Object Name -eq 'army_idle.windows.x86_64.dll')) { throw 'Exported native Army DLL is missing' }
$packageHashes = [ordered]@{}
foreach ($file in (Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName)) {
    $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
    $packageHashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
if (($before | ConvertTo-Json -Depth 4 -Compress) -ne ((Get-SourceHashes) | ConvertTo-Json -Depth 4 -Compress)) {
    throw 'Sources changed while staging sidecars; package is not a frozen baseline'
}
$manifest = [ordered]@{
    format = 1
    created_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_checkout = $project
    source_head = (git -C $project rev-parse HEAD)
    godot_editor_sha256 = (Get-FileHash -LiteralPath $editor -Algorithm SHA256).Hash.ToLowerInvariant()
    release_template = $template
    release_template_sha256 = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash.ToLowerInvariant()
    source_hashes = $before
    sidecar_count = $sidecarHashes.Count
    sidecar_bytes = $bytes
    sidecars = $sidecarHashes
    package_files = $packageHashes
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'site_release_manifest.json') -Encoding utf8
Write-Output "SITE_RELEASE_PACKAGE_READY stage=$stage files=$($packageHashes.Count) sidecars=$($sidecarHashes.Count) bytes=$bytes"

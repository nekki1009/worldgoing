[CmdletBinding()]
param(
    [string]$GodotExecutable = 'Godot_v4.6.2-stable_mono_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$verifyScript = Join-Path $env:USERPROFILE '.codex\skills\godot-runtime-verify\scripts\verify_godot.ps1'
if (!(Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    throw "godot-runtime-verify helper not found: $verifyScript"
}

# ponytail: stage only the CharacterCreator dependency slice; do not copy the
# world map or art files for a state/lifecycle contract that uses in-memory
# sheets.  Full pixel acceptance remains in the image-based Composer tests.
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('worldgoing-paperdoll-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

@'
[application]
config/name="Worldgoing Paper Doll Lifecycle Verify"

[display]
window/size/viewport_width=256
window/size/viewport_height=256

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/default_filters/use_nearest_mipmap_filter=false
'@ | Set-Content -LiteralPath (Join-Path $stageRoot 'project.godot') -Encoding UTF8

$files = @(
    'scripts/data/paper_doll_action_sheet.gd',
    'scripts/data/paper_doll_animation.gd',
    'scripts/data/paper_doll_catalog.gd',
    'scripts/data/paper_doll_layer_visual.gd',
    'scripts/data/paper_doll_mount_visual.gd',
    'scripts/data/paper_doll_preview_draft.gd',
    'scripts/data/paper_doll_recipe.gd',
    'scripts/ui/character_creator.gd',
    'scripts/ui/paper_doll_composer.gd',
    'scripts/ui/paper_doll_contact_sheet.gd',
    'scripts/tools/capture_character_creator_mount_toggle.gd',
    'scripts/tools/verify_character_creator_lifecycle.gd',
    'scripts/tools/verify_character_creator_real_assets.gd',
    'assets/paper_doll/reference_match/reference_match_armed_on_foot_unisex.png',
    'assets/paper_doll/reference_match/reference_match_armed_mounted_unisex.png',
    'scenes/ui/CharacterCreator.tscn'
)
foreach ($relativePath in $files) {
    $source = Join-Path $repoRoot $relativePath
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing lifecycle dependency: $source"
    }
    $destination = Join-Path $stageRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

Write-Output "STAGE=$stageRoot"
& $verifyScript -ProjectPath $stageRoot -GodotExecutable $GodotExecutable -Mode editor -TimeoutSeconds 60
if ($LASTEXITCODE -ne 0) {
    throw "Isolated CharacterCreator editor scan failed with exit code $LASTEXITCODE"
}

& $verifyScript `
    -ProjectPath $stageRoot `
    -GodotExecutable $GodotExecutable `
    -Mode headless `
    -GodotArguments @('--script', 'res://scripts/tools/verify_character_creator_lifecycle.gd') `
    -ExpectedOutput @('.visual_captures/paper_doll/character_creator_lifecycle_contract.txt') `
    -TimeoutSeconds 60
if ($LASTEXITCODE -ne 0) {
    throw "Isolated CharacterCreator lifecycle verification failed with exit code $LASTEXITCODE"
}

$oldAssetRoot = $env:WORLDGOING_PAPERDOLL_ASSET_ROOT
$oldOutputRoot = $env:WORLDGOING_PAPERDOLL_OUTPUT_ROOT
try {
    $env:WORLDGOING_PAPERDOLL_ASSET_ROOT = Join-Path $repoRoot 'assets\paper_doll'
    $env:WORLDGOING_PAPERDOLL_OUTPUT_ROOT = Join-Path $repoRoot '.visual_captures\paper_doll\qa'
    & $verifyScript `
        -ProjectPath $stageRoot `
        -GodotExecutable $GodotExecutable `
        -Mode headless `
        -GodotArguments @('--script', 'res://scripts/tools/verify_character_creator_real_assets.gd') `
        -ExpectedOutput @('.visual_captures/paper_doll/character_creator_real_assets_report.json') `
        -TimeoutSeconds 60
    if ($LASTEXITCODE -ne 0) {
        throw "Real CharacterCreator asset verification failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $oldAssetRoot) { Remove-Item Env:WORLDGOING_PAPERDOLL_ASSET_ROOT -ErrorAction SilentlyContinue }
    else { $env:WORLDGOING_PAPERDOLL_ASSET_ROOT = $oldAssetRoot }
    if ($null -eq $oldOutputRoot) { Remove-Item Env:WORLDGOING_PAPERDOLL_OUTPUT_ROOT -ErrorAction SilentlyContinue }
    else { $env:WORLDGOING_PAPERDOLL_OUTPUT_ROOT = $oldOutputRoot }
}

Write-Output 'CHARACTER_CREATOR_REAL_ASSET_VERIFY_PASS'
Write-Output 'CHARACTER_CREATOR_ISOLATED_VERIFY_PASS'

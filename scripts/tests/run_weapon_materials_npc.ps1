param([ValidateSet('Bake','Masks')][string]$Phase = 'Bake', [switch]$SkipPilot)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskStage = 'output/weapon_materials_npc_20260917'
$catalogText = Get-Content -LiteralPath (Join-Path $taskRoot 'scripts/ui/weapon_materials.gd') -Raw
$catalog = [regex]::Match($catalogText, '(?s)const OPTIONS := (\[.*?\n\])').Groups[1].Value | ConvertFrom-Json
$weapons = @($catalog | Where-Object id -ne 'none' | ForEach-Object { $_.id })
if ($weapons.Count -ne 44) { throw 'Expected the exact 44-option catalogue' }
$keys = if ($Phase -eq 'Masks') { @('base') + $weapons } else { $weapons }
$index = 0
foreach ($key in $keys) {
    $index++
    if ($Phase -eq 'Bake' -and $SkipPilot -and $key -in @('longsword_01_wood','spear_01_stone')) { continue }
    if ($Phase -eq 'Bake') {
        $arguments = @('--script','res://scripts/tools/bake_terrain_army_ranged.gd','--',"--weapon=$key","--output=res://$taskStage/atlases/ranged/$key")
        $expected = "$taskStage/atlases/ranged/$key/manifest.json"
    } else {
        $source = if ($key -eq 'base') { 'res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json' } else { "res://assets/characters/terrain_lab_army/standard_soldier/ranged/v1/$key/manifest.json" }
        $arguments = @('--script','res://scripts/tools/bake_terrain_army_dyes.gd','--',"--source=$source","--output=res://$taskStage/atlases/masks/$key")
        $expected = "$taskStage/atlases/masks/$key.json"
    }
    Write-Output "WEAPON_NPC_PROGRESS $Phase $index/$($keys.Count) $key"
    $runOutput = @(& 'C:/Users/Nekki/.codex/skills/godot-runtime-verify/scripts/verify_godot.ps1' -ProjectPath $taskRoot -GodotExecutable 'C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe' -Mode visual -GodotArguments $arguments -TimeoutSeconds 120 -ExpectedOutput @($expected))
    $runExit = $LASTEXITCODE
    $runOutput | Write-Output
    $resultLine = @($runOutput | Where-Object { "$_".StartsWith('RESULT=') })
    if ($resultLine.Count -eq 1) {
        $runDirectory = Split-Path -Parent $resultLine[0].Substring(7)
        $archive = Join-Path $taskRoot "$taskStage/verification/$(Split-Path -Leaf $runDirectory)"
        New-Item -ItemType Directory -Path $archive -Force | Out-Null
        foreach ($name in @('result.json','stdout.log','stderr.log','combined.log')) { Copy-Item -LiteralPath (Join-Path $runDirectory $name) -Destination (Join-Path $archive $name) }
    }
    if ($runExit -ne 0) { throw "Stopped on failed $Phase $key; retained results, no unchanged retry" }
}
Write-Output "WEAPON_NPC_PHASE_COMPLETE $Phase"

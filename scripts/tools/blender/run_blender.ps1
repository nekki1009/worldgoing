param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $BlenderArguments
)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$localBlender = Join-Path $projectRoot '.tools\blender-4.2.22-windows-x64\blender.exe'
$blenderCommand = Get-Command 'blender.exe' -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $localBlender) {
    $blenderPath = $localBlender
} elseif ($blenderCommand) {
    $blenderPath = $blenderCommand.Source
} else {
    Write-Error 'Worldgoing Blender runtime not found. Run the environment setup first.'
    exit 1
}

$resourceRoot = Join-Path $projectRoot '.godot-temp\blender-user-resources'
New-Item -ItemType Directory -Path $resourceRoot -Force | Out-Null
$env:BLENDER_USER_RESOURCES = $resourceRoot

& $blenderPath @BlenderArguments
exit $LASTEXITCODE

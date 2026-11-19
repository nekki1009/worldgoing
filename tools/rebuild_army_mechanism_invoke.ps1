[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Request, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$taskRequest = Get-Content -LiteralPath $Request -Raw | ConvertFrom-Json
if ($taskRequest.mode -ne 'headless') { throw 'Only non-GPU headless stages are automatic.' }
if ($null -eq $taskRequest.timeout_seconds -or [int]$taskRequest.timeout_seconds -lt 1) { throw 'Explicit canonical timeout required.' }
if ((Get-FileHash -LiteralPath $taskRequest.verifier -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskRequest.verifier_sha256.ToLowerInvariant()) { throw 'Canonical verifier changed.' }
$taskEngineName = [IO.Path]::GetFileNameWithoutExtension($taskRequest.godot_executable)
$taskActive = @(Get-Process | Where-Object { $_.ProcessName -match '^godot' -or $_.ProcessName -eq $taskEngineName })
if ($taskActive.Count -gt 0) { throw 'Existing Godot process: no launch or process killing.' }
if ($CheckOnly) { exit 0 }
& $taskRequest.verifier -ProjectPath $taskRequest.project -GodotExecutable $taskRequest.godot_executable `
    -Mode headless -GodotArguments @($taskRequest.args) -ExpectedOutput @($taskRequest.expected_outputs) `
    -TimeoutSeconds ([int]$taskRequest.timeout_seconds)
exit $LASTEXITCODE

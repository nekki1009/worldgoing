param([string]$Compiler = '', [string]$WindowsSdk = 'C:/Program Files (x86)/Windows Kits/10')
$ErrorActionPreference = 'Stop'
$env:VSLANG = '1033'
if (!$Compiler) {
    $Compiler = & 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC/Tools/MSVC/**/bin/Hostx64/x64/cl.exe' | Select-Object -First 1
}
if (!$Compiler -or !(Test-Path -LiteralPath $Compiler)) { throw 'Install the MSVC x64 build tools or pass -Compiler.' }
$compilerPath = (Resolve-Path -LiteralPath $Compiler).Path
$msvcRoot = Split-Path (Split-Path (Split-Path (Split-Path $compilerPath)))
$sdkVersion = Get-ChildItem -LiteralPath (Join-Path $WindowsSdk 'Lib') -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
$env:INCLUDE = @((Join-Path $msvcRoot 'include'), (Join-Path $WindowsSdk "Include/$sdkVersion/ucrt"), (Join-Path $WindowsSdk "Include/$sdkVersion/shared"), (Join-Path $WindowsSdk "Include/$sdkVersion/um")) -join ';'
$env:LIB = @((Join-Path $msvcRoot 'lib/x64'), (Join-Path $WindowsSdk "Lib/$sdkVersion/ucrt/x64"), (Join-Path $WindowsSdk "Lib/$sdkVersion/um/x64")) -join ';'
$buildRoot = New-Item -ItemType Directory -Force -Path .godot-temp/army_idle_build
$logRoot = New-Item -ItemType Directory -Force -Path (Join-Path $buildRoot.FullName (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force -Path native/army_idle/bin | Out-Null
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $compilerPath
$info.Arguments = '/nologo /std:c++17 /EHsc /O2 /fp:strict /MT /W4 /WX /LD native/army_idle/army_idle.cpp /Fo.godot-temp/army_idle_build/army_idle.obj /Fe.godot-temp/army_idle_build/army_idle.dll /link /IMPLIB:.godot-temp/army_idle_build/army_idle.lib'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($info)
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Army idle build exceeded the 60-second deadline.' }
$stdout.Result
$stderr.Result
[IO.File]::WriteAllText((Join-Path $logRoot.FullName 'stdout.txt'), $stdout.Result)
[IO.File]::WriteAllText((Join-Path $logRoot.FullName 'stderr.txt'), $stderr.Result)
[IO.File]::WriteAllText((Join-Path $logRoot.FullName 'result.json'), (@{exit_code=$process.ExitCode; compiler=$compilerPath; arguments=$info.Arguments} | ConvertTo-Json))
if ($process.ExitCode -ne 0) { exit $process.ExitCode }
Copy-Item -LiteralPath (Join-Path $buildRoot.FullName 'army_idle.dll') -Destination native/army_idle/bin/army_idle.windows.x86_64.dll
Get-FileHash -LiteralPath native/army_idle/bin/army_idle.windows.x86_64.dll -Algorithm SHA256

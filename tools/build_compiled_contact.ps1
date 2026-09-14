param([string]$GodotPackages = 'C:/Users/Nekki/Godot_v4.6.2-stable_mono_win64/GodotSharp/Tools/nupkgs', [switch]$Bootstrap)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $GodotPackages -PathType Container)) { throw 'Point -GodotPackages to the installed GodotSharp/Tools/nupkgs folder.' }
$buildRoot = Join-Path (Get-Location) '.godot-temp/compiled_contact'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
# These are generated, ignored build inputs. No user/global NuGet settings change.
$escapedPackages = [Security.SecurityElement]::Escape((Resolve-Path -LiteralPath $GodotPackages).Path)
[IO.File]::WriteAllText((Join-Path $buildRoot 'NuGet.Config'), '<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><clear/><add key="installed-godot" value="' + $escapedPackages + '"/></packageSources></configuration>')
[IO.File]::WriteAllText((Join-Path $buildRoot 'bootstrap.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework><NuGetAudit>false</NuGetAudit></PropertyGroup><ItemGroup><PackageDownload Include="Godot.NET.Sdk" Version="[4.6.2]"/></ItemGroup></Project>')
$env:DOTNET_CLI_HOME = Join-Path (Get-Location) '.godot-temp/compiled_contact/dotnet-home'
$env:NUGET_PACKAGES = Join-Path (Get-Location) '.godot-temp/compiled_contact/packages'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
if (!$Bootstrap -and !(Test-Path -LiteralPath (Join-Path $env:NUGET_PACKAGES 'godot.net.sdk/4.6.2/Sdk/Sdk.props'))) {
    & $PSCommandPath -GodotPackages $GodotPackages -Bootstrap
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$buildInfo = New-Object System.Diagnostics.ProcessStartInfo
$buildInfo.FileName = (Get-Command dotnet.exe -ErrorAction Stop).Source
$buildInfo.Arguments = if ($Bootstrap) {
    'restore .godot-temp/compiled_contact/bootstrap.csproj --configfile .godot-temp/compiled_contact/NuGet.Config --disable-parallel'
} else {
    'build worldgoing.csproj --configfile .godot-temp/compiled_contact/NuGet.Config -p:RestoreSources="' + $GodotPackages + '" -p:Optimize=true -p:UseSharedCompilation=false --disable-build-servers'
}
$buildInfo.UseShellExecute = $false
$buildInfo.CreateNoWindow = $true
$buildInfo.RedirectStandardOutput = $true
$buildInfo.RedirectStandardError = $true
$buildProcess = [Diagnostics.Process]::Start($buildInfo)
$buildOut = $buildProcess.StandardOutput.ReadToEndAsync()
$buildErr = $buildProcess.StandardError.ReadToEndAsync()
if (-not $buildProcess.WaitForExit(60000)) { $buildProcess.Kill(); throw 'Compiled contact build exceeded 60-second deadline' }
$buildOut.Result
$buildErr.Result
exit $buildProcess.ExitCode

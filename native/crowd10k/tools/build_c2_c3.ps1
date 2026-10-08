param([switch]$RunTests,[switch]$Asan,[string]$OutputRoot='',[string]$ReplayBlob='',[string]$ReplayHash='')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if(!$OutputRoot) { $OutputRoot=Join-Path $root 'output/crowd_c2_c3_native' }
elseif(![IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot=Join-Path $root $OutputRoot }
$run=Join-Path $OutputRoot (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
New-Item -ItemType Directory -Force -Path $run | Out-Null
$compiler=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC/Tools/MSVC/**/bin/Hostx64/x64/cl.exe' | Select-Object -First 1
$msvcRoot=Split-Path (Split-Path (Split-Path (Split-Path $compiler)))
$sdk='C:/Program Files (x86)/Windows Kits/10'
$version=Get-ChildItem -LiteralPath "$sdk/Lib" -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name
$env:INCLUDE=@("$msvcRoot/include","$sdk/Include/$version/ucrt","$sdk/Include/$version/shared","$sdk/Include/$version/um") -join ';'
$env:LIB=@("$msvcRoot/lib/x64","$sdk/Lib/$version/ucrt/x64","$sdk/Lib/$version/um/x64") -join ';'
$env:PATH=(Split-Path $compiler)+';'+$env:PATH
$env:VSLANG='1033'
$flags='/nologo /O2 /fp:precise /EHsc /std:c++17 /utf-8 /MT /W3 /WX'
if($Asan) { $flags+=' /fsanitize=address /Zi' }
$sourceList=Get-ChildItem -Path "$root/native/crowd10k/src/*","$root/native/crowd10k/godot/*","$root/native/crowd10k/tests/*","$root/native/crowd10k/tools/*" -File | Where-Object { $_.Extension -in '.h','.hpp','.c','.cpp' } | Sort-Object FullName
$identity=@("compiler=$compiler", "version=$((Get-Item $compiler).VersionInfo.FileVersion)","flags=$flags")
foreach($source in $sourceList) { $identity+=($source.FullName.Substring($root.Length+1)+'='+(Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash) }
$buildId=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($identity -join "`n")))).ToLowerInvariant()
[IO.File]::WriteAllText("$run/build_id.h", "#define WG_CROWD_BUILD_ID `"$buildId`"`n")
$identity | Set-Content "$run/build_identity.txt"
function Invoke-Bounded([string]$Name,[string]$Exe,[string]$Arguments,[int]$Timeout=180) {
 $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Exe;$info.Arguments=$Arguments;$info.WorkingDirectory=$root
 $info.StandardOutputEncoding=[Text.Encoding]::GetEncoding(950);$info.StandardErrorEncoding=[Text.Encoding]::GetEncoding(950);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($info);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$watch=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false
 while(!$process.WaitForExit(1000)) { if($watch.Elapsed.TotalSeconds -gt $Timeout) { $timedOut=$true;$process.Kill($true);$process.WaitForExit();break } }
 [IO.File]::WriteAllText("$run/$Name.stdout.txt",$stdout.Result);[IO.File]::WriteAllText("$run/$Name.stderr.txt",$stderr.Result)
 @{exit_code=$process.ExitCode;compiler=$compiler;arguments=$Arguments;duration=$watch.Elapsed.TotalSeconds;timeout_seconds=$Timeout;timed_out=$timedOut;build_id=$buildId;asan=[bool]$Asan} | ConvertTo-Json | Set-Content "$run/$Name.result.json"
 $stdout.Result;$stderr.Result;Write-Output "$Name EXIT=$($process.ExitCode) RUN=$run"
 if($process.ExitCode -ne 0 -or $timedOut) { throw "$Name failed; evidence preserved at $run" }
}
$src='crowd_core combat command ai crowd_c_api state render'.Split(' ') | ForEach-Object { "$root/native/crowd10k/src/$_.cpp" }
Invoke-Bounded 'compile_core' $compiler "$flags /c $($src -join ' ') /Fo$run/"
$objects='crowd_core combat command ai crowd_c_api state render'.Split(' ') | ForEach-Object { "$run/$_.obj" }
Invoke-Bounded 'compile_binding' $compiler "$flags /LD /I$run $root/native/crowd10k/godot/crowd10k_gdext.cpp $($objects -join ' ') /Fo$run/crowd10k_gdext.obj /Fe$run/crowd10k.windows.x86_64.dll /link /IMPLIB:$run/crowd10k.lib"
foreach($test in 'scenario_tests','c2_c3_tests','rules_vectors') { Invoke-Bounded "build_$test" $compiler "$flags $root/native/crowd10k/tests/$test.cpp $($objects -join ' ') /Fo$run/$test.obj /Fe$run/$test.exe" }
$cflags=$flags.Replace('/std:c++17','')
Invoke-Bounded 'build_api_test' $compiler "$cflags $root/native/crowd10k/src/api_test.c $($objects -join ' ') /Fo$run/api_test.obj /Fe$run/api_test.exe"
if($RunTests) {
 if($ReplayBlob) {
  $replayArgs='--replay "'+$ReplayBlob+'" '+$ReplayHash
  Invoke-Bounded 'd6_blob_replay' "$run/c2_c3_tests.exe" $replayArgs 120
 }
 Invoke-Bounded 'rules_reference' (Get-Command python -ErrorAction Stop).Source "$root/native/crowd10k/tools/gd_reference.py $run/rules_vectors.exe" 120
 Invoke-Bounded 'c2_c3_tests' "$run/c2_c3_tests.exe" '' 120
 Invoke-Bounded 'api_test' "$run/api_test.exe" '' 120
 Invoke-Bounded 'scenario_tests' "$run/scenario_tests.exe" '' 120
 Invoke-Bounded 'c2_c3_fuzz' "$run/c2_c3_tests.exe" '--fuzz' 120
}
@{run=$run;build_id=$buildId;dll_sha256=(Get-FileHash "$run/crowd10k.windows.x86_64.dll" -Algorithm SHA256).Hash;tests_run=[bool]$RunTests;asan=[bool]$Asan} | ConvertTo-Json | Set-Content "$run/result.json"
Write-Output "SUCCESS=$run"

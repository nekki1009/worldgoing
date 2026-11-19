@echo off
rem crowd10k v2 - build with Visual Studio and run tests + benchmark.
rem Run from "x64 Native Tools Command Prompt for VS" (same toolchain as tools\build_army_idle.ps1).
rem Build files and raw results go to %LOCALAPPDATA%\worldgoing_crowd10k (outside Dropbox):
rem Dropbox locks freshly written .obj files, which caused "C1083 ... Permission denied".
rem Gate: compiler warnings are errors (/WX), any failing test or bench exit code stops the batch.
setlocal
pushd "%~dp0"
set "WORK=%LOCALAPPDATA%\worldgoing_crowd10k"
set "BUILD=%WORK%\build"
set "OUT=%WORK%\out"
set RUNNO=0
if not exist "%BUILD%" mkdir "%BUILD%"
if not exist "%OUT%" mkdir "%OUT%"
set FLAGS=/nologo /O2 /fp:precise /EHsc /std:c++17 /utf-8 /MT /W3 /WX

echo === 1/3 compile core (once) ===
cl %FLAGS% /c src\crowd_core.cpp src\combat.cpp src\command.cpp src\ai.cpp src\crowd_c_api.cpp src\state.cpp src\render.cpp /Fo"%BUILD%\\"
if errorlevel 1 goto fail
lib /nologo /OUT:"%BUILD%\crowd_core.lib" "%BUILD%\crowd_core.obj" "%BUILD%\combat.obj" "%BUILD%\command.obj" "%BUILD%\ai.obj" "%BUILD%\crowd_c_api.obj" "%BUILD%\state.obj" "%BUILD%\render.obj"
if errorlevel 1 goto fail
cl %FLAGS% src\bench.cpp "%BUILD%\crowd_core.lib" /Fo"%BUILD%\\" /Fe"%BUILD%\crowd_bench.exe"
if errorlevel 1 goto fail
cl %FLAGS% tests\scenario_tests.cpp "%BUILD%\crowd_core.lib" /Fo"%BUILD%\\" /Fe"%BUILD%\crowd_scenario_tests.exe"
if errorlevel 1 goto fail
cl %FLAGS% tests\rules_vectors.cpp /Fo"%BUILD%\\" /Fe"%BUILD%\crowd_rules_vectors.exe"
if errorlevel 1 goto fail
cl /nologo /O2 /MT /utf-8 /W3 /WX src\api_test.c "%BUILD%\crowd_core.lib" /Fo"%BUILD%\\" /Fe"%BUILD%\crowd_api_test.exe"
if errorlevel 1 goto fail

echo === 2/3 rule tests ===
"%BUILD%\crowd_scenario_tests.exe"
if errorlevel 1 goto fail
"%BUILD%\crowd_api_test.exe"
if errorlevel 1 goto fail
where python >nul 2>nul && python tools\gd_reference.py "%BUILD%\crowd_rules_vectors.exe"

echo === 3/3 benchmark (about 10-15 minutes) ===
set "BENCH=%BUILD%\crowd_bench.exe"
rem Every run writes result_*.json, series_*.csv (per 5 s: step time, alive, down, fighting, deaths, routs ...)
rem and a console log. A bench exit code other than 0 (invariant violation) stops the batch.
call :run base   --n 10000 --threads 1 --seconds 120 --scenario battle
if errorlevel 1 goto fail
call :run base   --n 10000 --threads 4 --seconds 120 --scenario battle
if errorlevel 1 goto fail
call :run base   --n 10000 --threads 8 --seconds 120 --scenario battle
if errorlevel 1 goto fail
call :run base   --n 10000 --threads 1 --seconds 120 --scenario melee
if errorlevel 1 goto fail
call :run base   --n 10000 --threads 8 --seconds 120 --scenario melee
if errorlevel 1 goto fail
call :run base   --n 20000 --map 320 --threads 8 --seconds 120 --scenario battle
if errorlevel 1 goto fail
rem three factions with ids 0 / 2 / 5, all hostile (Astra review 2026-09-29), plus 7 minutes after the battle
call :run three  --n 10000 --map 320 --threads 8 --seconds 120 --scenario three --aftermath 420
if errorlevel 1 goto fail
rem wounded: 7 minutes after the battle: both sides step back 15 cells and hold; the Site clock
rem leaves combat 10 s after the last combat event (then 1 s = 1 game minute), about 5 game hours in all
rem   original = adjacent rescue only, captures by explicit order only
rem   default  = 2026-09-29 decision: walk 8 cells to rescue, AI auto-capture within 8 cells
call :run original --n 10000 --threads 8 --seconds 120 --scenario battle --aftermath 420 --rescue-seek 0 --no-auto-capture
if errorlevel 1 goto fail
call :run default  --n 10000 --threads 8 --seconds 120 --scenario battle --aftermath 420
if errorlevel 1 goto fail
if not exist out mkdir out
for %%D in (base three original default) do (
  if not exist out\%%D mkdir out\%%D
  copy /y "%OUT%\%%D\*.json" out\%%D\ >nul
  copy /y "%OUT%\%%D\*.csv" out\%%D\ >nul
  copy /y "%OUT%\%%D\*.log" out\%%D\ >nul
)
echo.
echo Results: %OUT%  (also copied to %~dp0out)
popd
exit /b 0

:fail
echo.
echo *** build, test or bench gate failed - please send the text above ***
popd
exit /b 1

:run
rem %1 = output group, the rest = bench arguments; console output is shown and kept in a log
set "GRP=%~1"
if not exist "%OUT%\%GRP%" mkdir "%OUT%\%GRP%"
set /a RUNNO+=1
set "LOG=%OUT%\%GRP%\run_%RUNNO%.log"
shift
set "ARGS="
:args
if "%~1"=="" goto go
set "ARGS=%ARGS% %1"
shift
goto args
:go
echo --- %BENCH% %ARGS%
"%BENCH%" %ARGS% --out "%OUT%\%GRP%" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
exit /b %RC%

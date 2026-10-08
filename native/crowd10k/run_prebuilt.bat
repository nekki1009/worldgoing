@echo off
rem crowd10k v2 - run the prebuilt Windows binaries in bin\ (no Visual Studio needed).
rem Just double-click this file. Results: %LOCALAPPDATA%\worldgoing_crowd10k\out (copied to .\out at the end).
rem The binaries are built with MinGW-w64 (g++ 13, -O2, static); MSVC numbers may differ a little.
setlocal
pushd "%~dp0"
set "OUT=%LOCALAPPDATA%\worldgoing_crowd10k\out"
set RUNNO=0
if not exist "%OUT%" mkdir "%OUT%"

echo === rule tests ===
bin\crowd_scenario_tests.exe
if errorlevel 1 goto fail
bin\crowd_api_test.exe
if errorlevel 1 goto fail

echo.
echo === benchmark (about 10-15 minutes) ===
set "BENCH=%~dp0bin\crowd_bench.exe"
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
echo Done. Results: %OUT%  (also copied to %~dp0out)
popd
pause
exit /b 0

:fail
echo.
echo *** a test or bench gate failed - please send the text above ***
popd
pause
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

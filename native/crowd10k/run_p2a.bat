@echo off
rem crowd10k P2a in the D: test copy: the native core inside Godot on a generated Site map.
rem Double-click. About 8-10 minutes. A window opens for the last run (about 1 minute); leave it alone.
rem Results: native\crowd10k\out_p2a (JSON per run, one PNG from the render run, and the console logs).
setlocal
pushd "%~dp0..\.."
set "PROJ=%CD%"
popd
set "OUT=%PROJ%\native\crowd10k\out_p2a"
if not exist "%OUT%" mkdir "%OUT%"
rem keep Godot from importing the result PNG / JSON / CSV files as project assets
if not exist "%OUT%\.gdignore" type nul > "%OUT%\.gdignore"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\*console*.exe") do set "GODOT=%%~fG"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\Godot*.exe") do set "GODOT=%%~fG"
if not defined GODOT goto no_godot
echo Godot:   "%GODOT%"
echo Project: "%PROJ%"
echo.
set SCRIPT=res://scripts/tests/crowd10k_site_bench.gd
set RUNNO=0

call :run headless --mode sim --preset 1 --formations 50 --per 100 --factions 3 --seconds 120 --threads 8
if errorlevel 1 goto fail
call :run headless --mode sim --preset 0 --formations 50 --per 100 --factions 3 --seconds 120 --threads 8
if errorlevel 1 goto fail
call :run headless --mode sim --preset 1 --formations 50 --per 100 --factions 3 --seconds 120 --threads 1
if errorlevel 1 goto fail
call :run window --mode render --preset 1 --formations 50 --per 100 --factions 3 --seconds 60 --threads 8
if errorlevel 1 goto fail
echo.
echo Done. Results: %OUT%
pause
exit /b 0

:no_godot
echo Cannot find Godot under %USERPROFILE%\Godot_v4.7.2-stable_mono_win64
echo Set GODOT to the Godot console exe and run again.
goto fail
:fail
echo.
echo *** a run failed - please send the text above ***
pause
exit /b 1

:run
set /a RUNNO+=1
set "LOG=%OUT%\run_%RUNNO%.log"
set "HEADLESS="
if "%~1"=="headless" set "HEADLESS=--headless"
shift
set "ARGS="
:args
if "%~1"=="" goto go
set "ARGS=%ARGS% %1"
shift
goto args
:go
echo --- run %RUNNO%: %HEADLESS% %ARGS%
"%GODOT%" %HEADLESS% --path "%PROJ%" --script %SCRIPT% -- %ARGS% --out res://native/crowd10k/out_p2a > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
findstr /B /C:"terrain:" /C:"deployed" /C:"==" /C:"step " /C:"determinism" /C:"frame " /C:"sim/frame" /C:"final " /C:"GATE" /C:"CROWD10K FAIL" /C:"SCRIPT ERROR" /C:"ERROR" "%LOG%"
echo exit code %RC%
exit /b %RC%

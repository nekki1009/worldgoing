@echo off
rem crowd10k P2d in the D: test copy: the player is one soldier of the 5,000 crowd under every soldier
rem rule (pushing, exchange rounds, stun / KO, bleeding, rescue, capture); only his wish to move and fight
rem comes from the host - here he walks to the nearest enemy and fights. The real TerrainTestCharacter
rem only presents him (position, pose, facing). Double-click; about 3 minutes.
rem Three windows open one after the other (45 s each). Please WATCH 1:
rem   1) plains, camera follows the player   2) terraced highland (cliffs), follows the player
rem   3) plains, whole map
rem Results: native\crowd10k\out_p2c (JSON + a screenshot per run, console logs).
setlocal
pushd "%~dp0..\.."
set "PROJ=%CD%"
popd
set "OUT=%PROJ%\native\crowd10k\out_p2c"
if not exist "%OUT%" mkdir "%OUT%"
rem keep Godot from importing the result PNG / JSON / CSV files as project assets
if not exist "%OUT%\.gdignore" type nul > "%OUT%\.gdignore"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\*console*.exe") do set "GODOT=%%~fG"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\Godot*.exe") do set "GODOT=%%~fG"
if not defined GODOT goto no_godot
echo Godot:   "%GODOT%"
echo Project: "%PROJ%"
echo.
set RUNNO=0
call :run --seconds 45 --preset 0 --player 1 --engage 1 --zoom 1.5 --threads 8
if errorlevel 1 goto fail
call :run --seconds 45 --preset 1 --player 1 --engage 1 --zoom 1.5 --threads 8
if errorlevel 1 goto fail
call :run --seconds 45 --preset 0 --player 1 --engage 1 --zoom 0 --threads 8
if errorlevel 1 goto fail
echo.
echo Done. Results: %OUT%
pause
exit /b 0

:no_godot
echo Cannot find Godot under %USERPROFILE%\Godot_v4.7.2-stable_mono_win64
goto fail
:fail
echo.
echo *** a run failed - please send the text above ***
pause
exit /b 1

:run
set /a RUNNO+=1
set "LOG=%OUT%\run_%RUNNO%.log"
echo --- run %RUNNO%: %*
"%GODOT%" --path "%PROJ%" --script res://scripts/tests/crowd10k_occlusion_bench.gd -- %* --out res://native/crowd10k/out_p2c > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
findstr /C:"player:" /C:"check " /C:"==" /C:"frame " /C:"sim/frame" /C:"gpu " /C:"nodes " /C:"final " /C:"order_ok" /C:"player soldier" /C:"GATE" /C:"FAIL" /C:"SCRIPT ERROR" /C:"Parse Error" "%LOG%"
echo exit code %RC%
exit /b %RC%

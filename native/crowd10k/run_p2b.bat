@echo off
rem crowd10k P2b in the D: test copy: 5,000 soldiers drawn with the game's own soldier atlas, materials
rem and batch shader (faction colours through the game's dye slots). Double-click; about 3 minutes.
rem Two windows open one after the other (1 minute each): the whole map, then game scale. Leave them alone.
rem Results: native\crowd10k\out_p2b (JSON + a screenshot per run, console logs).
setlocal
pushd "%~dp0..\.."
set "PROJ=%CD%"
popd
set "OUT=%PROJ%\native\crowd10k\out_p2b"
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
call :run --seconds 60 --zoom 0 --threads 8
if errorlevel 1 goto fail
call :run --seconds 60 --zoom 1.0 --threads 8
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
"%GODOT%" --path "%PROJ%" --script res://scripts/tests/crowd10k_atlas_bench.gd -- %* --out res://native/crowd10k/out_p2b > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
findstr /C:"atlas:" /C:"kit " /C:"clips not" /C:"==" /C:"frame " /C:"sim/frame" /C:"gpu " /C:"final " /C:"GATE" /C:"FAIL" /C:"SCRIPT ERROR" /C:"Parse Error" "%LOG%"
echo exit code %RC%
exit /b %RC%

@echo off
rem crowd10k C1 in the D: test copy: the formal TerrainLab with the native crowd instead of TerrainArmy.
rem 1) checks the two changed scripts for errors, 2) starts the game with --crowd.
rem In the game: open the trial deployment panel, set 我方 / 敵方 team counts (25 + 25 = 5,000) and press
rem 「空場部署多支百人隊」. You are one of the soldiers: WASD / arrows walk, Shift runs, HOLD Space to fight.
rem 「清除測試隊伍」 removes the crowd. Close the game window when done; the log is kept in out_c1.
setlocal
pushd "%~dp0..\.."
set "PROJ=%CD%"
popd
set "OUT=%PROJ%\native\crowd10k\out_c1"
if not exist "%OUT%" mkdir "%OUT%"
rem keep Godot from importing the result PNG / JSON / CSV files as project assets
if not exist "%OUT%\.gdignore" type nul > "%OUT%\.gdignore"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\*console*.exe") do set "GODOT=%%~fG"
if not defined GODOT for %%G in ("%USERPROFILE%\Godot_v4.7.2-stable_mono_win64\Godot*.exe") do set "GODOT=%%~fG"
if not defined GODOT goto no_godot
echo Godot:   "%GODOT%"
echo Project: "%PROJ%"
echo.
echo --- script check
"%GODOT%" --headless --path "%PROJ%" --check-only --script res://scripts/terrain_lab/crowd_site.gd > "%OUT%\check_crowd_site.log" 2>&1
findstr /C:"SCRIPT ERROR" /C:"Parse Error" /C:"ERROR:" "%OUT%\check_crowd_site.log"
"%GODOT%" --headless --path "%PROJ%" --check-only --script res://scripts/terrain_lab/terrain_lab.gd > "%OUT%\check_terrain_lab.log" 2>&1
findstr /C:"SCRIPT ERROR" /C:"Parse Error" "%OUT%\check_terrain_lab.log"
echo --- starting the game in crowd mode (close its window to finish)
"%GODOT%" --path "%PROJ%" -- --crowd > "%OUT%\game.log" 2>&1
echo.
echo --- log summary
findstr /C:"crowd10k" /C:"SCRIPT ERROR" /C:"Parse Error" "%OUT%\game.log"
echo.
echo Done. Log: %OUT%\game.log
pause
exit /b 0

:no_godot
echo Cannot find Godot under %USERPROFILE%\Godot_v4.7.2-stable_mono_win64
pause
exit /b 1

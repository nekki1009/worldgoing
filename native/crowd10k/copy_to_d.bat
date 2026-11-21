@echo off
rem Make a separate test copy of the worldgoing project on D: for the crowd10k P2 integration.
rem The original project in Dropbox is not modified. Double-click to run (takes a few minutes).
rem
rem Copied: everything the Godot project needs to open and run (project.godot, scenes, scripts, assets,
rem addons, native, .godot import cache, tools, export presets ...).
rem Left out: .git, lfs, art_source, output, reports, tmp, scratch, Claude outputs, Godot temp /
rem capture folders. The copy is renamed to "worldgoing_crowd10k_test" in project.godot so its
rem user:// data (settings, saves) is separate from the original game.
rem
rem Note: the source path contains "(" and ")", so this file never expands it inside a ( ... ) block.
setlocal
set "DEST=D:\worldgoing_crowd10k"
set "HERE=%~dp0"
pushd "%~dp0..\.."
set "SRC=%CD%"
popd

echo Source: "%SRC%"
echo Target: "%DEST%"
echo.
if not exist "%SRC%\project.godot" goto no_source
if exist "%DEST%\project.godot" goto exists

robocopy "%SRC%" "%DEST%" /E /R:1 /W:1 /MT:16 /NFL /NDL /NP /XD "%SRC%\.git" "%SRC%\lfs" "%SRC%\art_source" "%SRC%\output" "%SRC%\reports" "%SRC%\tmp" "%SRC%\scratch" "%SRC%\Claude outputs" "%SRC%\.godot-temp" "%SRC%\.godot-temp-archive" "%SRC%\.godot_tmp" "%SRC%\.visual_captures" "%SRC%\.benchmarks" "%SRC%\.codex-remote-attachments" "%SRC%\NVIDIA Corporation" "%SRC%\.godot-user-cache" "%SRC%\native\crowd10k\out" /LOG:"%TEMP%\worldgoing_crowd10k_copy.log" /TEE
rem robocopy: 0-7 = success, 8 or more = failure
if errorlevel 8 goto copy_failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%copy_to_d_rename.ps1" -Project "%DEST%\project.godot"
if errorlevel 1 goto rename_failed

copy /y "%TEMP%\worldgoing_crowd10k_copy.log" "%DEST%\COPY_LOG.txt" >nul
echo Test copy for the crowd10k P2 integration. Project renamed to worldgoing_crowd10k_test so user:// data is separate. Not a git checkout.> "%DEST%\CROWD10K_TEST_COPY.txt"
echo.
echo Done: %DEST%
pause
exit /b 0

:no_source
echo Cannot find project.godot in the source folder shown above.
goto fail
:exists
echo %DEST% already exists. It is not overwritten, so work done in the copy is kept.
echo Delete or rename that folder first if you want a fresh copy.
goto fail
:copy_failed
echo robocopy reported a failure. The log is %TEMP%\worldgoing_crowd10k_copy.log
goto fail
:rename_failed
echo Could not rename the project in %DEST%\project.godot
goto fail
:fail
echo.
echo *** copy did not finish - please send the text above ***
pause
exit /b 1

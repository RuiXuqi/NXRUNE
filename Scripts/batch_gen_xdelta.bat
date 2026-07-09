@echo off
setlocal enabledelayedexpansion

set "scriptDir=%~dp0"
set "outputDir=%scriptDir%xdelta"

if "%~1"=="" (
    set /p gamePath=Please enter DELTARUNE's install path: 
) else (
    set "gamePath=%~1"
)

if not exist "%gamePath%" (
    echo [ERROR] Path "%gamePath%" does not exist.
    pause
    exit /b 1
)

if not exist "%scriptDir%xdelta3.exe" (
    echo [ERROR] xdelta3.exe not found.
    pause
    exit /b 1
)

if not exist "%outputDir%" mkdir "%outputDir%"

call :GeneratePatch "Chapter Select" "." "chapter_select.xdelta"
call :GeneratePatch "Chapter 1" "chapter1_windows" "chapter1.xdelta"
call :GeneratePatch "Chapter 2" "chapter2_windows" "chapter2.xdelta"
call :GeneratePatch "Chapter 3" "chapter3_windows" "chapter3.xdelta"
call :GeneratePatch "Chapter 4" "chapter4_windows" "chapter4.xdelta"
call :GeneratePatch "Chapter 5" "chapter5_windows" "chapter5.xdelta"

setlocal disabledelayedexpansion
echo All done! :3
pause
exit /b 0

:GeneratePatch
set "name=%~1"
set "subFolder=%~2"
set "patchFile=%~3"

if "%subFolder%"=="." (
    set "targetDir=%gamePath%"
    set "backupDir=%gamePath%\backup\nxrune"
) else (
    set "targetDir=%gamePath%\%subFolder%"
    set "backupDir=%gamePath%\backup\nxrune\%subFolder%"
)

echo Generating %name%...

if not exist "!backupDir!\data.win" (
    echo Failed to generate %name%
    goto :eof
)

if not exist "!targetDir!\data.win" (
    echo Failed to generate %name%
    goto :eof
)

"%scriptDir%xdelta3.exe" -e -f -s "!backupDir!\data.win" "!targetDir!\data.win" "%outputDir%\%patchFile%"

if errorlevel 1 (
    echo Failed to generate %name%
)
goto :eof

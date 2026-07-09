@echo off
setlocal enabledelayedexpansion

set "scriptDir=%~dp0"
set "xdeltaExe=%scriptDir%xdelta.exe"
if not exist "%xdeltaExe%" set "xdeltaExe=%scriptDir%xdelta3.exe"
set "patchDir=%scriptDir%xdelta"
set "rollbackDir=%scriptDir%.nxrune_rollback_%RANDOM%%RANDOM%"
set "preparedFile=%rollbackDir%\prepared.txt"
set "existingBackupFile=%rollbackDir%\backup_existing.txt"
set "newBackupFile=%rollbackDir%\backup_new.txt"

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

if not exist "%xdeltaExe%" (
    echo [ERROR] xdelta executable not found.
    pause
    exit /b 1
)

if not exist "%patchDir%" (
    echo [ERROR] xdelta folder not found.
    pause
    exit /b 1
)

set "backupRoot=%gamePath%\backup\nxrune"

mkdir "%rollbackDir%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Could not create rollback directory "%rollbackDir%".
    pause
    exit /b 1
)

call :PreparePatch "Chapter Select" "." "chapter_select.xdelta"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 1" "chapter1_windows" "chapter1.xdelta"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 2" "chapter2_windows" "chapter2.xdelta"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 3" "chapter3_windows" "chapter3.xdelta"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 4" "chapter4_windows" "chapter4.xdelta"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 5" "chapter5_windows" "chapter5.xdelta"
if errorlevel 1 goto RollbackFailure

set "commitFailed=0"
for %%C in ("Chapter Select|." "Chapter 1|chapter1_windows" "Chapter 2|chapter2_windows" "Chapter 3|chapter3_windows" "Chapter 4|chapter4_windows" "Chapter 5|chapter5_windows") do (
    for /f "tokens=1,2 delims=|" %%A in ("%%~C") do (
        set "name=%%A"
        set "subFolder=%%B"
        if "!subFolder!"=="." (
            set "targetDir=%gamePath%"
        ) else (
            set "targetDir=%gamePath%\!subFolder!"
        )
        set "sourceFile=!targetDir!\data.win"
        set "patchedFile=!targetDir!\data_patched.win"
        move /Y "!patchedFile!" "!sourceFile!" >nul
        if errorlevel 1 (
            echo Failed to patch !name!
            set "commitFailed=1"
        )
    )
)
if "!commitFailed!"=="1" goto RollbackFailure

goto Success

:Success
setlocal disabledelayedexpansion
echo All done! :3
endlocal
rd /S /Q "%rollbackDir%" >nul 2>nul
pause >nul
exit /b 0

:PreparePatch
set "name=%~1"
set "subFolder=%~2"
set "deltaFile=%~3"
call :SetPaths "%subFolder%"

echo Patching %name%...

if not exist "%patchDir%\%deltaFile%" (
    echo Failed to patch %name%: "/xdelta/%deltaFile%" not found
    exit /b 1
)

if not exist "%sourceFile%" (
    echo Failed to patch %name%
    exit /b 1
)

if exist "%backupFile%" (
    mkdir "%stateDir%" >nul 2>nul
    copy /Y "%backupFile%" "%stateDir%\data.win" >nul
    if errorlevel 1 (
        echo Failed to patch %name%
        exit /b 1
    )
    echo %subFolder%>> "%existingBackupFile%"
) else (
    echo %subFolder%>> "%newBackupFile%"
)

mkdir "%backupDir%" >nul 2>nul
copy /Y "%sourceFile%" "%backupFile%" >nul
if errorlevel 1 (
    echo Failed to patch %name%
    exit /b 1
)

if exist "%patchedFile%" del "%patchedFile%"

"%xdeltaExe%" -d -f -s "%sourceFile%" "%patchDir%\%deltaFile%" "%patchedFile%"
if errorlevel 1 (
    echo Failed to patch %name%
    if exist "%patchedFile%" del "%patchedFile%"
    exit /b 1
)

if not exist "%patchedFile%" (
    echo Failed to patch %name%
    exit /b 1
)

echo %subFolder%>> "%preparedFile%"
echo Patched %name%
exit /b 0

:RollbackFailure
call :Rollback
pause
exit /b 1

:Rollback
echo Rolling back...

if exist "%preparedFile%" (
    for /f "usebackq delims=" %%S in ("%preparedFile%") do call :RestoreData "%%S"
)

if exist "%existingBackupFile%" (
    for /f "usebackq delims=" %%S in ("%existingBackupFile%") do call :RestoreExistingBackup "%%S"
)

if exist "%newBackupFile%" (
    for /f "usebackq delims=" %%S in ("%newBackupFile%") do call :RemoveNewBackup "%%S"
)

for /f "delims=" %%D in ('dir /ad /b /s "%backupRoot%" 2^>nul ^| sort /R') do rd "%%D" 2>nul
rd "%backupRoot%" 2>nul
rd "%gamePath%\backup" 2>nul
rd /S /Q "%rollbackDir%" >nul 2>nul
exit /b 0

:RestoreData
set "subFolder=%~1"
call :SetPaths "%subFolder%"
if exist "%backupFile%" copy /Y "%backupFile%" "%sourceFile%" >nul
if exist "%patchedFile%" del "%patchedFile%"
exit /b 0

:RestoreExistingBackup
set "subFolder=%~1"
call :SetPaths "%subFolder%"
mkdir "%backupDir%" >nul 2>nul
copy /Y "%stateDir%\data.win" "%backupFile%" >nul
exit /b 0

:RemoveNewBackup
set "subFolder=%~1"
call :SetPaths "%subFolder%"
if exist "%backupFile%" del "%backupFile%"
exit /b 0

:SetPaths
set "subFolder=%~1"
if "%subFolder%"=="." (
    set "targetDir=%gamePath%"
    set "backupDir=%backupRoot%"
    set "stateDir=%rollbackDir%\backup"
) else (
    set "targetDir=%gamePath%\%subFolder%"
    set "backupDir=%backupRoot%\%subFolder%"
    set "stateDir=%rollbackDir%\backup\%subFolder%"
)
set "sourceFile=%targetDir%\data.win"
set "backupFile=%backupDir%\data.win"
set "patchedFile=%targetDir%\data_patched.win"
exit /b 0

@echo off
setlocal enabledelayedexpansion

set "scriptDir=%~dp0"
set "csxDir=%scriptDir%csx"
set "utmtCli=%scriptDir%utmt\UndertaleModCli.exe"
set "runLog=%scriptDir%nxrune_patch.log"
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

if not exist "%utmtCli%" (
    echo [ERROR] UTMT CLI "%utmtCli%" does not exist.
    pause
    exit /b 1
)

if not exist "%csxDir%\NXRUNE.csx" (
    echo [ERROR] CSX scripts folder "%csxDir%" is incomplete.
    pause
    exit /b 1
)

set "backupRoot=%gamePath%\backup\nxrune"

if exist "%runLog%" del "%runLog%"
mkdir "%rollbackDir%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Could not create rollback directory "%rollbackDir%".
    pause
    exit /b 1
)

echo Target: "%gamePath%" > "%runLog%"
echo. >> "%runLog%"

call :PreparePatch "Chapter Select" "." "NXRUNE.csx"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 1" "chapter1_windows" "NXRUNE_CH1.csx"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 2" "chapter2_windows" "NXRUNE_CH2.csx"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 3" "chapter3_windows" "NXRUNE_CH3.csx"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 4" "chapter4_windows" "NXRUNE_CH4.csx"
if errorlevel 1 goto RollbackFailure
call :PreparePatch "Chapter 5" "chapter5_windows" "NXRUNE_CH5.csx"
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
            call :Log "Failed to patch !name!."
            call :Log "[ERROR] Could not replace !sourceFile!."
            set "commitFailed=1"
        )
    )
)
if "!commitFailed!"=="1" goto RollbackFailure

goto Success

:PreparePatch
set "name=%~1"
set "subFolder=%~2"
set "scriptFile=%~3"
call :SetPaths "%subFolder%"

call :Log "Patching %name%..."

if not exist "%sourceFile%" (
    call :Log "Failed to patch %name%."
    call :Log "[ERROR] Source file !sourceFile! not found."
    exit /b 1
)

if not exist "%csxDir%\%scriptFile%" (
    set "logMessage=Failed to patch %name%: "/csx/%scriptFile%" not found"
    call :LogVar
    exit /b 1
)

if exist "%backupFile%" (
    mkdir "%stateDir%" >nul 2>nul
    copy /Y "%backupFile%" "%stateDir%\data.win" >nul
    if errorlevel 1 (
        call :Log "Failed to patch %name%."
        call :Log "[ERROR] Could not preserve existing backup !backupFile!."
        exit /b 1
    )
    echo %subFolder%>> "%existingBackupFile%"
) else (
    echo %subFolder%>> "%newBackupFile%"
)

mkdir "%backupDir%" >nul 2>nul
copy /Y "%sourceFile%" "%backupFile%" >nul
if errorlevel 1 (
    call :Log "Failed to patch %name%."
    call :Log "[ERROR] Could not create backup !backupFile!."
    exit /b 1
)

if exist "%patchedFile%" del "%patchedFile%"

set "UTMT_CLI=%utmtCli%"
set "SOURCE_FILE=%sourceFile%"
set "SCRIPT_FILE=%csxDir%\%scriptFile%"
set "PATCHED_FILE=%patchedFile%"
set "RUN_LOG=%runLog%"
set "STATUS_LINE=Patching %name%..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "$enc=[System.Text.UTF8Encoding]::new($false); $ui= -not [Console]::IsOutputRedirected; $window=New-Object 'System.Collections.Generic.List[string]'; $max=8; $rendered=0; function Width { try { [Math]::Max(20,[Console]::WindowWidth) } catch { 100 } }; function Clip([string]$s) { $limit=(Width)-3; if ($s.Length -gt $limit) { $s.Substring(0,[Math]::Max(0,$limit-3)) + '...' } else { $s } }; function ClearLines([int]$extra) { if ($ui -and ($rendered + $extra) -gt 0) { [Console]::Write([char]27 + '[' + ($rendered + $extra) + 'A' + [char]27 + '[J') }; $script:rendered=0 }; function Render { if (-not $ui) { return }; ClearLines 0; foreach ($line in $window) { [Console]::Out.WriteLine('  ' + (Clip $line)) }; $script:rendered=$window.Count }; & $env:UTMT_CLI load $env:SOURCE_FILE -s $env:SCRIPT_FILE -o $env:PATCHED_FILE 2>&1 | ForEach-Object { $line=$_.ToString(); [System.IO.File]::AppendAllText($env:RUN_LOG,$line+[Environment]::NewLine,$enc); if ($ui) { [void]$window.Add($line); while ($window.Count -gt $max) { $window.RemoveAt(0) }; Render } else { [Console]::Out.WriteLine($line) } }; $code=$LASTEXITCODE; if ($ui) { ClearLines 1 }; exit $code"

if errorlevel 1 (
    call :Log "Failed to patch %name%."
    if exist "%patchedFile%" del "%patchedFile%"
    exit /b 1
)

if not exist "%patchedFile%" (
    call :Log "Failed to patch %name%."
    call :Log "[ERROR] UTMT CLI did not produce !patchedFile!."
    exit /b 1
)

echo %subFolder%>> "%preparedFile%"
call :Log "Patched %name%"
exit /b 0

:RollbackFailure
call :Rollback
pause
exit /b 1

:Success
setlocal disabledelayedexpansion
>> "%runLog%" echo All done^! :3
echo All done^! :3
endlocal
rd /S /Q "%rollbackDir%" >nul 2>nul
pause >nul
exit /b 0

:Rollback
call :Log "Rolling back..."

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

:Log
echo %~1
>> "%runLog%" echo %~1
exit /b 0

:LogVar
echo !logMessage!
>> "%runLog%" echo !logMessage!
exit /b 0

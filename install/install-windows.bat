@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "CLASH_DIR=%APPDATA%\io.github.clash-verge-rev.clash-verge-rev"
set "SCRIPT_DIR=%~dp0"
set "CONFIG_DIR=%SCRIPT_DIR%..\config"
set "PACKAGE_VERSION=dev"
set "VERSION_FILE=%SCRIPT_DIR%VERSION.txt"
if not exist "%VERSION_FILE%" set "VERSION_FILE=%SCRIPT_DIR%..\VERSION.txt"
if exist "%VERSION_FILE%" for /f "usebackq delims=" %%V in ("%VERSION_FILE%") do set "PACKAGE_VERSION=%%V"

if not exist "%CONFIG_DIR%\Merge.yaml" set "CONFIG_DIR=%SCRIPT_DIR%"

echo Package version: %PACKAGE_VERSION%
echo Package path: %SCRIPT_DIR%

if not exist "%CONFIG_DIR%\Merge.yaml" (
    echo ERROR: Config files not found. Use the official Release zip and keep all files together.
    pause
    exit /b 1
)

if not exist "%CLASH_DIR%" (
    echo ERROR: Clash Verge Rev data folder was not found.
    echo Install Clash Verge Rev, import your own subscription, run it once, then close it.
    pause
    exit /b 1
)

for %%P in ("clash-verge.exe" "Clash Verge Rev.exe" "verge-mihomo.exe" "verge-mihomo-alpha.exe" "mihomo.exe") do (
    tasklist /FI "IMAGENAME eq %%~P" 2>nul | find /I "%%~P" >nul
    if !ERRORLEVEL! EQU 0 (
        echo ERROR: Clash Verge Rev or mihomo is still running. Close it first.
        pause
        exit /b 1
    )
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
if not defined TS set "TS=unknown"
set BACKUP_RETRY=0
:make_backup_dir
set /a BACKUP_RETRY+=1 >nul
set "BACKUP_DIR=%CLASH_DIR%\backup_%TS%_%RANDOM%%RANDOM%"
mkdir "%BACKUP_DIR%" 2>nul
if errorlevel 1 (
    if !BACKUP_RETRY! LSS 10 goto make_backup_dir
    echo ERROR: Could not create backup folder: %BACKUP_DIR%
    pause
    exit /b 1
)

echo Backup folder:
echo   %BACKUP_DIR%
if exist "%CLASH_DIR%\profiles\Merge.yaml" (
    call :copy_required "%CLASH_DIR%\profiles\Merge.yaml" "%BACKUP_DIR%\Merge.yaml" "backup"
    if errorlevel 1 goto install_failed
)
if exist "%CLASH_DIR%\profiles\Script.js" (
    call :copy_required "%CLASH_DIR%\profiles\Script.js" "%BACKUP_DIR%\Script.js" "backup"
    if errorlevel 1 goto install_failed
)
if exist "%CLASH_DIR%\verge.yaml" (
    call :copy_required "%CLASH_DIR%\verge.yaml" "%BACKUP_DIR%\verge.yaml" "backup"
    if errorlevel 1 goto install_failed
)
if exist "%CLASH_DIR%\dns_config.yaml" (
    call :copy_required "%CLASH_DIR%\dns_config.yaml" "%BACKUP_DIR%\dns_config.yaml" "backup"
    if errorlevel 1 goto install_failed
)

echo Installing...
call :copy_required "%CONFIG_DIR%\Merge.yaml" "%CLASH_DIR%\profiles\Merge.yaml" "install"
if errorlevel 1 goto install_failed
call :copy_required "%CONFIG_DIR%\Script.js" "%CLASH_DIR%\profiles\Script.js" "install"
if errorlevel 1 goto install_failed

set "SYNC_SCRIPT=%SCRIPT_DIR%sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" set "SYNC_SCRIPT=%SCRIPT_DIR%..\install\sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" (
    echo ERROR: sync-profile-bound-files.ps1 was not found.
    pause
    exit /b 1
)
if not defined BACKUP_DIR (
    echo ERROR: Backup folder variable is empty.
    pause
    exit /b 1
)
if not exist "%BACKUP_DIR%\." (
    echo ERROR: Backup folder does not exist: %BACKUP_DIR%
    pause
    exit /b 1
)
where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    pause
    exit /b 1
)
set "SYNC_CLASH_DIR=%CLASH_DIR%"
set "SYNC_CONFIG_DIR=%CONFIG_DIR%"
set "SYNC_BACKUP_DIR=%BACKUP_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%"
if errorlevel 1 (
    echo ERROR: Failed to sync profile-bound merge/script files.
    pause
    exit /b 1
)
set "SYNC_CLASH_DIR="
set "SYNC_CONFIG_DIR="
set "SYNC_BACKUP_DIR="

call :copy_required "%CONFIG_DIR%\verge.yaml" "%CLASH_DIR%\verge.yaml" "install"
if errorlevel 1 goto install_failed
call :copy_required "%CONFIG_DIR%\dns_config.yaml" "%CLASH_DIR%\dns_config.yaml" "install"
if errorlevel 1 goto install_failed
set CLEANUP_COUNT=0
for /f "skip=5 delims=" %%B in ('dir /b /ad /o-n "%CLASH_DIR%\backup_*" 2^>nul') do (
    rmdir /s /q "%CLASH_DIR%\%%B" 2>nul
    set /a CLEANUP_COUNT+=1 >nul
)
if !CLEANUP_COUNT! GTR 0 echo Old backups cleaned. Keeping latest 5 backup folders.

echo.
echo [OK] Installed.
echo Subscription and nodes were not changed.
echo Backup:
echo   %BACKUP_DIR%
echo Next: reopen Clash Verge Rev and check groups:
echo   Claude / AI / US / Google / YouTube / Exchange
echo For restore steps or the 60-second checklist, read README.txt.
pause
exit /b 0

:install_failed
echo ERROR: Install did not finish. Check the message above.
pause
exit /b 1

:copy_required
copy /Y "%~1" "%~2" >nul
if errorlevel 1 (
    echo ERROR: %~3 failed: "%~1" to "%~2"
    exit /b 1
)
exit /b 0

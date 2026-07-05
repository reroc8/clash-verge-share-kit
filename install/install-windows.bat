@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "CLASH_DIR=%APPDATA%\io.github.clash-verge-rev.clash-verge-rev"
set "SCRIPT_DIR=%~dp0"
set "CONFIG_DIR=%SCRIPT_DIR%..\config"
set "PACKAGE_VERSION=dev"
set "CREATED_FILES_LIST="
set "INSTALL_STARTED=0"
set "INSTALL_COMPLETED=0"
set "VERSION_FILE=%SCRIPT_DIR%VERSION.txt"
if not exist "%VERSION_FILE%" set "VERSION_FILE=%SCRIPT_DIR%..\VERSION.txt"
if exist "%VERSION_FILE%" for /f "usebackq delims=" %%V in ("%VERSION_FILE%") do set "PACKAGE_VERSION=%%V"

if not exist "%CONFIG_DIR%\Merge.yaml" set "CONFIG_DIR=%SCRIPT_DIR%"

echo 安装包版本: %PACKAGE_VERSION%
echo 安装来源: %SCRIPT_DIR%

if not exist "%CONFIG_DIR%\Merge.yaml" (
    echo 错误: 找不到配置文件。请使用正式压缩包，并保持所有文件在同一文件夹。
    echo.
    echo 请按任意键关闭窗口...
    pause >nul
    exit /b 1
)

if not exist "%CLASH_DIR%" (
    echo 错误: 未找到 Clash Verge Rev 数据目录。
    echo 请先安装 Clash Verge Rev，导入自己的订阅，运行一次，然后完全退出。
    echo.
    echo 请按任意键关闭窗口...
    pause >nul
    exit /b 1
)

for %%P in ("clash-verge.exe" "Clash Verge Rev.exe" "verge-mihomo.exe" "verge-mihomo-alpha.exe" "mihomo.exe") do (
    tasklist /FI "IMAGENAME eq %%~P" 2>nul | find /I "%%~P" >nul
    if !ERRORLEVEL! EQU 0 (
        echo 错误: 检测到 Clash Verge Rev 或内核仍在运行。请先完全退出。
        echo.
        echo 请按任意键关闭窗口...
        pause >nul
        exit /b 1
    )
)

where powershell >nul 2>nul
if errorlevel 1 (
    echo 错误: 未找到 Windows PowerShell。Windows 10/11 一般自带，请确认系统未被精简。
    echo.
    echo 请按任意键关闭窗口...
    pause >nul
    exit /b 1
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
    echo 错误: 无法创建备份目录:
    echo   %BACKUP_DIR%
    echo.
    echo 请按任意键关闭窗口...
    pause >nul
    exit /b 1
)

echo 安装前已备份到:
echo   %BACKUP_DIR%
set "CREATED_FILES_LIST=%BACKUP_DIR%\.created-files"
break > "%CREATED_FILES_LIST%"
call :backup_existing_file "%CLASH_DIR%\profiles\Merge.yaml" "Merge.yaml"
if errorlevel 1 goto install_failed
call :backup_existing_file "%CLASH_DIR%\profiles\Script.js" "Script.js"
if errorlevel 1 goto install_failed
call :backup_existing_file "%CLASH_DIR%\verge.yaml" "verge.yaml"
if errorlevel 1 goto install_failed
call :backup_existing_file "%CLASH_DIR%\dns_config.yaml" "dns_config.yaml"
if errorlevel 1 goto install_failed

echo 正在安装...
set "INSTALL_STARTED=1"
call :copy_required "%CONFIG_DIR%\Merge.yaml" "%CLASH_DIR%\profiles\Merge.yaml" "install"
if errorlevel 1 goto install_failed
call :copy_required "%CONFIG_DIR%\Script.js" "%CLASH_DIR%\profiles\Script.js" "install"
if errorlevel 1 goto install_failed

set "SYNC_SCRIPT=%SCRIPT_DIR%sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" set "SYNC_SCRIPT=%SCRIPT_DIR%..\install\sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" (
    echo 错误: 缺少同步脚本 sync-profile-bound-files.ps1。请重新解压完整安装包。
    goto install_failed
)
if not defined BACKUP_DIR (
    echo 错误: 备份目录为空，已停止安装。
    goto install_failed
)
if not exist "%BACKUP_DIR%\." (
    echo 错误: 备份目录不存在:
    echo   %BACKUP_DIR%
    goto install_failed
)
set "SYNC_CLASH_DIR=%CLASH_DIR%"
set "SYNC_CONFIG_DIR=%CONFIG_DIR%"
set "SYNC_BACKUP_DIR=%BACKUP_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%"
if errorlevel 1 (
    echo 错误: 同步已有订阅绑定的配置文件失败。
    goto install_failed
)
set "SYNC_CLASH_DIR="
set "SYNC_CONFIG_DIR="
set "SYNC_BACKUP_DIR="

call :copy_required "%CONFIG_DIR%\verge.yaml" "%CLASH_DIR%\verge.yaml" "install"
if errorlevel 1 goto install_failed
call :copy_required "%CONFIG_DIR%\dns_config.yaml" "%CLASH_DIR%\dns_config.yaml" "install"
if errorlevel 1 goto install_failed
set "INSTALL_COMPLETED=1"
set CLEANUP_COUNT=0
for /f "skip=5 delims=" %%B in ('dir /b /ad /o-n "%CLASH_DIR%\backup_*" 2^>nul') do (
    rmdir /s /q "%CLASH_DIR%\%%B" 2>nul
    set /a CLEANUP_COUNT+=1 >nul
)
if !CLEANUP_COUNT! GTR 0 echo 已清理旧备份，仅保留最近 5 个 backup_* 目录。

echo.
echo 安装完成。
echo 你的订阅和节点没有被修改。
echo 备份位置:
echo   %BACKUP_DIR%
echo 下一步:
echo   1. 重新打开 Clash Verge Rev。
echo   2. 在代理页确认能看到这些分组:
echo   Claude / AI / US / Google / YouTube / Exchange
echo   3. 按 README.txt 的“安装后 60 秒检查清单”测试。
echo 如果某类网站异常，先切换对应策略组节点。
echo.
echo 请按任意键关闭窗口...
pause >nul
exit /b 0

:install_failed
call :restore_from_backup
echo 错误: 安装未完成。请查看上面的提示。
echo.
echo 请按任意键关闭窗口...
pause >nul
exit /b 1

:backup_existing_file
if exist "%~1" (
    if not exist "%BACKUP_DIR%\%~2" (
        copy /Y "%~1" "%BACKUP_DIR%\%~2" >nul
        if errorlevel 1 (
            echo 错误: 备份失败: "%~1" -^> "%BACKUP_DIR%\%~2"
            exit /b 1
        )
    )
) else (
    if defined CREATED_FILES_LIST (
        set "CREATED_PATH=%~1"
        >>"%CREATED_FILES_LIST%" echo(!CREATED_PATH!
    )
)
exit /b 0

:restore_from_backup
if not "%INSTALL_STARTED%"=="1" exit /b 0
if "%INSTALL_COMPLETED%"=="1" exit /b 0
if not defined BACKUP_DIR exit /b 0
if not exist "%BACKUP_DIR%\." exit /b 0
echo 正在尝试从备份恢复安装前配置...
if defined CREATED_FILES_LIST if exist "%CREATED_FILES_LIST%" (
    for /f "usebackq delims=" %%C in ("%CREATED_FILES_LIST%") do (
        if exist "%%C" del /f /q "%%C" >nul 2>nul
    )
)
for /f "delims=" %%F in ('dir /b /a-d "%BACKUP_DIR%" 2^>nul') do (
    if /I not "%%F"==".created-files" (
        if /I "%%F"=="verge.yaml" (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\%%F" >nul 2>nul
            if errorlevel 1 echo 警告: 恢复失败: "%CLASH_DIR%\%%F"
        ) else if /I "%%F"=="dns_config.yaml" (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\%%F" >nul 2>nul
            if errorlevel 1 echo 警告: 恢复失败: "%CLASH_DIR%\%%F"
        ) else (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\profiles\%%F" >nul 2>nul
            if errorlevel 1 echo 警告: 恢复失败: "%CLASH_DIR%\profiles\%%F"
        )
    )
)
echo 已尝试恢复。备份目录:
echo   %BACKUP_DIR%
exit /b 0

:copy_required
copy /Y "%~1" "%~2" >nul
if errorlevel 1 (
    echo 错误: 复制失败: "%~1" -^> "%~2"
    exit /b 1
)
exit /b 0

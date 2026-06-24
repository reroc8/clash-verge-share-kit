@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "CLASH_DIR=%APPDATA%\io.github.clash-verge-rev.clash-verge-rev"
set "SCRIPT_DIR=%~dp0"
set "CONFIG_DIR=%SCRIPT_DIR%..\config"

if not exist "%CONFIG_DIR%\Merge.yaml" set "CONFIG_DIR=%SCRIPT_DIR%"

if not exist "%CONFIG_DIR%\Merge.yaml" (
    echo 错误: 未找到配置文件。请确认 config 目录存在，或使用 Release zip 根目录运行。
    pause
    exit /b 1
)

if not exist "%CLASH_DIR%" (
    echo 错误: 未找到 Clash Verge Rev 数据目录
    echo 请先安装 Clash Verge Rev，导入自己的订阅，并运行一次
    pause
    exit /b 1
)

for %%P in ("Clash Verge.exe" "clash-verge.exe" "verge-mihomo.exe" "mihomo.exe") do (
    tasklist /FI "IMAGENAME eq %%~P" 2>nul | find /I "%%~P" >nul
    if !ERRORLEVEL! EQU 0 (
        echo 错误: 检测到 Clash Verge Rev 或内核正在运行，请先完全退出
        pause
        exit /b 1
    )
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
set "BACKUP_DIR=%CLASH_DIR%\backup_%TS%"
mkdir "%BACKUP_DIR%" 2>nul

echo 安装前备份到: %BACKUP_DIR%
if exist "%CLASH_DIR%\profiles\Merge.yaml"   copy "%CLASH_DIR%\profiles\Merge.yaml"   "%BACKUP_DIR%\Merge.yaml" >nul
if exist "%CLASH_DIR%\profiles\Script.js"    copy "%CLASH_DIR%\profiles\Script.js"    "%BACKUP_DIR%\Script.js" >nul
if exist "%CLASH_DIR%\verge.yaml"            copy "%CLASH_DIR%\verge.yaml"            "%BACKUP_DIR%\verge.yaml" >nul
if exist "%CLASH_DIR%\dns_config.yaml"       copy "%CLASH_DIR%\dns_config.yaml"       "%BACKUP_DIR%\dns_config.yaml" >nul

echo 正在安装...
copy /Y "%CONFIG_DIR%\Merge.yaml"       "%CLASH_DIR%\profiles\Merge.yaml" >nul
copy /Y "%CONFIG_DIR%\Script.js"        "%CLASH_DIR%\profiles\Script.js" >nul
copy /Y "%CONFIG_DIR%\verge.yaml"       "%CLASH_DIR%\verge.yaml" >nul
copy /Y "%CONFIG_DIR%\dns_config.yaml"  "%CLASH_DIR%\dns_config.yaml" >nul

echo.
echo 安装完成。你的订阅和节点数据未被修改。
echo 原文件已备份到: %BACKUP_DIR%
echo 请重新打开 Clash Verge Rev
echo 脚本会自动补齐常见策略组。打开后可按需选择: US / Google / YouTube / Exchange
pause

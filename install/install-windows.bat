@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "CLASH_DIR=%APPDATA%\io.github.clash-verge-rev.clash-verge-rev"
set "SCRIPT_DIR=%~dp0"
set "CONFIG_DIR=%SCRIPT_DIR%..\config"
set "PACKAGE_VERSION=dev"
set "VERSION_FILE=%SCRIPT_DIR%VERSION.txt"
if not exist "%VERSION_FILE%" set "VERSION_FILE=%SCRIPT_DIR%..\VERSION.txt"
if exist "%VERSION_FILE%" set /p PACKAGE_VERSION=<"%VERSION_FILE%"

if not exist "%CONFIG_DIR%\Merge.yaml" set "CONFIG_DIR=%SCRIPT_DIR%"

echo 安装包版本: %PACKAGE_VERSION%
echo 安装来源: %SCRIPT_DIR%

if not exist "%CONFIG_DIR%\Merge.yaml" (
    echo 错误: 未找到配置文件。请确认 config/ 目录存在，或使用 Release zip 根目录运行。
    pause
    exit /b 1
)

if not exist "%CLASH_DIR%" (
    echo 错误: 未找到 Clash Verge Rev 数据目录
    echo 请先安装 Clash Verge Rev，导入自己的订阅，并运行一次
    pause
    exit /b 1
)

for %%P in ("clash-verge.exe" "Clash Verge Rev.exe" "verge-mihomo.exe" "verge-mihomo-alpha.exe" "mihomo.exe") do (
    tasklist /FI "IMAGENAME eq %%~P" 2>nul | find /I "%%~P" >nul
    if !ERRORLEVEL! EQU 0 (
        echo 错误: 检测到 Clash Verge Rev 或内核正在运行，请先完全退出
        pause
        exit /b 1
    )
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
set BACKUP_RETRY=0
:make_backup_dir
set /a BACKUP_RETRY+=1 >nul
set "BACKUP_DIR=%CLASH_DIR%\backup_%TS%_%RANDOM%%RANDOM%"
mkdir "%BACKUP_DIR%" 2>nul
if errorlevel 1 (
    if !BACKUP_RETRY! LSS 10 goto make_backup_dir
    echo 错误: 无法创建备份目录: %BACKUP_DIR%
    pause
    exit /b 1
)

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

set CLEANUP_COUNT=0
for /f "skip=5 delims=" %%B in ('dir /b /ad /o-n "%CLASH_DIR%\backup_*" 2^>nul') do (
    rmdir /s /q "%CLASH_DIR%\%%B" 2>nul
    set /a CLEANUP_COUNT+=1 >nul
)
if !CLEANUP_COUNT! GTR 0 echo 已清理旧备份，仅保留最近 5 个 backup_* 目录

echo.
echo 安装完成。你的订阅和节点数据未被修改。
echo 原文件已备份到: %BACKUP_DIR%
echo 如需还原: 完全退出 Clash Verge Rev 后，把备份目录里的文件复制回对应位置
echo   Merge.yaml / Script.js -^> %CLASH_DIR%\profiles\
echo   verge.yaml / dns_config.yaml -^> %CLASH_DIR%\
echo 配置文件已写入；重新打开 Clash Verge Rev 后即生效
echo 安装后确认: 代理页能看到 US / Google / YouTube / Exchange
echo 如果某类网站异常，先换对应策略组节点；如果规则集下载失败，请查看 Clash Verge Rev 日志
echo 也可以按 README.txt 的“安装后 60 秒检查清单”逐项测试
pause

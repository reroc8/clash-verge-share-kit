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

where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

call :say 5a6J6KOF5YyF54mI5pysOg==
echo   %PACKAGE_VERSION%
call :say 5a6J6KOF5p2l5rqQOg==
echo   %SCRIPT_DIR%

if not exist "%CONFIG_DIR%\Merge.yaml" (
    call :say 6ZSZ6K+vOiDmib7kuI3liLDphY3nva7mlofku7bjgILor7fkvb/nlKjmraPlvI/ljovnvKnljIXvvIzlubbkv53mjIHmiYDmnInmlofku7blnKjlkIzkuIDmlofku7blpLnjgII=
    echo.
    call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
    pause >nul
    exit /b 1
)

if not exist "%CLASH_DIR%" (
    call :say 6ZSZ6K+vOiDmnKrmib7liLAgQ2xhc2ggVmVyZ2UgUmV2IOaVsOaNruebruW9leOAgg==
    call :say 6K+35YWI5a6J6KOFIENsYXNoIFZlcmdlIFJldu+8jOWvvOWFpeiHquW3seeahOiuoumYhe+8jOi/kOihjOS4gOasoe+8jOeEtuWQjuWujOWFqOmAgOWHuuOAgg==
    echo.
    call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
    pause >nul
    exit /b 1
)

for %%P in ("clash-verge.exe" "Clash Verge Rev.exe" "verge-mihomo.exe" "verge-mihomo-alpha.exe" "mihomo.exe") do (
    tasklist /FI "IMAGENAME eq %%~P" 2>nul | find /I "%%~P" >nul
    if !ERRORLEVEL! EQU 0 (
        call :say 6ZSZ6K+vOiDmo4DmtYvliLAgQ2xhc2ggVmVyZ2UgUmV2IOaIluWGheaguOS7jeWcqOi/kOihjOOAguivt+WFiOWujOWFqOmAgOWHuuOAgg==
        echo.
        call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
        pause >nul
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
    call :say 6ZSZ6K+vOiDml6Dms5XliJvlu7rlpIfku73nm67lvZU6
    echo   %BACKUP_DIR%
    echo.
    call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
    pause >nul
    exit /b 1
)

call :say 5a6J6KOF5YmN5bey5aSH5Lu95YiwOg==
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

call :say 5q2j5Zyo5a6J6KOFLi4u
set "INSTALL_STARTED=1"
call :copy_required "%CONFIG_DIR%\Merge.yaml" "%CLASH_DIR%\profiles\Merge.yaml" "install"
if errorlevel 1 goto install_failed
call :copy_required "%CONFIG_DIR%\Script.js" "%CLASH_DIR%\profiles\Script.js" "install"
if errorlevel 1 goto install_failed

set "SYNC_SCRIPT=%SCRIPT_DIR%sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" set "SYNC_SCRIPT=%SCRIPT_DIR%..\install\sync-profile-bound-files.ps1"
if not exist "%SYNC_SCRIPT%" (
    call :say 6ZSZ6K+vOiDnvLrlsJHlkIzmraXohJrmnKwgc3luYy1wcm9maWxlLWJvdW5kLWZpbGVzLnBzMeOAguivt+mHjeaWsOino+WOi+WujOaVtOWuieijheWMheOAgg==
    goto install_failed
)
if not defined BACKUP_DIR (
    call :say 6ZSZ6K+vOiDlpIfku73nm67lvZXkuLrnqbrvvIzlt7LlgZzmraLlronoo4XjgII=
    goto install_failed
)
if not exist "%BACKUP_DIR%\." (
    call :say 6ZSZ6K+vOiDlpIfku73nm67lvZXkuI3lrZjlnKg6
    echo   %BACKUP_DIR%
    goto install_failed
)
set "SYNC_CLASH_DIR=%CLASH_DIR%"
set "SYNC_CONFIG_DIR=%CONFIG_DIR%"
set "SYNC_BACKUP_DIR=%BACKUP_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%" >nul
if errorlevel 1 (
    call :say 6ZSZ6K+vOiDlkIzmraXlt7LmnInorqLpmIXnu5HlrprnmoTphY3nva7mlofku7blpLHotKXjgII=
    goto install_failed
)
call :say 5bey5ZCM5q2l5bey5pyJ6K6i6ZiF57uR5a6a55qE6YWN572u5paH5Lu244CC
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
if !CLEANUP_COUNT! GTR 0 call :say 5bey5riF55CG5pen5aSH5Lu977yM5LuF5L+d55WZ5pyA6L+RIDUg5LiqIGJhY2t1cF8qIOebruW9leOAgg==

echo.
call :say 5a6J6KOF5a6M5oiQ44CC
call :say 5L2g55qE6K6i6ZiF5ZKM6IqC54K55rKh5pyJ6KKr5L+u5pS544CC
call :say 5aSH5Lu95L2N572uOg==
echo   %BACKUP_DIR%
call :say 5LiL5LiA5q2lOg==
call :say ICAxLiDph43mlrDmiZPlvIAgQ2xhc2ggVmVyZ2UgUmV244CC
call :say ICAyLiDlnKjku6PnkIbpobXnoa7orqTog73nnIvliLDov5nkupvliIbnu4Q6
echo   Claude / AI / Google / YouTube / Telegram / Exchange / US / TW / SG / HK / JP / Proxies
call :say ICAzLiDmjIkgUkVBRE1FLnR4dCDnmoTigJzlronoo4XlkI4gNjAg56eS5qOA5p+l5riF5Y2V4oCd5rWL6K+V44CC
call :say 5aaC5p6c5p+Q57G7572R56uZ5byC5bi477yM5YWI5YiH5o2i5a+55bqU562W55Wl57uE6IqC54K544CC
echo.
call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
pause >nul
exit /b 0

:install_failed
call :restore_from_backup
call :say 6ZSZ6K+vOiDlronoo4XmnKrlrozmiJDjgILor7fmn6XnnIvkuIrpnaLnmoTmj5DnpLrjgII=
echo.
call :say 6K+35oyJ5Lu75oSP6ZSu5YWz6Zet56qX5Y+jLi4u
pause >nul
exit /b 1

:say
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Write-Host ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%~1')))"
exit /b 0

:backup_existing_file
if exist "%~1" (
    if not exist "%BACKUP_DIR%\%~2" (
        copy /Y "%~1" "%BACKUP_DIR%\%~2" >nul
        if errorlevel 1 (
            call :say 6ZSZ6K+vOiDlpIfku73lpLHotKU6
            echo   "%~1" -^> "%BACKUP_DIR%\%~2"
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
call :say 5q2j5Zyo5bCd6K+V5LuO5aSH5Lu95oGi5aSN5a6J6KOF5YmN6YWN572uLi4u
if defined CREATED_FILES_LIST if exist "%CREATED_FILES_LIST%" (
    for /f "usebackq delims=" %%C in ("%CREATED_FILES_LIST%") do (
        if exist "%%C" del /f /q "%%C" >nul 2>nul
    )
)
for /f "delims=" %%F in ('dir /b /a-d "%BACKUP_DIR%" 2^>nul') do (
    if /I not "%%F"==".created-files" (
        if /I "%%F"=="verge.yaml" (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\%%F" >nul 2>nul
            if errorlevel 1 (
                call :say 6K2m5ZGKOiDmgaLlpI3lpLHotKU6
                echo   "%CLASH_DIR%\%%F"
            )
        ) else if /I "%%F"=="dns_config.yaml" (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\%%F" >nul 2>nul
            if errorlevel 1 (
                call :say 6K2m5ZGKOiDmgaLlpI3lpLHotKU6
                echo   "%CLASH_DIR%\%%F"
            )
        ) else (
            copy /Y "%BACKUP_DIR%\%%F" "%CLASH_DIR%\profiles\%%F" >nul 2>nul
            if errorlevel 1 (
                call :say 6K2m5ZGKOiDmgaLlpI3lpLHotKU6
                echo   "%CLASH_DIR%\profiles\%%F"
            )
        )
    )
)
call :say 5bey5bCd6K+V5oGi5aSN44CC5aSH5Lu955uu5b2VOg==
echo   %BACKUP_DIR%
exit /b 0

:copy_required
copy /Y "%~1" "%~2" >nul
if errorlevel 1 (
    call :say 6ZSZ6K+vOiDlpI3liLblpLHotKU6
    echo   "%~1" -^> "%~2"
    exit /b 1
)
exit /b 0

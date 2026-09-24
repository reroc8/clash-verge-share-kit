@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "CLOSE_PS1=%SCRIPT_DIR%close-clash-windows.ps1"
if not exist "%CLOSE_PS1%" set "CLOSE_PS1=%SCRIPT_DIR%install\close-clash-windows.ps1"

where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

if not exist "%CLOSE_PS1%" (
    echo ERROR: close-clash-windows.ps1 was not found.
    echo Please use the complete release package.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CLOSE_PS1%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Press any key to close...
pause >nul
exit /b %EXIT_CODE%

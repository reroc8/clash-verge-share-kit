@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_PS1=%SCRIPT_DIR%install-windows.ps1"
if not exist "%INSTALL_PS1%" set "INSTALL_PS1=%SCRIPT_DIR%install\install-windows.ps1"
if not exist "%INSTALL_PS1%" set "INSTALL_PS1=%SCRIPT_DIR%..\install\install-windows.ps1"

where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

if not exist "%INSTALL_PS1%" (
    echo ERROR: install-windows.ps1 was not found.
    echo Please use the complete release package.
    echo Press any key to close...
    pause >nul
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_PS1%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Press any key to close...
pause >nul
exit /b %EXIT_CODE%

# Behavior tests for install/close-clash-windows.ps1.
#
# Why this file exists: PowerShell unwraps single-element arrays on function
# return, and StrictMode 2.0 throws on .Count of a scalar or $null. The close
# script used to read .Count straight off Get-NamedProcess results, so on a
# normal machine (one GUI, one kernel) it aborted with an error traceback and
# closed nothing - even though README tells users to double-click it.
#
# The parent role runs each scenario in a child pwsh process (the close script
# ends with `exit`), with Get-Process / Stop-Process / Get-Service stubbed so
# no real process is ever touched. Everything ASCII-only: Windows PowerShell
# 5.1 decodes BOM-less .ps1 files as ANSI, so Chinese literals here would be
# corrupted; user-facing messages are compared via their UTF-8 base64 forms.

param([string] $RunScenario = "")

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$closeScript = Join-Path (Join-Path $rootDir 'install') 'close-clash-windows.ps1'
if (-not (Test-Path -LiteralPath $closeScript)) {
    throw "close-clash-windows.ps1 not found at $closeScript"
}

function Decode-Utf8Base64 {
    param([string] $Text)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Text))
}

# ---------- child role: run the close script once, with stubs ----------
if ($RunScenario -ne "") {
    function Write-Call {
        param([string] $Text)
        if ($env:WB_CLOSE_TEST_LOG) {
            [System.IO.File]::AppendAllText($env:WB_CLOSE_TEST_LOG, $Text + [Environment]::NewLine)
        }
    }

    # Return REAL System.Diagnostics.Process objects: a PSCustomObject would
    # answer .Count with 1 under StrictMode, hiding exactly the defect these
    # tests are here to catch.
    function Get-Process {
        param([string[]] $Name, [string] $ErrorAction)
        $joined = ($Name -join ',')
        if ($joined -match 'service') {
            return @()
        }
        if ($joined -match 'mihomo') {
            if ($RunScenario -eq 'kernel-survives') {
                return (Microsoft.PowerShell.Management\Get-Process -Id $PID)
            }
            return @()
        }
        if ($joined -match 'clash-verge|Clash Verge') {
            if ($RunScenario -eq 'none') {
                return @()
            }
            if ($RunScenario -eq 'gui-only') {
                # The call log doubles as the "GUI already stopped" marker: once
                # Stop-Process recorded a call, the GUI must no longer be found.
                # (Scope caveat: $script: inside these stubs resolves to the
                # close script's own scope, so state travels via env + file.)
                if ($env:WB_CLOSE_TEST_LOG -and (Test-Path -LiteralPath $env:WB_CLOSE_TEST_LOG)) {
                    return @()
                }
                return (Microsoft.PowerShell.Management\Get-Process -Id $PID)
            }
            return @()
        }
        return @()
    }
    function Stop-Process {
        param([int] $Id, [switch] $Force, [string] $ErrorAction)
        Write-Call ("stop:" + $Id)
    }
    function Start-Sleep {
        param([int] $Seconds)
    }
    function Get-Service {
        param([string] $Name, [string] $ErrorAction)
        return $null
    }
    function Stop-Service {
        param([string] $Name, [switch] $Force, [string] $ErrorAction)
    }
    function Read-Host {
        param([string] $Prompt)
        return ''
    }

    & $closeScript
    # `exit` inside a &-invoked script sets $LASTEXITCODE instead of terminating
    # this process, so forward the close script's own exit code.
    exit $LASTEXITCODE
}

# ---------- parent role: drive the scenarios and assert ----------
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$pwshPath = (Get-Process -Id $PID).Path

$noOpMessage = Decode-Utf8Base64 '5peg6ZyA5pON5L2c'
$closedMessage = Decode-Utf8Base64 '6YO95bey5YWz6Zet'
$kernelMessage = Decode-Utf8Base64 '5YaF5qC45LuN5Zyo6L+Q6KGM'

$stopLogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("close-clash-windows-test-" + [Guid]::NewGuid().ToString('N'))

function Invoke-CloseScenario {
    param([string] $Scenario)
    $logPath = Join-Path $stopLogDir ($Scenario + '.txt')
    $env:WB_CLOSE_TEST_LOG = $logPath
    $output = & $pwshPath -NoProfile -File $PSCommandPath -RunScenario $Scenario 2>&1
    $exitCode = $LASTEXITCODE
    $stopCount = 0
    if (Test-Path -LiteralPath $logPath) {
        $stopCount = @(Get-Content -LiteralPath $logPath).Count
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
        StopCount = $stopCount
    }
}

try {
    New-Item -ItemType Directory -Path $stopLogDir -Force | Out-Null

    $none = Invoke-CloseScenario 'none'
    if ($none.ExitCode -ne 0) { throw "no-process run must exit 0, got $($none.ExitCode): $($none.Output)" }
    if ($none.StopCount -ne 0) { throw "no-process run must not call Stop-Process, got $($none.StopCount) calls: $($none.Output)" }
    if ($none.Output -match 'cannot be found') { throw "no-process run hit the StrictMode .Count failure: $($none.Output)" }
    if (-not $none.Output.Contains($noOpMessage)) { throw "no-process run must print the no-op message: $($none.Output)" }

    $gui = Invoke-CloseScenario 'gui-only'
    if ($gui.ExitCode -ne 0) { throw "single-GUI run must exit 0, got $($gui.ExitCode): $($gui.Output)" }
    if ($gui.StopCount -ne 1) { throw "single-GUI run must stop the GUI exactly once, got $($gui.StopCount) calls: $($gui.Output)" }
    if ($gui.Output -match 'cannot be found') { throw "single-GUI run hit the StrictMode .Count failure: $($gui.Output)" }
    if (-not $gui.Output.Contains($closedMessage)) { throw "single-GUI run must report success: $($gui.Output)" }

    $kernel = Invoke-CloseScenario 'kernel-survives'
    if ($kernel.ExitCode -ne 1) { throw "kernel-survives run must exit 1 (relaunch-elevated path), got $($kernel.ExitCode): $($kernel.Output)" }
    if ($kernel.StopCount -lt 1) { throw "kernel-survives run must attempt to stop the kernel" }
    if ($kernel.Output -match 'cannot be found') { throw "kernel-survives run hit the StrictMode .Count failure: $($kernel.Output)" }
    if (-not $kernel.Output.Contains($kernelMessage)) { throw "kernel-survives run must report the kernel: $($kernel.Output)" }

    Write-Host 'close-clash-windows tests passed'
} finally {
    Remove-Item -LiteralPath $stopLogDir -Recurse -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Say-B64 {
    param([string] $Text)
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Host ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Text)))
}

# Names as used on Windows:
#   GUI     clash-verge / Clash Verge - exact or space variant, never the helper
#   kernel  verge-mihomo, verge-mihomo-alpha, mihomo
#   helper  the registered service is clash_verge_service (underscores) while its
#           process is clash-verge-service.exe (hyphens). It keeps running after
#           Clash is closed by design and never rewrites the config, so it is not
#           reported as something that must be stopped.
$guiNames = @('clash-verge', 'Clash Verge*')
$kernelNames = @('verge-mihomo*', 'mihomo')
$helperNames = @('clash-verge-service')
$serviceNames = @('clash_verge_service', 'clash-verge-service')

function Get-NamedProcess {
    param([string[]] $Names)
    return @(Get-Process -Name $Names -ErrorAction SilentlyContinue)
}

function Stop-NamedProcess {
    param([string[]] $Names)
    foreach ($proc in (Get-NamedProcess $Names)) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            $null = $_
        }
    }
}

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

Say-B64 '5YWz6ZetIENsYXNoIFZlcmdlIFJldiDlj4rlhbblhoXmoLg='
Write-Host ''

$runningGui = Get-NamedProcess $guiNames
$runningKernel = Get-NamedProcess $kernelNames

if ($runningGui.Count -eq 0 -and $runningKernel.Count -eq 0) {
    Say-B64 '5rKh5pyJ5Y+R546w5q2j5Zyo6L+Q6KGM55qEIENsYXNoIFZlcmdlIFJldiDmiJblhoXmoLjvvIzml6DpnIDmk43kvZw='
    if ((Get-NamedProcess $helperNames).Count -gt 0) {
        Say-B64 '5rOoOiDluLjpqbvliqnmiYsgY2xhc2gtdmVyZ2Utc2VydmljZSDku43lnKjov5DooYzvvIzov5nmmK/mraPluLjnmoTvvIzkuI3lvbHlk43lronoo4U='
    }
    exit 0
}

if ($runningGui.Count -gt 0) {
    Say-B64 '5q2j5Zyo5YWz6ZetIENsYXNoIFZlcmdlIFJldu+8iOeVjOmdoui/m+eoi++8iS4uLg=='
    Stop-NamedProcess $guiNames
}

if ($runningKernel.Count -gt 0) {
    Say-B64 '5q2j5Zyo5YWz6Zet5YaF5qC4Li4u'
    Stop-NamedProcess $kernelNames
}

Start-Sleep -Seconds 1

# Second pass: whatever ignored the first attempt gets forced again.
Stop-NamedProcess $guiNames
Stop-NamedProcess $kernelNames
Start-Sleep -Seconds 1

# The helper service is optional and needs admin rights; stop it best-effort.
foreach ($serviceName in $serviceNames) {
    try {
        $helperService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($helperService -and $helperService.Status -eq 'Running') {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        }
    } catch {
        $null = $_
    }
}

$runningGui = Get-NamedProcess $guiNames
$runningKernel = Get-NamedProcess $kernelNames

if ($runningGui.Count -eq 0 -and $runningKernel.Count -eq 0) {
    Say-B64 '57uT5p6cOiBDbGFzaCBWZXJnZSBSZXYg5Y+K5YW25YaF5qC46YO95bey5YWz6Zet77yM546w5Zyo5Y+v5Lul6L+Q6KGM5a6J6KOF5Zmo5LqG'
    exit 0
}

if ($runningGui.Count -gt 0) {
    Say-B64 '6ZSZ6K+vOiBDbGFzaCBWZXJnZSBSZXYg5LuN54S25rKh5YWz5o6J'
    Say-B64 '6K+35omL5Yqo5pON5L2c77ya54K55byAIENsYXNoIFZlcmdlIFJldiDnqpflj6PvvIzmiJbnlKjmiZjnm5jlm77moIfoj5zljZXph4znmoTjgIzpgIDlh7rjgI3vvJvnm7TmjqXlhbPnqpflj6Plj6rmmK/mnIDlsI/ljJbliLDmiZjnm5jvvIzov5vnqIvku43lnKjov5DooYw='
} else {
    Say-B64 '5YaF5qC45LuN5Zyo6L+Q6KGM44CC5a6D5LiN5Lya5b2x5ZON5a6J6KOF77yM5Y+v5Lul5LiN566h77yb6KOF5a6M6YeN5paw5omT5byAIENsYXNoIFZlcmdlIFJldiDljbPlj68='
}

# Both cases above can be caused by a SYSTEM-owned process, which a normal
# user cannot stop. Offer to relaunch this file elevated - the whole reason a
# separate, manually run file exists next to the installer.
Say-B64 '57uT5p6cOiDmnInov5vnqIvmsqHog73nu5PmnZ/jgILor7flj7PplK7mnKzmlofku7bvvIzpgInmi6njgIzku6XnrqHnkIblkZjouqvku73ov5DooYzjgI3lho3or5XkuIDmrKE='

if (-not (Test-IsElevated)) {
    try {
        $answer = Read-Host 'Run again as administrator? [y/N]'
    } catch {
        $answer = ''
    }
    if ($answer -match '^(y|yes)$') {
        try {
            Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
            ) -ErrorAction Stop
        } catch {
            $null = $_
        }
    }
}

exit 1

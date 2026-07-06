$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:InstallStarted = $false
$script:InstallCompleted = $false
$script:BackupDir = $null
$script:CreatedFilesList = $null
$script:ClashDir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$script:ProfilesDir = Join-Path $script:ClashDir 'profiles'

function Say-B64 {
    param([string] $Text)
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Host ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Text)))
}

function Say-Path {
    param([string] $Path)
    Write-Host ("  " + $Path)
}

function Restore-FromBackup {
    if (-not $script:InstallStarted) { return }
    if ($script:InstallCompleted) { return }
    if ([string]::IsNullOrWhiteSpace($script:BackupDir)) { return }
    if (-not (Test-Path -LiteralPath $script:BackupDir -PathType Container)) { return }

    Say-B64 '5q2j5Zyo5bCd6K+V5LuO5aSH5Lu95oGi5aSN5a6J6KOF5YmN6YWN572uLi4u'

    if ($script:CreatedFilesList -and (Test-Path -LiteralPath $script:CreatedFilesList)) {
        Get-Content -LiteralPath $script:CreatedFilesList -Encoding UTF8 | ForEach-Object {
            if ($_ -and (Test-Path -LiteralPath $_ -PathType Leaf)) {
                Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Get-ChildItem -LiteralPath $script:BackupDir -File | ForEach-Object {
        if ($_.Name -eq '.created-files') { return }
        if ($_.Name -eq 'verge.yaml' -or $_.Name -eq 'dns_config.yaml') {
            $target = Join-Path $script:ClashDir $_.Name
        } else {
            $target = Join-Path $script:ProfilesDir $_.Name
        }

        try {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop
        } catch {
            Say-B64 '6K2m5ZGKOiDmgaLlpI3lpLHotKU6'
            Say-Path $target
        }
    }

    Say-B64 '5bey5bCd6K+V5oGi5aSN44CC5aSH5Lu955uu5b2VOg=='
    Say-Path $script:BackupDir
}

function Fail-Install {
    param(
        [string] $Message,
        [string] $Detail = ''
    )
    if ($Message) { Say-B64 $Message }
    if ($Detail) { Say-Path $Detail }
    Restore-FromBackup
    Say-B64 '6ZSZ6K+vOiDlronoo4XmnKrlrozmiJDjgILor7fmn6XnnIvkuIrpnaLnmoTmj5DnpLrjgII='
    exit 1
}

function Backup-ExistingFile {
    param(
        [string] $Source,
        [string] $BackupName
    )
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        $backupPath = Join-Path $script:BackupDir $BackupName
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $Source -Destination $backupPath -Force -ErrorAction Stop
        }
    } else {
        [System.IO.File]::AppendAllText($script:CreatedFilesList, $Source + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    }
}

function Copy-Required {
    param(
        [string] $Source,
        [string] $Destination
    )
    Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
}

function Require-File {
    param(
        [string] $Path,
        [string] $Message
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail-Install $Message $Path
    }
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $parentDir = Split-Path -Parent $scriptDir
    $configDir = Join-Path $parentDir 'config'
    if (-not (Test-Path -LiteralPath (Join-Path $configDir 'Merge.yaml'))) {
        $configDir = $scriptDir
    }

    $packageVersion = 'dev'
    $versionFile = Join-Path $scriptDir 'VERSION.txt'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        $versionFile = Join-Path $parentDir 'VERSION.txt'
    }
    if (Test-Path -LiteralPath $versionFile) {
        $packageVersion = (Get-Content -LiteralPath $versionFile -Encoding UTF8 | Select-Object -First 1).Trim()
    }

    Say-B64 '5a6J6KOF5YyF54mI5pysOg=='
    Say-Path $packageVersion
    Say-B64 '5a6J6KOF5p2l5rqQOg=='
    Say-Path $scriptDir

    Require-File (Join-Path $configDir 'Merge.yaml') '6ZSZ6K+vOiDmib7kuI3liLDphY3nva7mlofku7bjgILor7fkvb/nlKjmraPlvI/ljovnvKnljIXvvIzlubbkv53mjIHmiYDmnInmlofku7blnKjlkIzkuIDmlofku7blpLnjgII='
    Require-File (Join-Path $configDir 'Script.js') '6ZSZ6K+vOiDmib7kuI3liLDphY3nva7mlofku7bjgILor7fkvb/nlKjmraPlvI/ljovnvKnljIXvvIzlubbkv53mjIHmiYDmnInmlofku7blnKjlkIzkuIDmlofku7blpLnjgII='
    Require-File (Join-Path $configDir 'verge.yaml') '6ZSZ6K+vOiDmib7kuI3liLDphY3nva7mlofku7bjgILor7fkvb/nlKjmraPlvI/ljovnvKnljIXvvIzlubbkv53mjIHmiYDmnInmlofku7blnKjlkIzkuIDmlofku7blpLnjgII='
    Require-File (Join-Path $configDir 'dns_config.yaml') '6ZSZ6K+vOiDmib7kuI3liLDphY3nva7mlofku7bjgILor7fkvb/nlKjmraPlvI/ljovnvKnljIXvvIzlubbkv53mjIHmiYDmnInmlofku7blnKjlkIzkuIDmlofku7blpLnjgII='

    if (-not (Test-Path -LiteralPath $script:ClashDir -PathType Container)) {
        Say-B64 '6ZSZ6K+vOiDmnKrmib7liLAgQ2xhc2ggVmVyZ2UgUmV2IOaVsOaNruebruW9leOAgg=='
        Say-B64 '6K+35YWI5a6J6KOFIENsYXNoIFZlcmdlIFJldu+8jOWvvOWFpeiHquW3seeahOiuoumYhe+8jOi/kOihjOS4gOasoe+8jOeEtuWQjuWujOWFqOmAgOWHuuOAgg=='
        exit 1
    }

    if (-not (Test-Path -LiteralPath $script:ProfilesDir -PathType Container)) {
        New-Item -ItemType Directory -Path $script:ProfilesDir -Force | Out-Null
    }

    $runningNames = @('clash-verge', 'Clash Verge Rev', 'verge-mihomo', 'verge-mihomo-alpha', 'mihomo')
    foreach ($name in $runningNames) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
            Say-B64 '6ZSZ6K+vOiDmo4DmtYvliLAgQ2xhc2ggVmVyZ2UgUmV2IOaIluWGheaguOS7jeWcqOi/kOihjOOAguivt+WFiOWujOWFqOmAgOWHuuOAgg=='
            exit 1
        }
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    for ($i = 0; $i -lt 10; $i++) {
        $candidate = Join-Path $script:ClashDir ("backup_{0}_{1}" -f $timestamp, (Get-Random -Minimum 10000000 -Maximum 99999999))
        if (-not (Test-Path -LiteralPath $candidate)) {
            New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
            $script:BackupDir = $candidate
            break
        }
    }
    if (-not $script:BackupDir) {
        Fail-Install '6ZSZ6K+vOiDml6Dms5XliJvlu7rlpIfku73nm67lvZU6'
    }

    Say-B64 '5a6J6KOF5YmN5bey5aSH5Lu95YiwOg=='
    Say-Path $script:BackupDir
    $script:CreatedFilesList = Join-Path $script:BackupDir '.created-files'
    Set-Content -LiteralPath $script:CreatedFilesList -Value '' -Encoding UTF8

    Backup-ExistingFile (Join-Path $script:ProfilesDir 'Merge.yaml') 'Merge.yaml'
    Backup-ExistingFile (Join-Path $script:ProfilesDir 'Script.js') 'Script.js'
    Backup-ExistingFile (Join-Path $script:ClashDir 'verge.yaml') 'verge.yaml'
    Backup-ExistingFile (Join-Path $script:ClashDir 'dns_config.yaml') 'dns_config.yaml'

    Say-B64 '5q2j5Zyo5a6J6KOFLi4u'
    $script:InstallStarted = $true
    Copy-Required (Join-Path $configDir 'Merge.yaml') (Join-Path $script:ProfilesDir 'Merge.yaml')
    Copy-Required (Join-Path $configDir 'Script.js') (Join-Path $script:ProfilesDir 'Script.js')

    $syncScript = Join-Path $scriptDir 'sync-profile-bound-files.ps1'
    if (-not (Test-Path -LiteralPath $syncScript)) {
        $syncScript = Join-Path $parentDir 'install\sync-profile-bound-files.ps1'
    }
    Require-File $syncScript '6ZSZ6K+vOiDnvLrlsJHlkIzmraXohJrmnKwgc3luYy1wcm9maWxlLWJvdW5kLWZpbGVzLnBzMeOAguivt+mHjeaWsOino+WOi+WujOaVtOWuieijheWMheOAgg=='

    $env:SYNC_CLASH_DIR = $script:ClashDir
    $env:SYNC_CONFIG_DIR = $configDir
    $env:SYNC_BACKUP_DIR = $script:BackupDir
    & powershell -NoProfile -ExecutionPolicy Bypass -File $syncScript | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail-Install '6ZSZ6K+vOiDlkIzmraXlt7LmnInorqLpmIXnu5HlrprnmoTphY3nva7mlofku7blpLHotKXjgII='
    }
    Say-B64 '5bey5ZCM5q2l5bey5pyJ6K6i6ZiF57uR5a6a55qE6YWN572u5paH5Lu244CC'
    Remove-Item Env:\SYNC_CLASH_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\SYNC_CONFIG_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\SYNC_BACKUP_DIR -ErrorAction SilentlyContinue

    Copy-Required (Join-Path $configDir 'verge.yaml') (Join-Path $script:ClashDir 'verge.yaml')
    Copy-Required (Join-Path $configDir 'dns_config.yaml') (Join-Path $script:ClashDir 'dns_config.yaml')

    $script:InstallCompleted = $true
    $oldBackups = Get-ChildItem -LiteralPath $script:ClashDir -Directory -Filter 'backup_*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -Skip 5
    $cleanupCount = 0
    foreach ($backup in $oldBackups) {
        Remove-Item -LiteralPath $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue
        $cleanupCount += 1
    }
    if ($cleanupCount -gt 0) {
        Say-B64 '5bey5riF55CG5pen5aSH5Lu977yM5LuF5L+d55WZ5pyA6L+RIDUg5LiqIGJhY2t1cF8qIOebruW9leOAgg=='
    }

    Write-Host ''
    Say-B64 '5a6J6KOF5a6M5oiQ44CC'
    Say-B64 '5L2g55qE6K6i6ZiF5ZKM6IqC54K55rKh5pyJ6KKr5L+u5pS544CC'
    Say-B64 '5aSH5Lu95L2N572uOg=='
    Say-Path $script:BackupDir
    Say-B64 '5LiL5LiA5q2lOg=='
    Say-B64 'ICAxLiDph43mlrDmiZPlvIAgQ2xhc2ggVmVyZ2UgUmV244CC'
    Say-B64 'ICAyLiDlnKjku6PnkIbpobXnoa7orqTog73nnIvliLDov5nkupvliIbnu4Q6'
    Write-Host '  Claude / AI / Google / YouTube / Telegram / Exchange / US / TW / SG / HK / JP / Proxies'
    Say-B64 'ICAzLiDmjIkgUkVBRE1FLnR4dCDnmoTigJzlronoo4XlkI4gNjAg56eS5qOA5p+l5riF5Y2V4oCd5rWL6K+V44CC'
    Say-B64 '5aaC5p6c5p+Q57G7572R56uZ5byC5bi477yM5YWI5YiH5o2i5a+55bqU562W55Wl57uE6IqC54K544CC'
    exit 0
} catch {
    Restore-FromBackup
    Say-B64 '6ZSZ6K+vOiDlronoo4XmnKrlrozmiJDjgILor7fmn6XnnIvkuIrpnaLnmoTmj5DnpLrjgII='
    Say-Path $_.Exception.Message
    exit 1
}

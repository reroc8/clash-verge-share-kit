param(
    [string] $ClashDir = $env:SYNC_CLASH_DIR,
    [string] $ConfigDir = $env:SYNC_CONFIG_DIR,
    [string] $BackupDir = $env:SYNC_BACKUP_DIR
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Require-Directory {
    param(
        [string] $Name,
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Name is empty"
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Name does not exist: $Path"
    }
}

try {
    Require-Directory 'ClashDir' $ClashDir
    Require-Directory 'ConfigDir' $ConfigDir
    Require-Directory 'BackupDir' $BackupDir

    $profiles = Join-Path $ClashDir 'profiles'
    Require-Directory 'profiles' $profiles

    $profilesYaml = Join-Path $ClashDir 'profiles.yaml'

    if (-not (Test-Path -LiteralPath $profilesYaml)) {
        Write-Host 'profiles.yaml not found; skip profile-bound file sync'
        exit 0
    }

    $script:ItemType = $null
    $script:SyncedCount = 0

    Get-Content -LiteralPath $profilesYaml -ErrorAction Stop | ForEach-Object {
        $line = $_

        if ($line -match '^- uid:') {
            $script:ItemType = $null
            return
        }

        if ($line -match '^\s*type:\s*(merge|script)\s*$') {
            $script:ItemType = $Matches[1]
            return
        }

        if ($line -match '^\s*file:\s*(.+?)\s*$' -and ($script:ItemType -eq 'merge' -or $script:ItemType -eq 'script')) {
            $file = $Matches[1].Trim().Trim([char]34).Trim([char]39)
            if ([string]::IsNullOrWhiteSpace($file) -or $file -match '[\\/:]' -or $file -match '\.\.') {
                return
            }

            $dst = Join-Path $profiles $file
            $backupDst = Join-Path $BackupDir $file

            if (Test-Path -LiteralPath $dst) {
                if (-not (Test-Path -LiteralPath $backupDst)) {
                    Copy-Item -LiteralPath $dst -Destination $backupDst -Force -ErrorAction Stop
                }
            }

            if ($script:ItemType -eq 'merge') {
                $src = Join-Path $ConfigDir 'Merge.yaml'
            } else {
                $src = Join-Path $ConfigDir 'Script.js'
            }

            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
            $script:SyncedCount += 1
        }
    }

    Write-Host "Synced profile-bound merge/script files: $script:SyncedCount"
    exit 0
} catch {
    Write-Host "Error: failed to sync profile-bound merge/script files: $($_.Exception.Message)"
    exit 1
}

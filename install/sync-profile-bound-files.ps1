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

function ConvertFrom-YamlScalar {
    param([string] $Value)

    if ($null -eq $Value) { return '' }
    $clean = ($Value -replace '\s+#.*$', '').Trim()
    if ($clean.Length -ge 2) {
        if (($clean.StartsWith('"') -and $clean.EndsWith('"')) -or
            ($clean.StartsWith("'") -and $clean.EndsWith("'"))) {
            $clean = $clean.Substring(1, $clean.Length - 2)
        }
    }
    return $clean
}

try {
    Require-Directory 'ClashDir' $ClashDir
    Require-Directory 'ConfigDir' $ConfigDir
    Require-Directory 'BackupDir' $BackupDir

    $profiles = Join-Path $ClashDir 'profiles'
    Require-Directory 'profiles' $profiles

    $profilesYaml = Join-Path $ClashDir 'profiles.yaml'
    $createdFilesList = Join-Path $BackupDir 'created-files.txt'

    if (-not (Test-Path -LiteralPath $profilesYaml)) {
        Write-Host 'profiles.yaml not found; skip profile-bound file sync'
        exit 0
    }

    $script:SyncedCount = 0
    $items = New-Object System.Collections.Generic.List[object]
    $currentType = $null
    $currentFile = $null
    $haveItem = $false
    $skippedMalformedItem = $false
    $flushItem = {
        if ($haveItem -and ($currentType -eq 'merge' -or $currentType -eq 'script') -and
            -not [string]::IsNullOrWhiteSpace($currentFile)) {
            $items.Add([pscustomobject]@{ Type = $currentType; File = $currentFile })
        } elseif ($haveItem -and ($currentType -eq 'merge' -or $currentType -eq 'script')) {
            Write-Host 'Warning: skipped a merge/script profile item without a file field'
        }
    }

    foreach ($line in (Get-Content -LiteralPath $profilesYaml -Encoding UTF8 -ErrorAction Stop)) {
        if ($line -match '^-\s*uid\s*:') {
            & $flushItem
            $currentType = $null
            $currentFile = $null
            $haveItem = $true
            continue
        }

        if ($line -match '^-\s*' -or $line -match '^\s+-\s*(?:uid|type|file|\{)') {
            & $flushItem
            $currentType = $null
            $currentFile = $null
            $haveItem = $false
            $skippedMalformedItem = $true
            continue
        }

        if (-not $haveItem) { continue }
        if ($line -match '^  type\s*:\s*(.*?)\s*$') {
            $currentType = ConvertFrom-YamlScalar $Matches[1]
            continue
        }
        if ($line -match '^  file\s*:\s*(.*?)\s*$') {
            $currentFile = ConvertFrom-YamlScalar $Matches[1]
        }
    }
    & $flushItem

    if ($skippedMalformedItem) {
        Write-Host 'Warning: skipped non-standard profiles.yaml entries; only Clash Verge - uid: items are supported'
    }

    foreach ($item in $items) {
        $file = $item.File
        if ([string]::IsNullOrWhiteSpace($file) -or $file -match '[\\/:]' -or $file -match '\.\.') {
            continue
        }

        $dst = Join-Path $profiles $file
        $backupProfilesDir = Join-Path $BackupDir 'profiles'
        if (-not (Test-Path -LiteralPath $backupProfilesDir -PathType Container)) {
            New-Item -ItemType Directory -Path $backupProfilesDir -Force -ErrorAction Stop | Out-Null
        }
        $backupDst = Join-Path $backupProfilesDir $file

        if (Test-Path -LiteralPath $dst) {
            if (-not (Test-Path -LiteralPath $backupDst)) {
                Copy-Item -LiteralPath $dst -Destination $backupDst -Force -ErrorAction Stop
            }
        } else {
            $createdFiles = @(Get-Content -LiteralPath $createdFilesList -Encoding UTF8 -ErrorAction SilentlyContinue)
            if ($createdFiles -notcontains $dst) {
                [System.IO.File]::AppendAllText($createdFilesList, $dst + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
            }
        }

        if ($item.Type -eq 'merge') {
            $src = Join-Path $ConfigDir 'Merge.yaml'
        } else {
            $src = Join-Path $ConfigDir 'Script.js'
        }

        Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
        $script:SyncedCount += 1
    }

    Write-Host "Synced profile-bound merge/script files: $script:SyncedCount"
    exit 0
} catch {
    Write-Host "Error: failed to sync profile-bound merge/script files: $($_.Exception.Message)"
    exit 1
}

param(
    [Parameter(Mandatory = $true)] [string] $ClashDir,
    [Parameter(Mandatory = $true)] [string] $ConfigDir,
    [Parameter(Mandatory = $true)] [string] $BackupDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

try {
    $profiles = Join-Path $ClashDir 'profiles'
    $profilesYaml = Join-Path $ClashDir 'profiles.yaml'

    if (-not (Test-Path -LiteralPath $profilesYaml)) {
        Write-Host '未找到 profiles.yaml，跳过订阅绑定文件同步'
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

    Write-Host "已同步已有订阅绑定的 merge/script 文件: $script:SyncedCount"
    exit 0
} catch {
    Write-Host "错误: 同步已有订阅绑定的 merge/script 文件失败: $($_.Exception.Message)"
    exit 1
}

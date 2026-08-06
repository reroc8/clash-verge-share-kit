$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clash-windows-sync-test-" + [Guid]::NewGuid().ToString('N'))
$clashDir = Join-Path $tempRoot 'clash'
$profilesDir = Join-Path $clashDir 'profiles'
$configDir = Join-Path $tempRoot 'config'
$backupDir = Join-Path $tempRoot 'backup'

try {
    New-Item -ItemType Directory -Path $profilesDir, $configDir, (Join-Path $backupDir 'root') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $configDir 'Merge.yaml') -Value 'new merge' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $configDir 'Script.js') -Value 'new script' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $backupDir 'created-files.txt') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $backupDir 'root\verge.yaml') -Value 'old root verge' -Encoding ASCII

    Set-Content -LiteralPath (Join-Path $profilesDir 'verge.yaml') -Value 'old profile verge' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $profilesDir 'order-first.yaml') -Value 'old order first' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $profilesDir 'inline.js') -Value 'old inline' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $profilesDir 'quoted.yaml') -Value 'old quoted' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $profilesDir 'untouched.yaml') -Value 'keep me' -Encoding ASCII

    @'
items:
- uid: collision
  type: merge
  file: verge.yaml
- uid: order-first
  file: order-first.yaml
  type: merge
- {uid: inline, file: inline.js, type: script}
- uid: quoted
  type: "merge" # comment
  file: "quoted.yaml" # comment
- uid: normal
  file: untouched.yaml
  type: remote
'@ | Set-Content -LiteralPath (Join-Path $clashDir 'profiles.yaml') -Encoding UTF8

    $powershellPath = (Get-Process -Id $PID).Path
    & $powershellPath -NoProfile -File (Join-Path $rootDir 'install\sync-profile-bound-files.ps1') -ClashDir $clashDir -ConfigDir $configDir -BackupDir $backupDir
    if ($LASTEXITCODE -ne 0) { throw "sync script exited with $LASTEXITCODE" }

    if ((Get-Content -LiteralPath (Join-Path $profilesDir 'verge.yaml') -Raw).Trim() -ne 'new merge') { throw 'verge profile was not synced' }
    if ((Get-Content -LiteralPath (Join-Path $profilesDir 'order-first.yaml') -Raw).Trim() -ne 'new merge') { throw 'field-order profile was not synced' }
    if ((Get-Content -LiteralPath (Join-Path $profilesDir 'inline.js') -Raw).Trim() -ne 'old inline') { throw 'non-standard inline profile must be skipped' }
    if ((Get-Content -LiteralPath (Join-Path $profilesDir 'quoted.yaml') -Raw).Trim() -ne 'new merge') { throw 'quoted profile was not synced' }
    if ((Get-Content -LiteralPath (Join-Path $profilesDir 'untouched.yaml') -Raw).Trim() -ne 'keep me') { throw 'normal profile was overwritten' }
    if ((Get-Content -LiteralPath (Join-Path $backupDir 'root\verge.yaml') -Raw).Trim() -ne 'old root verge') { throw 'root backup was overwritten' }
    if ((Get-Content -LiteralPath (Join-Path $backupDir 'profiles\verge.yaml') -Raw).Trim() -ne 'old profile verge') { throw 'profile backup is missing' }

    Write-Host 'Windows sync regression tests passed'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

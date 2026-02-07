# Archive Backup folders - reduces repo size
# Run from project root. Creates Backup_archived_YYYY-MM-DD.zip, then optionally removes Backup/

$date = Get-Date -Format "yyyy-MM-dd"
$archiveName = "Backup_archived_$date.zip"
$backupPath = Join-Path $PSScriptRoot "Backup"

if (-not (Test-Path $backupPath)) {
    Write-Host "No Backup folder found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Archiving Backup/ to $archiveName ..." -ForegroundColor Cyan
Compress-Archive -Path "$backupPath\*" -DestinationPath (Join-Path $PSScriptRoot $archiveName) -Force
Write-Host "Created $archiveName" -ForegroundColor Green

$response = Read-Host "Remove Backup folder to reduce repo size? (y/n)"
if ($response -eq 'y' -or $response -eq 'Y') {
    Remove-Item -Path $backupPath -Recurse -Force
    Write-Host "Removed Backup/" -ForegroundColor Green
} else {
    Write-Host "Backup/ kept. You can remove it manually after verifying the archive." -ForegroundColor Gray
}

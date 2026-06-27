# Test script
$dbPath = ".\keygen\subscribers.db"
$dbBackup = $null

Write-Host "Checking path: $dbPath"
if (Test-Path $dbPath) {
    Write-Host "File exists, creating temp file..."
    $dbBackup = [System.IO.Path]::GetTempFileName()
    Write-Host "Temp file created: $dbBackup"
    Copy-Item -Path $dbPath -Destination $dbBackup -Force
    Write-Host "Copied to temp successfully"
} else {
    Write-Host "File does not exist"
}

Write-Host "Doing simulated keygen folder cleaning..."
Remove-Item -Path ".\keygen\*" -Recurse -Force
New-Item -ItemType Directory -Force -Path ".\keygen"

Write-Host "Restoring..."
if ($dbBackup -and (Test-Path $dbBackup)) {
    Write-Host "Restoring from $dbBackup to $dbPath"
    Copy-Item -Path $dbBackup -Destination $dbPath -Force
    Remove-Item -Path $dbBackup -Force
    Write-Host "Restored successfully"
} else {
    Write-Host "Backup file not found or not created: $dbBackup"
}

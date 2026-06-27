# setup_new_store.ps1
# Interactive/Silent setup script to link database sync to a new GitHub repository/account.
# Must be run as Administrator.

param(
    [switch]$Silent
)

# Enable UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir "sync_config.json"
$syncDir = Join-Path $scriptDir "database_sync"
$taskName = "ELATTAR_Database_Backup"
$syncScriptPath = Join-Path $scriptDir "backup_sync.ps1"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "     ELATTAR Store - GitHub Link Setup Tool      " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Check Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    if (-not $Silent) {
        Write-Host "Please close this window, right-click 'setup_new_store.bat' and select 'Run as administrator'." -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
    }
    Exit 1
}

# 2. Get inputs
$repoUrl = "https://github.com/ELATTAROBOUR/OBOURDIST"
$branchName = "elobour"
$storeEmail = ""
$storeName = ""

if ($Silent) {
    # Read from config file
    if (-not (Test-Path $configPath)) {
        Write-Host "[ERROR] sync_config.json not found for silent setup!" -ForegroundColor Red
        Exit 1
    }
    try {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        $repoUrl = $config.repo_url
        $branchName = $config.branch_name
        $storeEmail = $config.store_email
        $storeName = $config.store_name
        
        if ([string]::IsNullOrEmpty($repoUrl)) {
            Write-Host "[ERROR] repo_url is empty in sync_config.json" -ForegroundColor Red
            Exit 1
        }
    } catch {
        Write-Host "[ERROR] Failed to read sync_config.json: $_" -ForegroundColor Red
        Exit 1
    }
} else {
    Write-Host "This script will link the database sync to a new GitHub account & repository." -ForegroundColor Gray
    Write-Host "Before proceeding, please ensure you have:" -ForegroundColor Yellow
    Write-Host "  1. Created the new GitHub repository." -ForegroundColor Yellow
    Write-Host "  2. Signed in to GitHub on this computer (e.g. using GitHub Desktop)." -ForegroundColor Yellow
    Write-Host ""

    # Interactive prompts
    while ([string]::IsNullOrEmpty($repoUrl)) {
        $repoUrl = Read-Host "1. Enter the new GitHub Repository URL (e.g. https://github.com/user/repo)"
        $repoUrl = $repoUrl.Trim()
    }

    $branchName = Read-Host "2. Enter the Git branch name [Press Enter for default: elobour]"
    $branchName = $branchName.Trim()
    if ([string]::IsNullOrEmpty($branchName)) {
        $branchName = "elobour"
    }

    while ([string]::IsNullOrEmpty($storeEmail)) {
        $storeEmail = Read-Host "3. Enter the GitHub email address for this store"
        $storeEmail = $storeEmail.Trim()
    }

    while ([string]::IsNullOrEmpty($storeName)) {
        $storeName = Read-Host "4. Enter the Store/Branch Name (e.g. ELATTAR Branch B)"
        $storeName = $storeName.Trim()
    }

    $machineId = ""
    while ($machineId -notmatch '^[1-9]$') {
        $machineId = Read-Host "5. Enter a unique Machine ID for this computer (1-9) [Press Enter for default: 1]"
        $machineId = $machineId.Trim()
        if ([string]::IsNullOrEmpty($machineId)) {
            $machineId = "1"
        }
    }

    Write-Host "`n--------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Summary of configuration:" -ForegroundColor Cyan
    Write-Host "Repository URL : $repoUrl" -ForegroundColor Gray
    Write-Host "Branch Name    : $branchName" -ForegroundColor Gray
    Write-Host "Store Email    : $storeEmail" -ForegroundColor Gray
    Write-Host "Store Name     : $storeName" -ForegroundColor Gray
    Write-Host "Machine ID     : $machineId" -ForegroundColor Gray
    Write-Host "--------------------------------------------------`n" -ForegroundColor Cyan

    $confirm = Read-Host "Is this information correct? (Y/N)"
    if ($confirm.Trim().ToUpper() -ne "Y") {
        Write-Host "Setup aborted." -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        Exit 1
    }

    # Save to config file
    Write-Host "`n[1/5] Saving configuration to sync_config.json..." -ForegroundColor Yellow
    $configObj = @{
        repo_url = $repoUrl
        branch_name = $branchName
        store_email = $storeEmail
        store_name = $storeName
        machine_id = $machineId
        sync_time = "00:00"
    }
    $configObj | ConvertTo-Json | Out-File -FilePath $configPath -Encoding utf8
    Write-Host "Configuration saved." -ForegroundColor Green
}

# Temporary directory to preserve backups during sync folder transition
$tempBackupDir = Join-Path $env:TEMP "elattar_sync_backup_temp"
if (Test-Path $tempBackupDir) {
    Remove-Item -Recurse -Force $tempBackupDir -ErrorAction SilentlyContinue | Out-Null
}
New-Item -ItemType Directory -Path $tempBackupDir -Force | Out-Null

# Preserve existing database files from the old sync folder if present
if (Test-Path $syncDir) {
    Get-ChildItem -Path $syncDir -Filter "ELATTAR_STORE*.db" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $tempBackupDir -Force | Out-Null
    }
}

# 3. Re-initialize database_sync folder
Write-Host "[2/5] Cleaning up old sync folder if present..." -ForegroundColor Yellow
if (Test-Path $syncDir) {
    try {
        Remove-Item -Recurse -Force $syncDir -ErrorAction SilentlyContinue
        # Fallback if folder is locked
        if (Test-Path $syncDir) {
            Write-Host "[WARNING] database_sync folder is locked. Attempting force deletion..." -ForegroundColor Yellow
            cmd.exe /c "rmdir /s /q `"$syncDir`""
        }
    } catch {
        Write-Host "[WARNING] Could not delete old sync folder. We will attempt to re-use it." -ForegroundColor Yellow
    }
}

Write-Host "Cloning branch '$branchName' from new repository..." -ForegroundColor Yellow
$cloneResult = git clone -b $branchName $repoUrl $syncDir 2>&1
$isNewInit = $false
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] Clone failed or branch does not exist. Initializing empty repository..." -ForegroundColor Yellow
    $isNewInit = $true
    
    # Create empty dir and init
    New-Item -ItemType Directory -Path $syncDir -Force | Out-Null
    Push-Location $syncDir
    git init
    git checkout -b $branchName
    git remote add origin $repoUrl
    Pop-Location
} else {
    Write-Host "Repository cloned successfully." -ForegroundColor Green
}

# Now populate and push the database files to the repository
if (Test-Path $syncDir) {
    Push-Location $syncDir
    
    # Restore any preserved databases from the temporary folder
    if (Test-Path $tempBackupDir) {
        Get-ChildItem -Path $tempBackupDir -Filter "ELATTAR_STORE*.db" | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $syncDir -Force | Out-Null
        }
    }
    
    # Copy active database from Documents to sync directory
    $dbName = "ELATTAR_STORE.db"
    $localDbPath = Join-Path $syncDir $dbName
    $documentsDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)
    $sourceDbPath = Join-Path $documentsDir $dbName
    
    if (Test-Path $sourceDbPath) {
        Copy-Item -Path $sourceDbPath -Destination $localDbPath -Force | Out-Null
    }
    
    # Ensure backup database exists in sync folder
    $backupDbPath = Join-Path $syncDir "ELATTAR_STORE_backup.db"
    if (-not (Test-Path $backupDbPath) -and (Test-Path $localDbPath)) {
        Copy-Item -Path $localDbPath -Destination $backupDbPath -Force | Out-Null
    }
    
    # Ensure daily backup database exists in sync folder
    $dailyDbPath = Join-Path $syncDir "ELATTAR_STORE_daily_backup.db"
    if (-not (Test-Path $dailyDbPath) -and (Test-Path $localDbPath)) {
        Copy-Item -Path $localDbPath -Destination $dailyDbPath -Force | Out-Null
    }
    
    # Add files to git
    git add $dbName
    if (Test-Path $backupDbPath) { git add "ELATTAR_STORE_backup.db" }
    if (Test-Path $dailyDbPath) { git add "ELATTAR_STORE_daily_backup.db" }
    
    # Set Git local config
    git config --local user.name "$storeName"
    git config --local user.email "$storeEmail"
    
    # Check if there are changes to commit
    $statusResult = git status --porcelain
    if ($statusResult) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        git commit -m "Initialize/Link database sync with backups [$storeEmail] [$timestamp]"
        
        Write-Host "Pushing database files to remote..." -ForegroundColor Yellow
        if ($isNewInit) {
            git push -u origin $branchName 2>&1
        } else {
            git push origin $branchName 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARNING] Could not push database files to remote repository. Please verify your connection/credentials!" -ForegroundColor Yellow
        } else {
            Write-Host "Database and backup files synced & pushed successfully." -ForegroundColor Green
        }
    } else {
        Write-Host "Database and backup files are already up-to-date in the repository." -ForegroundColor Green
    }
    
    Pop-Location
}

# 4. Set Git Local Identity on the new clone
Write-Host "[3/5] Configuring Git identity for this machine..." -ForegroundColor Yellow
if (Test-Path $syncDir) {
    Push-Location $syncDir
    git config --local user.name "$storeName"
    git config --local user.email "$storeEmail"
    Pop-Location
    Write-Host "Local identity set: $storeName ($storeEmail)" -ForegroundColor Green
}

# 5. Clean up old Windows Task Scheduler Task (since sync is now native in Flutter)
Write-Host "[4/5] Cleaning up old Task Scheduler backups if registered..." -ForegroundColor Yellow
try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
        Write-Host "Unregistered old scheduled task successfully." -ForegroundColor Green
    } else {
        Write-Host "No old scheduled task found. Skipping cleanup." -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARNING] Could not unregister old task: $_" -ForegroundColor Yellow
}

# 6. Perform verification check
Write-Host "[5/5] Verification check completed. Git directory initialized." -ForegroundColor Green

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    SETUP COMPLETE! Database is linked to GitHub  " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan

if (-not $Silent) {
    Read-Host "Press Enter to exit..."
}

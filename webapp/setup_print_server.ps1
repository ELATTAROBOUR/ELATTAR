<#
.SYNOPSIS
  ELATTAR Print Server — Setup & Auto-Start Installer

.DESCRIPTION
  Installs print_server.ps1 to run automatically when Windows starts.
  Two methods are offered:
    1. Startup Folder (simpler) — creates a .vbs launcher in shell:startup
    2. Scheduled Task (more reliable) — runs even when no user is logged in

  Run this script once after cloning/downloading the project.
  The print server MUST be running for the web app to print directly to
  Windows printers.

.EXAMPLE
  # Install as scheduled task (recommended)
  powershell -ExecutionPolicy Bypass -File setup_print_server.ps1 -Method Task

  # Install as startup shortcut
  powershell -ExecutionPolicy Bypass -File setup_print_server.ps1 -Method Startup

  # Test the server (after starting it)
  powershell -ExecutionPolicy Bypass -File setup_print_server.ps1 -Method Test
#>

param(
  [ValidateSet('Task', 'Startup', 'Test', 'Manual')]
  [string]$Method = 'Task'
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PrintServerPs1 = Join-Path $ScriptRoot 'lib\print_server.ps1'
$TaskName = 'ELATTAR Print Server'
$VbsName  = 'ELATTAR_PrintServer.launcher.vbs'

# ─── Helper: ensure the print server script exists ──────────────────────────
function Assert-ScriptExists {
  if (-not (Test-Path $PrintServerPs1)) {
    Write-Host "[ERROR] print_server.ps1 not found at: $PrintServerPs1" -ForegroundColor Red
    Write-Host "        Make sure you are running this script from the webapp/ folder." -ForegroundColor Yellow
    exit 1
  }
}

# ─── Method 1: Scheduled Task (recommended) ─────────────────────────────────
function Install-ScheduledTask {
  Assert-ScriptExists

  $action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PrintServerPs1`""

  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

  $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -Hidden

  $principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

  Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force

  if ($?) {
    Write-Host "[OK] Scheduled task '$TaskName' created successfully." -ForegroundColor Green
    Write-Host "     The print server will start automatically when you log in." -ForegroundColor Green
    Write-Host "     Task location: Task Scheduler Library → $TaskName" -ForegroundColor Gray
  } else {
    Write-Host "[ERROR] Failed to create scheduled task." -ForegroundColor Red
    exit 1
  }

  # Start it right now
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "[OK] Print server started now." -ForegroundColor Green
}

# ─── Method 2: Startup Folder shortcut ──────────────────────────────────────
function Install-StartupShortcut {
  Assert-ScriptExists

  # Create a VBS launcher (runs PowerShell silently, no window)
  $startupDir = [Environment]::GetFolderPath('Startup')
  $vbsPath = Join-Path $startupDir $VbsName

  $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PrintServerPs1`"", 0, False
"@

  [System.IO.File]::WriteAllText($vbsPath, $vbsContent, [System.Text.Encoding]::UTF8)

  if (Test-Path $vbsPath) {
    Write-Host "[OK] Startup shortcut created:" -ForegroundColor Green
    Write-Host "     $vbsPath" -ForegroundColor Gray
    Write-Host "     The print server will start automatically when you log in." -ForegroundColor Green
  } else {
    Write-Host "[ERROR] Failed to create startup shortcut." -ForegroundColor Red
    exit 1
  }

  # Launch it now
  & $vbsPath
  Write-Host "[OK] Print server started now." -ForegroundColor Green
}

# ─── Method 3: Test the server ─────────────────────────────────────────────
function Test-ServerConnection {
  Write-Host "Testing ELATTAR Print Server..." -ForegroundColor Cyan

  try {
    $res = Invoke-WebRequest -Uri 'http://localhost:19283/status' -UseBasicParsing -TimeoutSec 5
    if ($res.StatusCode -eq 200) {
      $data = $res.Content | ConvertFrom-Json
      Write-Host "[OK] Server is running on port 19283" -ForegroundColor Green
      Write-Host "     Status: $($data.status)" -ForegroundColor Gray
      Write-Host "     OS: $($data.os)" -ForegroundColor Gray
    } else {
      Write-Host "[WARN] Server returned HTTP $($res.StatusCode)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "[ERROR] Server is NOT running." -ForegroundColor Red
    Write-Host "        Start it manually:" -ForegroundColor Yellow
    Write-Host "        powershell -ExecutionPolicy Bypass -File `"$PrintServerPs1`"" -ForegroundColor Yellow
    exit 1
  }

  # Test listing printers
  try {
    $res = Invoke-WebRequest -Uri 'http://localhost:19283/list-printers' -UseBasicParsing -TimeoutSec 5
    if ($res.StatusCode -eq 200) {
      $printers = $res.Content | ConvertFrom-Json
      Write-Host "[OK] Detected $($printers.Count) printer(s):" -ForegroundColor Green
      $printers | ForEach-Object { Write-Host "     - $($_.name)" -ForegroundColor Gray }
    }
  } catch {
    Write-Host "[WARN] Could not list printers: $_" -ForegroundColor Yellow
  }
}

# ─── Method 4: Manual instructions ─────────────────────────────────────────
function Show-ManualInstructions {
  Write-Host ""
  Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
  Write-Host "║        ELATTAR Print Server — Manual Setup              ║" -ForegroundColor Cyan
  Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "To start the server manually:" -ForegroundColor White
  Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PrintServerPs1`"" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "To test if the server is running:" -ForegroundColor White
  Write-Host "  Visit http://localhost:19283/status in your browser" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "For auto-start, run this script again with:" -ForegroundColor White
  Write-Host "  -Method Task     (recommended — runs as scheduled task)" -ForegroundColor Yellow
  Write-Host "  -Method Startup  (simpler — uses startup folder)" -ForegroundColor Yellow
  Write-Host ""
}

# ─── Main ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       ELATTAR Print Server — Setup                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

switch ($Method) {
  'Task'    { Install-ScheduledTask }
  'Startup' { Install-StartupShortcut }
  'Test'    { Test-ServerConnection }
  'Manual'  { Show-ManualInstructions }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan

# Build script for ELATTAROBOUR Mobile Apps
# Builds two separate APKs from the same project with different entry points.
# Each APK has a different app name on the phone (via APP_LABEL env var).
#
# Usage: .\BUILD_BOTH.ps1
#
# Output:
#   build\app\outputs\flutter-apk\Elattar_Store.apk  (app name: Elattar Store)
#   build\app\outputs\flutter-apk\KEY.apk            (app name: KEYGEN)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$OutputDir = Join-Path $ProjectRoot "build\app\outputs\flutter-apk"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ELATTAROBOUR Mobile Apps Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# Build 1: Main App (Elattar Store)
# ============================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Step 1: Building Store App..." -ForegroundColor Yellow
Write-Host "  APK: Elattar_Store.apk" -ForegroundColor Yellow
Write-Host "  App Name: العطار استور" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Set env vars explicitly for Store app to prevent leftover env var leaks
$env:APP_LABEL = "العطار استور"
$env:APP_ID = "com.elattar.mobileapp.mobileapp"
Push-Location $ProjectRoot
try {
    flutter build apk --release -t lib/main.dart
} finally {
    Pop-Location
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Store App build failed!" -ForegroundColor Red
    exit 1
}

# Rename the APK
$MainApk = Join-Path $OutputDir "app-release.apk"
$MainApkNew = Join-Path $OutputDir "Elattar_Store.apk"
if (Test-Path $MainApkNew) { Remove-Item $MainApkNew -Force }
Rename-Item -Path $MainApk -NewName "Elattar_Store.apk"
Write-Host "Elattar Store built successfully!" -ForegroundColor Green
Write-Host "   ➜ $MainApkNew" -ForegroundColor Green

# ============================================
# Build 2: Keygen App (KEY)
# ============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Step 2: Building KEY..." -ForegroundColor Yellow
Write-Host "  APK: KEY.apk" -ForegroundColor Yellow
Write-Host "  App Name: KEY" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Set env vars so Gradle uses different package name + label for KEY
$env:APP_LABEL = "KEY"
$env:APP_ID = "com.elattar.mobileapp.keygen"
Push-Location $ProjectRoot
try {
    flutter build apk --release -t lib/entry_keygen.dart
} finally {
    Pop-Location
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: KEY build failed!" -ForegroundColor Red
    exit 1
}

# Rename the APK
$KeyApk = Join-Path $OutputDir "app-release.apk"
$KeyApkNew = Join-Path $OutputDir "KEY.apk"
if (Test-Path $KeyApkNew) { Remove-Item $KeyApkNew -Force }
Rename-Item -Path $KeyApk -NewName "KEY.apk"
Write-Host "KEY built successfully!" -ForegroundColor Green
Write-Host "   ➜ $KeyApkNew" -ForegroundColor Green

# ============================================
# Summary
# ============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Both applications built successfully!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$mainSize = [math]::Round((Get-Item "$MainApkNew").Length / 1MB, 1)
$keySize = [math]::Round((Get-Item "$KeyApkNew").Length / 1MB, 1)
Write-Host ""
Write-Host "Store App APK:" -ForegroundColor White
Write-Host "    App Label: Elattar Store" -ForegroundColor White
Write-Host "    Package: com.elattar.mobileapp.mobileapp" -ForegroundColor White
Write-Host "    Size: ${mainSize}MB" -ForegroundColor White
Write-Host "    Path: $MainApkNew" -ForegroundColor White
Write-Host ""
Write-Host "Keygen APK:" -ForegroundColor White
Write-Host "    App Label: KEY" -ForegroundColor White
Write-Host "    Package: com.elattar.mobileapp.keygen" -ForegroundColor White
Write-Host "    Size: ${keySize}MB" -ForegroundColor White
Write-Host "    Path: $KeyApkNew" -ForegroundColor White
Write-Host ""
Write-Host "APKs have different package names and can be installed side-by-side!" -ForegroundColor Green

# deploy.ps1 - Learnova one-command deploy to learnova.optimus.com.my
# Usage: cd C:\learnova_app && .\deploy.ps1

$ErrorActionPreference = "Continue"
$FlutterBin = "C:\flutter\bin\flutter.bat"
$ProjectDir = "C:\learnova_app"
$BuildDir   = "$ProjectDir\build\web"
$ZipPath    = "$ProjectDir\learnova_deploy.zip"
$FtpUrl     = "ftp://optimus.com.my/public_html/Learnova/learnova.zip"
$FtpUser    = "optimus"
$FtpPass    = "sa@yHLVwmHMN"
$ExtractUrl = "https://learnova.optimus.com.my/deploy_extract.php?token=LN_DEPLOY_2026"

Write-Host ""
Write-Host "=== LEARNOVA DEPLOY ===" -ForegroundColor Cyan

# 1 - Build
Write-Host "[1/5] Building Flutter web..." -ForegroundColor Yellow
Set-Location $ProjectDir
& $FlutterBin build web --release
if ($LASTEXITCODE -ne 0) { Write-Host "Build FAILED" -ForegroundColor Red; exit 1 }
Write-Host "      Build OK" -ForegroundColor Green

# 2 - Patch service worker: force immediate activation on ALL devices
# Flutter's SW waits for tabs to close before updating - this kills that behaviour.
# Two lines appended after every build. Permanent fix, no manual cache clearing needed.
Write-Host "[2/5] Patching service worker (skip-waiting)..." -ForegroundColor Yellow
$swPath = "$BuildDir\flutter_service_worker.js"
$patch = "`n// LEARNOVA PATCH: auto-activate immediately, never wait for tabs to close.`nself.addEventListener('install',  function() { self.skipWaiting(); });`nself.addEventListener('activate', function(e) { e.waitUntil(self.clients.claim()); });"
Add-Content -Path $swPath -Value $patch -Encoding UTF8
Write-Host "      SW patched OK" -ForegroundColor Green

# 3 - Zip
Write-Host "[3/5] Creating zip..." -ForegroundColor Yellow
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$BuildDir\*" -DestinationPath $ZipPath -Force
$sizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "      Zip OK ($sizeMB MB)" -ForegroundColor Green

# 4 - Upload
Write-Host "[4/5] Uploading to server..." -ForegroundColor Yellow
curl.exe -s -T $ZipPath $FtpUrl --user "${FtpUser}:${FtpPass}"
Write-Host "      Upload OK" -ForegroundColor Green

# 5 - Extract
Write-Host "[5/5] Extracting on server..." -ForegroundColor Yellow
$result = curl.exe -s $ExtractUrl
if ($result -like "Deploy OK*") {
    Write-Host "      $result" -ForegroundColor Green
} else {
    Write-Host "      Server said: $result" -ForegroundColor Red; exit 1
}

Write-Host ""
Write-Host "LIVE => https://learnova.optimus.com.my" -ForegroundColor Cyan
Write-Host "Users get the update on next page open. No cache clearing ever needed." -ForegroundColor Green
Write-Host ""

param(
  [string]$message = "Deploy Learnova"
)

$ftpHost    = "learnova.optimus.com.my"
$ftpUser    = if ($env:LEARNOVA_FTP_USER) { $env:LEARNOVA_FTP_USER } else { "optimus" }
$ftpPass    = if ($env:LEARNOVA_FTP_PASS) { $env:LEARNOVA_FTP_PASS } else { throw "Set LEARNOVA_FTP_PASS env var" }
$remotePath = "/home/optimus/public_html/Learnova"
$localWeb   = "C:\learnova_app\build\web"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " LEARNOVA DEPLOYMENT SCRIPT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 0 — Pre-deploy checks
Write-Host "`n[0/4] Running pre-deploy checks..." -ForegroundColor Yellow
& "C:\learnova_app\check_before_deploy.ps1"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Deploy ABORTED - fix issues first!" -ForegroundColor Red
  exit 1
}
Write-Host "Checks passed. Deploying...`n" -ForegroundColor Green

# Step 1 — Build
Write-Host "`n[1/4] Building Flutter web..." -ForegroundColor Yellow
Set-Location C:\learnova_app
& C:\flutter\bin\flutter.bat build web --release --pwa-strategy=none "--base-href=/"
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED." -ForegroundColor Red; exit 1 }
Write-Host "Build complete." -ForegroundColor Green

# Step 2 — Ensure .htaccess is in build output
Write-Host "`n[2/4] Copying .htaccess to build output..." -ForegroundColor Yellow
Copy-Item "C:\learnova_app\web\.htaccess" "$localWeb\.htaccess" -Force
Write-Host ".htaccess copied." -ForegroundColor Green

# Step 3 — Zip
Write-Host "`n[3/4] Creating deploy zip..." -ForegroundColor Yellow
$zipPath = "C:\learnova_app\build\deploy_fresh.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$localWeb\*" -DestinationPath $zipPath -Force
$size = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "Zip: $size MB" -ForegroundColor Green

# Step 4 — Upload zip, extract, delete
Write-Host "`n[4/4] Uploading to cPanel FTP..." -ForegroundColor Yellow
curl.exe -T $zipPath "ftp://$ftpHost$remotePath/deploy_fresh.zip" `
  --user "${ftpUser}:${ftpPass}" --ftp-create-dirs --progress-bar
if ($LASTEXITCODE -ne 0) { Write-Host "FTP upload failed." -ForegroundColor Red; exit 1 }

Write-Host "Extracting..." -ForegroundColor Yellow
$r = curl.exe -s -u "${ftpUser}:${ftpPass}" `
  "https://${ftpHost}:2083/json-api/cpanel" `
  -d "cpanel_jsonapi_module=Fileman&cpanel_jsonapi_func=fileop&op=extract&destfiles%5B0%5D=%2Fpublic_html%2FLearnova&sourcefiles%5B0%5D=%2Fpublic_html%2FLearnova%2Fdeploy_fresh.zip"
Write-Host $r

Write-Host "Cleaning up zip..." -ForegroundColor Yellow
curl.exe -s "ftp://$ftpHost$remotePath/deploy_fresh.zip" `
  --user "${ftpUser}:${ftpPass}" -Q "DELE $remotePath/deploy_fresh.zip" | Out-Null

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " DEPLOYED SUCCESSFULLY" -ForegroundColor Green
Write-Host " Live: https://learnova.optimus.com.my" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

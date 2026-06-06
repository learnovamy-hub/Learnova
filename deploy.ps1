param(
  [string]$message = "Deploy Learnova"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " LEARNOVA DEPLOYMENT SCRIPT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 1 — Build
Write-Host "`n[1/3] Building Flutter web..." -ForegroundColor Yellow
Set-Location C:\learnova_app
& C:\flutter\bin\flutter.bat build web --release
if ($LASTEXITCODE -ne 0) {
  Write-Host "BUILD FAILED. Stopping." -ForegroundColor Red
  exit 1
}
$buildTime = Get-Date -Format "HH:mm:ss"
Write-Host "Build complete at $buildTime." -ForegroundColor Green

# Step 2 — Zip
Write-Host "`n[2/3] Creating deployment zip..." -ForegroundColor Yellow
Set-Location C:\learnova_app\build
if (Test-Path deploy_fresh.zip) { Remove-Item deploy_fresh.zip -Force }
Compress-Archive -Path web\* -DestinationPath deploy_fresh.zip -Force
$size = [math]::Round((Get-Item deploy_fresh.zip).Length / 1MB, 2)
Write-Host "Zip created: $size MB" -ForegroundColor Green

# Step 3 — Push to gh-pages
Write-Host "`n[3/3] Deploying to GitHub Pages..." -ForegroundColor Yellow
Set-Location C:\learnova_app

# Use worktree to avoid switching branches
$worktreePath = "C:\learnova_ghpages_deploy"
if (Test-Path $worktreePath) {
  git worktree remove $worktreePath --force 2>$null
}
git worktree add $worktreePath gh-pages

# Clear old files (keep .git)
Get-ChildItem $worktreePath -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force

# Copy fresh build
Copy-Item -Path C:\learnova_app\build\web\* -Destination $worktreePath\ -Recurse -Force

# Restore CNAME (critical — without this custom domain breaks)
Set-Content -Path "$worktreePath\CNAME" -Value "learnova.optimus.com.my" -Encoding utf8 -NoNewline

# Commit and push
Set-Location $worktreePath
git add -A
git commit -m $message
git push origin gh-pages --force

$pushCode = $LASTEXITCODE

# Cleanup
Set-Location C:\learnova_app
git worktree remove $worktreePath --force

if ($pushCode -ne 0) {
  Write-Host "PUSH FAILED." -ForegroundColor Red
  exit 1
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " DEPLOYED SUCCESSFULLY" -ForegroundColor Green
Write-Host " Live: https://learnova.optimus.com.my" -ForegroundColor Green
Write-Host " (GitHub Pages takes ~30s to update)" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Green

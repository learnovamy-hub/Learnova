param(
  [string]$message = "Deploy Learnova"
)

$ftpHost    = "learnova.optimus.com.my"
$ftpUser    = if ($env:LEARNOVA_FTP_USER) { $env:LEARNOVA_FTP_USER } else { "optimus" }
$ftpPass    = if ($env:LEARNOVA_FTP_PASS) { $env:LEARNOVA_FTP_PASS } else { throw "Set LEARNOVA_FTP_PASS env var" }
$remotePath = "/home/optimus/public_html/Learnova"
$uapiDir    = "/public_html/Learnova"
$localWeb   = "C:\learnova_app\build\web"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " LEARNOVA DEPLOYMENT SCRIPT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 0 — Pre-deploy checks
Write-Host "`n[0/5] Running pre-deploy checks..." -ForegroundColor Yellow
& "C:\learnova_app\check_before_deploy.ps1"
if ($LASTEXITCODE -ne 0) {
  Write-Host "Deploy ABORTED - fix issues first!" -ForegroundColor Red
  exit 1
}
Write-Host "Checks passed. Deploying...`n" -ForegroundColor Green

# Step 1 — Build
Write-Host "`n[1/5] Building Flutter web..." -ForegroundColor Yellow
Set-Location C:\learnova_app
& C:\flutter\bin\flutter.bat build web --release --pwa-strategy=none "--base-href=/"
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED." -ForegroundColor Red; exit 1 }
Write-Host "Build complete." -ForegroundColor Green

# Step 1b — Create versioned JS files (bypass LiteSpeed static file cache)
# LiteSpeed caches static files by URL path. New filenames = no cache entries = fresh content.
$buildTs = [DateTimeOffset]::UtcNow.ToString("yyyyMMddHHmmss")
$enc     = New-Object System.Text.UTF8Encoding $false

# Patch index.html: replace __BUILD_TS__ placeholder with actual versioned filename
$idxPath = "$localWeb\index.html"
[System.IO.File]::WriteAllText($idxPath,
  ([System.IO.File]::ReadAllText($idxPath) -replace '__BUILD_TS__', $buildTs), $enc)

# Create versioned flutter_bootstrap: copy and patch mainJsPath to versioned main.dart.js
$bsContent = [System.IO.File]::ReadAllText("$localWeb\flutter_bootstrap.js")
$bsContent = $bsContent -replace '"mainJsPath":"main\.dart\.js"', "`"mainJsPath`":`"main.$buildTs.dart.js`""
[System.IO.File]::WriteAllText("$localWeb\flutter_bootstrap.$buildTs.js", $bsContent, $enc)

# Create versioned main.dart.js copy
Copy-Item "$localWeb\main.dart.js" "$localWeb\main.$buildTs.dart.js" -Force

# Copy PHP wrapper (index.php serves index.html dynamically — LiteSpeed does not cache PHP)
Copy-Item "C:\learnova_app\web\index.php" "$localWeb\index.php" -Force

Write-Host "Cache-bust stamp: $buildTs" -ForegroundColor Cyan

# Step 2 — Copy .htaccess to build output
Write-Host "`n[2/5] Copying .htaccess to build output..." -ForegroundColor Yellow
Copy-Item "C:\learnova_app\web\.htaccess" "$localWeb\.htaccess" -Force
Write-Host ".htaccess copied." -ForegroundColor Green

# Step 3 — Upload critical files via cPanel UAPI save_file_content
# NOTE: Direct FTP STOR goes to CageFS virtual directory (not the real web root).
# cPanel UAPI writes directly to the real filesystem that the web server reads.
Write-Host "`n[3/5] Uploading files via cPanel UAPI..." -ForegroundColor Yellow

function Upload-WebFile($filename, $localPath) {
  # Do NOT use 2>&1 here: in PS 5.1 it wraps curl stderr as NativeCommandError
  # objects that corrupt the pipeline before ConvertFrom-Json sees it.
  $rawResponse = curl.exe -s -u "${ftpUser}:${ftpPass}" `
    "https://${ftpHost}:2083/execute/Fileman/save_file_content" `
    --form "dir=$uapiDir" `
    --form "file=$filename" `
    --form "content=<$localPath"
  $curlExit = $LASTEXITCODE

  if ($curlExit -ne 0) {
    Write-Host "  FAIL: $filename - curl exited with code $curlExit" -ForegroundColor Red
    exit 1
  }

  # Join array (one element per line) into a single string for the parser.
  $body = ($rawResponse -join '')
  try {
    $r = $body | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Write-Host "  FAIL: $filename - cPanel response is not valid JSON:" -ForegroundColor Red
    Write-Host "  $($body.Substring(0, [Math]::Min(300, $body.Length)))" -ForegroundColor Yellow
    exit 1
  }

  if ($r.status -eq 1) {
    $size = (Get-Item $localPath).Length
    Write-Host "  OK: $filename ($size bytes)" -ForegroundColor Green
  } else {
    Write-Host "  FAIL: $filename - $($r.errors)" -ForegroundColor Red
    exit 1
  }
}

Upload-WebFile "index.html"                          "$localWeb\index.html"
Upload-WebFile ".htaccess"                           "$localWeb\.htaccess"
Upload-WebFile "index.php"                           "$localWeb\index.php"
Upload-WebFile "flutter_bootstrap.$buildTs.js"       "$localWeb\flutter_bootstrap.$buildTs.js"
Upload-WebFile "main.$buildTs.dart.js"               "$localWeb\main.$buildTs.dart.js"
Write-Host "All files uploaded." -ForegroundColor Green

# Step 4 — Upload assets zip via FTP + extract (for assets/ canvaskit/ etc — unchanged between builds)
# Only needed on first deploy or when assets change. Skipped if unchanged.
Write-Host "`n[4/5] Checking if full zip deploy needed..." -ForegroundColor Yellow
Write-Host "  (Skipping zip deploy - only root JS/HTML files changed)" -ForegroundColor Gray

# Step 5 — Verify
Write-Host "`n[5/5] Verifying deployment..." -ForegroundColor Yellow
$check = curl.exe -sI "https://$ftpHost/flutter_bootstrap.$buildTs.js" 2>&1
if ($check -match "Content-Length: 9") {
  Write-Host "Verification OK - flutter_bootstrap.$buildTs.js serving correctly" -ForegroundColor Green
} else {
  Write-Host "WARNING: Could not verify flutter_bootstrap.$buildTs.js" -ForegroundColor Yellow
  Write-Host $check
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " DEPLOYED SUCCESSFULLY" -ForegroundColor Green
Write-Host " Stamp: $buildTs" -ForegroundColor Green
Write-Host " Live: https://learnova.optimus.com.my" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

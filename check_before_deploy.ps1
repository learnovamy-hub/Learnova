Set-Location C:\learnova_app

Write-Host "LEARNOVA PRE-DEPLOY CHECKS" -ForegroundColor Cyan
Write-Host "══════════════════════════" -ForegroundColor Cyan
$errors = 0

# CHECK 1 — No CupertinoIcons
Write-Host "`nChecking CupertinoIcons..." -NoNewline
$cupertino = Get-ChildItem lib -Recurse -Filter "*.dart" |
  Select-String "CupertinoIcons" |
  Select-Object -First 1
if ($cupertino) {
  Write-Host " FAIL - Found in $($cupertino.Filename)" -ForegroundColor Red
  $errors++
} else {
  Write-Host " OK" -ForegroundColor Green
}

# CHECK 2 — No hardcoded "kau" in strings (word boundary, skip comments)
Write-Host "Checking BM language (kau)..." -NoNewline
$kau = Get-ChildItem lib -Recurse -Filter "*.dart" |
  Select-String '\bkau\b' |
  Where-Object { $_ -notmatch "^\s*//" } |
  Select-Object -First 1
if ($kau) {
  Write-Host " WARN - Found kau in $($kau.Filename):$($kau.LineNumber)" -ForegroundColor Yellow
} else {
  Write-Host " OK" -ForegroundColor Green
}

# CHECK 3 — No raw JSON leak patterns (Text widget containing {)
Write-Host "Checking for JSON leak patterns..." -NoNewline
$json = Get-ChildItem lib -Recurse -Filter "*.dart" |
  Select-String 'Text\(.*\{.*\}' |
  Select-Object -First 1
if ($json) {
  Write-Host " WARN - Possible JSON in Text() at $($json.Filename):$($json.LineNumber)" -ForegroundColor Yellow
} else {
  Write-Host " OK" -ForegroundColor Green
}

# CHECK 4 — CORS includes production domain
Write-Host "Checking CORS config..." -NoNewline
$cors = Select-String "learnova.optimus.com.my" "C:\Learnova\server_updated.mjs"
if (-not $cors) {
  Write-Host " FAIL - Production domain not in CORS!" -ForegroundColor Red
  $errors++
} else {
  Write-Host " OK" -ForegroundColor Green
}

# CHECK 5 — .htaccess exists in web folder
Write-Host "Checking .htaccess..." -NoNewline
if (-not (Test-Path "web\.htaccess")) {
  Write-Host " FAIL - Missing web\.htaccess!" -ForegroundColor Red
  $errors++
} else {
  Write-Host " OK" -ForegroundColor Green
}

# CHECK 6 — Build exists and is recent (under 24h)
Write-Host "Checking build freshness..." -NoNewline
if (Test-Path "build\web\main.dart.js") {
  $buildAge = (Get-Date) - (Get-Item "build\web\main.dart.js").LastWriteTime
  if ($buildAge.TotalHours -gt 24) {
    Write-Host " WARN - Build is $([int]$buildAge.TotalHours)h old" -ForegroundColor Yellow
  } else {
    Write-Host " OK ($([int]$buildAge.TotalMinutes)m old)" -ForegroundColor Green
  }
} else {
  Write-Host " FAIL - No build found!" -ForegroundColor Red
  $errors++
}

# CHECK 7 — Railway server is responding
Write-Host "Checking Railway server..." -NoNewline
try {
  $response = Invoke-WebRequest -Uri "https://learnova-backend-production-bd3a.up.railway.app/health" -TimeoutSec 10 -UseBasicParsing
  if ($response.StatusCode -eq 200) {
    Write-Host " OK" -ForegroundColor Green
  } else {
    Write-Host " WARN - Status $($response.StatusCode)" -ForegroundColor Yellow
  }
} catch {
  Write-Host " FAIL - Server not responding!" -ForegroundColor Red
  $errors++
}

# CHECK 8 — Live site responding
Write-Host "Checking live site..." -NoNewline
$r = curl.exe -s -o NUL -w "%{http_code}" https://learnova.optimus.com.my 2>$null
if ($r -eq "200") {
  Write-Host " OK" -ForegroundColor Green
} else {
  Write-Host " WARN - Status $r" -ForegroundColor Yellow
}

# CHECK 9 — No emoji in server .mjs files (prevents crash on Railway)
# Build range at runtime to avoid encoding issues in script file
Write-Host "Checking for emoji in server files..." -NoNewline
$emojiFound = $false
foreach ($mjs in @(Get-Item "C:\Learnova\server_updated.mjs")) {
  $content = [System.IO.File]::ReadAllText($mjs.FullName)
  foreach ($c in $content.ToCharArray()) {
    $cp = [int][char]$c
    if (($cp -ge 0x2600 -and $cp -le 0x2BFF) -or ($cp -ge 0xD800 -and $cp -le 0xDFFF)) {
      Write-Host " FAIL - Emoji/symbol found in $($mjs.Name)" -ForegroundColor Red
      $errors++
      $emojiFound = $true
      break
    }
  }
  if ($emojiFound) { break }
}
if (-not $emojiFound) { Write-Host " OK" -ForegroundColor Green }

Write-Host "`n══════════════════════════" -ForegroundColor Cyan
if ($errors -gt 0) {
  Write-Host "FAILED: $errors critical issue(s) found." -ForegroundColor Red
  Write-Host "Fix these before deploying!" -ForegroundColor Red
  exit 1
} else {
  Write-Host "ALL CHECKS PASSED. Safe to deploy." -ForegroundColor Green
  exit 0
}

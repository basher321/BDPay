# Builds the real (live) BDPay APK and saves it in D:\BDPay\live.
#   live\BDPay-latest.apk          always the newest build (give this one to testers)
#   live\BDPay-<yyyyMMdd-HHmm>.apk a dated copy of every build
#
# Run it yourself in a PowerShell window:
#   powershell -ExecutionPolicy Bypass -File D:\BDPay\ops\build_live_apk.ps1
# It asks for the Supabase anon (publishable) key. The key is passed to flutter as --dart-define only and is
# never written to a file. Never type the service_role or secret key here.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$supabaseUrl = 'https://ilidxuukjybrtvrkgjrg.supabase.co'

$anon = $env:BDPAY_ANON_KEY
if ([string]::IsNullOrWhiteSpace($anon)) {
    $anon = Read-Host 'Paste the Supabase anon (publishable) key'
}
$anon = $anon.Trim()
if ($anon -eq '' -or $anon -match 'service_role' -or $anon.StartsWith('sb_secret_')) {
    Write-Host 'Stopped: give the anon / publishable key, never the secret or service_role key.' -ForegroundColor Red
    exit 1
}

# Without the release signing file (production runbook step 8) a debug-signed test build is made instead.
$mode = if (Test-Path (Join-Path $root 'app\android\key.properties')) { 'release' } else { 'debug' }
if ($mode -eq 'debug') {
    Write-Host 'No android\key.properties: building a TEST apk (debug-signed), not for the Play Store.' -ForegroundColor Yellow
}

Push-Location (Join-Path $root 'app')
try {
    flutter build apk "--$mode" "--dart-define=SUPABASE_URL=$supabaseUrl" "--dart-define=SUPABASE_ANON_KEY=$anon"
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$built = Join-Path $root "app\build\app\outputs\flutter-apk\app-$mode.apk"
$liveDir = Join-Path $root 'live'
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
Copy-Item $built (Join-Path $liveDir "BDPay-$stamp.apk")
Copy-Item $built (Join-Path $liveDir 'BDPay-latest.apk') -Force

Write-Host ''
Write-Host "Done. Newest APK: $liveDir\BDPay-latest.apk" -ForegroundColor Green
Write-Host "Dated copy:       $liveDir\BDPay-$stamp.apk"

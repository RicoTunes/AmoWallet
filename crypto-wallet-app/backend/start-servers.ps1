# Crypto Wallet Backend Startup Script
# Starts Rust Crypto Server + Node.js API Server

Write-Host "Starting Crypto Wallet Backend with Rust Security..." -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# Navigate to backend directory
Set-Location $PSScriptRoot

# Check if Rust binary exists
$rustBinary = ".\rust\target\release\crypto_wallet_cli.exe"
if (-not (Test-Path $rustBinary)) {
    Write-Host "[!] Rust binary not found. Building..." -ForegroundColor Red
    Write-Host "   This will take a few minutes...`n"
    
    Set-Location rust
    cargo build --release
    Set-Location ..
    
    if (-not (Test-Path $rustBinary)) {
        Write-Host "[!] Rust build failed!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[OK] Rust binary found`n" -ForegroundColor Green

# Start Rust Crypto Server
Write-Host "Starting Rust Crypto Security Server..." -ForegroundColor Yellow
$rustJob = Start-Job -ScriptBlock {
    param($binaryPath)
    Set-Location (Split-Path $binaryPath)
    $env:RUST_HTTPS_PORT = "8443"
    & $binaryPath server
} -ArgumentList (Resolve-Path $rustBinary)

# Wait for Rust server to start
Start-Sleep -Seconds 2

# Check if Rust server is running
try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:8443/health" -Method Get -TimeoutSec 5
    if ($health.success -and $health.data.engine -eq "rust") {
        Write-Host "[OK] Rust Crypto Server running on port 8443`n" -ForegroundColor Green
    }
} catch {
    Write-Host "[WARN] Rust server health check failed: $_" -ForegroundColor Yellow
    Write-Host "   Continuing anyway...`n"
}

# Start Node.js API Server
Write-Host "Starting Node.js API Server..." -ForegroundColor Yellow
Start-Sleep -Seconds 1
node server.js

# Cleanup on exit
Write-Host "`nShutting down servers..." -ForegroundColor Red
Stop-Job $rustJob -ErrorAction SilentlyContinue
Remove-Job $rustJob -ErrorAction SilentlyContinue
Write-Host "[OK] Shutdown complete" -ForegroundColor Green

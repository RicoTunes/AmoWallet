# ========================================
# DATABASE SETUP GUIDE - Windows Native
# PostgreSQL + Redis Installation
# ========================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DATABASE SETUP GUIDE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Docker is not installed. You have 2 options:`n" -ForegroundColor Yellow

Write-Host "OPTION 1: Install Docker (RECOMMENDED - Easier)" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "1. Download Docker Desktop for Windows:" -ForegroundColor White
Write-Host "   https://www.docker.com/products/docker-desktop/`n" -ForegroundColor Cyan
Write-Host "2. Install Docker Desktop (requires restart)" -ForegroundColor White
Write-Host "3. After restart, run: .\setup-database-simple.ps1`n" -ForegroundColor White

Write-Host "`nOPTION 2: Install Natively on Windows" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

Write-Host "`n[PostgreSQL Installation]" -ForegroundColor Cyan
Write-Host "1. Download PostgreSQL 15 for Windows:" -ForegroundColor White
Write-Host "   https://www.postgresql.org/download/windows/`n" -ForegroundColor Cyan

Write-Host "2. Run the installer and configure:" -ForegroundColor White
Write-Host "   - Password: CryptoWallet2025" -ForegroundColor Gray
Write-Host "   - Port: 5432" -ForegroundColor Gray
Write-Host "   - Install as Windows Service: YES" -ForegroundColor Gray

Write-Host "`n3. After installation, open 'SQL Shell (psql)' and create database:" -ForegroundColor White
Write-Host "   CREATE DATABASE crypto_wallet;" -ForegroundColor Gray
Write-Host "   CREATE USER crypto_admin WITH PASSWORD 'CryptoWallet2025';" -ForegroundColor Gray
Write-Host "   GRANT ALL PRIVILEGES ON DATABASE crypto_wallet TO crypto_admin;" -ForegroundColor Gray

Write-Host "`n[Redis Installation]" -ForegroundColor Cyan
Write-Host "1. Download Redis for Windows:" -ForegroundColor White
Write-Host "   https://github.com/tporadowski/redis/releases`n" -ForegroundColor Cyan

Write-Host "2. Download Redis-x64-5.0.14.1.zip (or latest)" -ForegroundColor White
Write-Host "3. Extract to: C:\Redis" -ForegroundColor White
Write-Host "4. Open PowerShell as Administrator and run:" -ForegroundColor White
Write-Host "   cd C:\Redis" -ForegroundColor Gray
Write-Host "   .\redis-server.exe --service-install redis.windows.conf" -ForegroundColor Gray
Write-Host "   .\redis-server.exe --service-start" -ForegroundColor Gray

Write-Host "`n[Quick Redis Setup - No Service]" -ForegroundColor Yellow
Write-Host "If you don't want to install as service:" -ForegroundColor White
Write-Host "1. Extract Redis to C:\Redis" -ForegroundColor White
Write-Host "2. Open PowerShell and run:" -ForegroundColor White
Write-Host "   cd C:\Redis" -ForegroundColor Gray
Write-Host "   Start-Process -NoNewWindow .\redis-server.exe" -ForegroundColor Gray
Write-Host "3. Keep this window open (Redis running)" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AFTER INSTALLATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Run this command to update .env and run migrations:" -ForegroundColor White
Write-Host ".\finalize-database-setup.ps1`n" -ForegroundColor Cyan

# Create the finalize script
$finalizeScript = @'
# Finalize Database Setup

Write-Host "`nFinalizing database setup...`n" -ForegroundColor Cyan

# Update .env.production
$envFile = ".\.env.production"
if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw
    
    $dbUrl = "postgresql://crypto_admin:CryptoWallet2025@localhost:5432/crypto_wallet"
    $content = $content -replace 'DATABASE_URL=.*', "DATABASE_URL=$dbUrl"
    $content = $content -replace 'REDIS_URL=.*', "REDIS_URL=redis://localhost:6379"
    
    Set-Content -Path $envFile -Value $content -NoNewline
    Write-Host "Updated .env.production" -ForegroundColor Green
}

# Test PostgreSQL connection
Write-Host "`nTesting PostgreSQL connection..." -ForegroundColor Cyan
try {
    $env:PGPASSWORD = "CryptoWallet2025"
    $pgTest = psql -U crypto_admin -d crypto_wallet -c "SELECT version();" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "PostgreSQL: Connected!" -ForegroundColor Green
        
        # Run migrations
        Write-Host "`nRunning migrations..." -ForegroundColor Cyan
        $migrationFile = ".\migrations\002_revenue_tracking.sql"
        if (Test-Path $migrationFile) {
            psql -U crypto_admin -d crypto_wallet -f $migrationFile
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`nMigrations completed!" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "PostgreSQL: Not connected" -ForegroundColor Red
        Write-Host "Error: $pgTest" -ForegroundColor Yellow
    }
} catch {
    Write-Host "PostgreSQL: psql command not found" -ForegroundColor Red
    Write-Host "Add PostgreSQL bin folder to PATH" -ForegroundColor Yellow
}

# Test Redis
Write-Host "`nTesting Redis connection..." -ForegroundColor Cyan
try {
    if (Test-Path "C:\Redis\redis-cli.exe") {
        $redisTest = & "C:\Redis\redis-cli.exe" ping
        if ($redisTest -eq "PONG") {
            Write-Host "Redis: Connected!" -ForegroundColor Green
        } else {
            Write-Host "Redis: Not responding" -ForegroundColor Red
        }
    } else {
        Write-Host "Redis: redis-cli.exe not found at C:\Redis\" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Redis: Error testing connection" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Setup complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Start your server: node server.js" -ForegroundColor White
Write-Host "2. Test the system: .\test-monetization.ps1`n" -ForegroundColor White
'@

Set-Content -Path ".\finalize-database-setup.ps1" -Value $finalizeScript
Write-Host "Created finalize-database-setup.ps1" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Choose your installation method above" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Ask user what they want to do
Write-Host "What would you like to do?" -ForegroundColor White
Write-Host "1. Open Docker Desktop download page" -ForegroundColor Green
Write-Host "2. Open PostgreSQL download page" -ForegroundColor Yellow
Write-Host "3. Open Redis download page" -ForegroundColor Yellow
Write-Host "4. Skip - I'll install manually" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Enter your choice (1-4)"

switch ($choice) {
    "1" { Start-Process "https://www.docker.com/products/docker-desktop/" }
    "2" { Start-Process "https://www.postgresql.org/download/windows/" }
    "3" { Start-Process "https://github.com/tporadowski/redis/releases" }
    "4" { Write-Host "`nOK. Run .\finalize-database-setup.ps1 after installation.`n" -ForegroundColor Cyan }
}

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

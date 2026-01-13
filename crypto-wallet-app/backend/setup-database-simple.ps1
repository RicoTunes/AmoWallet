# Database Setup Script - Simple Version
# PostgreSQL + Redis using Docker

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DATABASE SETUP FOR CRYPTO WALLET" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test if Docker is available
Write-Host "Checking for Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker found: $dockerVersion`n" -ForegroundColor Green
    } else {
        Write-Host "`nDocker not found!" -ForegroundColor Red
        Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/`n" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "`nDocker not found!" -ForegroundColor Red
    Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/`n" -ForegroundColor Yellow
    exit 1
}

# Stop and remove existing containers
Write-Host "Cleaning up existing containers..." -ForegroundColor Yellow
docker stop crypto-postgres 2>$null | Out-Null
docker rm crypto-postgres 2>$null | Out-Null
docker stop crypto-redis 2>$null | Out-Null
docker rm crypto-redis 2>$null | Out-Null

# Create PostgreSQL container
Write-Host "`nSetting up PostgreSQL..." -ForegroundColor Cyan
$pgPassword = "CryptoWallet2025"

docker run -d `
    --name crypto-postgres `
    -e POSTGRES_DB=crypto_wallet `
    -e POSTGRES_USER=crypto_admin `
    -e POSTGRES_PASSWORD=$pgPassword `
    -p 5432:5432 `
    -v crypto-postgres-data:/var/lib/postgresql/data `
    postgres:15-alpine

if ($LASTEXITCODE -eq 0) {
    Write-Host "PostgreSQL container created!" -ForegroundColor Green
    Write-Host "  Database: crypto_wallet" -ForegroundColor Gray
    Write-Host "  Username: crypto_admin" -ForegroundColor Gray
    Write-Host "  Password: $pgPassword" -ForegroundColor Gray
    Write-Host "  Port: 5432" -ForegroundColor Gray
} else {
    Write-Host "Failed to create PostgreSQL container" -ForegroundColor Red
    exit 1
}

# Create Redis container
Write-Host "`nSetting up Redis..." -ForegroundColor Cyan

docker run -d `
    --name crypto-redis `
    -p 6379:6379 `
    -v crypto-redis-data:/data `
    redis:7-alpine `
    redis-server --appendonly yes

if ($LASTEXITCODE -eq 0) {
    Write-Host "Redis container created!" -ForegroundColor Green
    Write-Host "  Port: 6379" -ForegroundColor Gray
} else {
    Write-Host "Failed to create Redis container" -ForegroundColor Red
    exit 1
}

# Wait for databases to be ready
Write-Host "`nWaiting for databases to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

# Test connections
Write-Host "`nTesting connections..." -ForegroundColor Cyan

# Test PostgreSQL
$pgTest = docker exec crypto-postgres pg_isready -U crypto_admin 2>&1
if ($pgTest -like "*accepting connections*") {
    Write-Host "PostgreSQL: Connected!" -ForegroundColor Green
} else {
    Write-Host "PostgreSQL: Still starting (this is normal)..." -ForegroundColor Yellow
}

# Test Redis
$redisTest = docker exec crypto-redis redis-cli ping 2>&1
if ($redisTest -eq "PONG") {
    Write-Host "Redis: Connected!" -ForegroundColor Green
} else {
    Write-Host "Redis: Still starting (this is normal)..." -ForegroundColor Yellow
}

# Update .env.production
Write-Host "`nUpdating .env.production..." -ForegroundColor Cyan
$envFile = ".\.env.production"

if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw
    
    # Update DATABASE_URL
    $dbUrl = "postgresql://crypto_admin:$pgPassword@localhost:5432/crypto_wallet"
    $content = $content -replace 'DATABASE_URL=.*', "DATABASE_URL=$dbUrl"
    
    # Update REDIS_URL
    $content = $content -replace 'REDIS_URL=.*', "REDIS_URL=redis://localhost:6379"
    
    Set-Content -Path $envFile -Value $content -NoNewline
    Write-Host ".env.production updated!" -ForegroundColor Green
    Write-Host "  DATABASE_URL=$dbUrl" -ForegroundColor Gray
    Write-Host "  REDIS_URL=redis://localhost:6379" -ForegroundColor Gray
}

# Run migrations
Write-Host "`nRunning database migrations..." -ForegroundColor Cyan
$migrationFile = ".\migrations\002_revenue_tracking.sql"

if (Test-Path $migrationFile) {
    # Wait a bit more to ensure PostgreSQL is fully ready
    Start-Sleep -Seconds 3
    
    # Copy migration file to container
    docker cp $migrationFile crypto-postgres:/tmp/migration.sql | Out-Null
    
    # Run migration
    $migrationResult = docker exec crypto-postgres psql -U crypto_admin -d crypto_wallet -f /tmp/migration.sql 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nMigration completed successfully!" -ForegroundColor Green
        Write-Host "`nCreated tables:" -ForegroundColor Cyan
        Write-Host "  - revenue_transactions" -ForegroundColor White
        Write-Host "  - daily_revenue_summary" -ForegroundColor White
        Write-Host "  - user_activity_log" -ForegroundColor White
        Write-Host "  - security_events" -ForegroundColor White
    } else {
        Write-Host "`nMigration may have issues (check if tables already exist):" -ForegroundColor Yellow
        Write-Host $migrationResult -ForegroundColor Gray
    }
} else {
    Write-Host "Migration file not found: $migrationFile" -ForegroundColor Yellow
}

# Show status
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Docker containers running:" -ForegroundColor Green
docker ps --filter "name=crypto-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Start your server: node server.js" -ForegroundColor White
Write-Host "2. Test revenue system: .\test-monetization.ps1" -ForegroundColor White
Write-Host "3. Check admin dashboard: http://localhost:3000/api/admin/dashboard`n" -ForegroundColor White

Write-Host "To manage databases:" -ForegroundColor Yellow
Write-Host "  Stop: docker stop crypto-postgres crypto-redis" -ForegroundColor Gray
Write-Host "  Start: docker start crypto-postgres crypto-redis" -ForegroundColor Gray
Write-Host "  Remove: docker rm -f crypto-postgres crypto-redis`n" -ForegroundColor Gray

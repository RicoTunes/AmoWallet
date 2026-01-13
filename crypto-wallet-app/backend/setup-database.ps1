# ===================================
# DATABASE SETUP SCRIPT
# PostgreSQL + Redis Installation
# ===================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DATABASE SETUP FOR CRYPTO WALLET" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️  Warning: Not running as Administrator" -ForegroundColor Yellow
    Write-Host "Some operations may require elevated privileges`n" -ForegroundColor Yellow
}

# ===================================
# OPTION 1: Docker Installation (RECOMMENDED)
# ===================================

function Test-Docker {
    try {
        $dockerVersion = docker --version 2>$null
        return $true
    } catch {
        return $false
    }
}

function Install-DockerDatabases {
    Write-Host "`n📦 Installing databases using Docker...`n" -ForegroundColor Green
    
    # Check if Docker is installed
    if (-not (Test-Docker)) {
        Write-Host "❌ Docker is not installed!" -ForegroundColor Red
        Write-Host "`nPlease install Docker Desktop from:" -ForegroundColor Yellow
        Write-Host "https://www.docker.com/products/docker-desktop/`n" -ForegroundColor Cyan
        return $false
    }
    
    Write-Host "✓ Docker is installed" -ForegroundColor Green
    
    # Stop and remove existing containers if they exist
    Write-Host "`n🧹 Cleaning up existing containers..." -ForegroundColor Yellow
    docker stop crypto-postgres 2>$null
    docker rm crypto-postgres 2>$null
    docker stop crypto-redis 2>$null
    docker rm crypto-redis 2>$null
    
    # Create PostgreSQL container
    Write-Host "`n🐘 Setting up PostgreSQL..." -ForegroundColor Cyan
    $pgPassword = "CryptoWallet2025!"
    
    docker run -d `
        --name crypto-postgres `
        -e POSTGRES_DB=crypto_wallet `
        -e POSTGRES_USER=crypto_admin `
        -e POSTGRES_PASSWORD=$pgPassword `
        -p 5432:5432 `
        -v crypto-postgres-data:/var/lib/postgresql/data `
        postgres:15-alpine
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ PostgreSQL container created successfully!" -ForegroundColor Green
        Write-Host "  Database: crypto_wallet" -ForegroundColor Gray
        Write-Host "  Username: crypto_admin" -ForegroundColor Gray
        Write-Host "  Password: $pgPassword" -ForegroundColor Gray
        Write-Host "  Port: 5432" -ForegroundColor Gray
    } else {
        Write-Host "❌ Failed to create PostgreSQL container" -ForegroundColor Red
        return $false
    }
    
    # Create Redis container
    Write-Host "`n🔴 Setting up Redis..." -ForegroundColor Cyan
    
    docker run -d `
        --name crypto-redis `
        -p 6379:6379 `
        -v crypto-redis-data:/data `
        redis:7-alpine `
        redis-server --appendonly yes
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Redis container created successfully!" -ForegroundColor Green
        Write-Host "  Port: 6379" -ForegroundColor Gray
        Write-Host "  No password (localhost only)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Failed to create Redis container" -ForegroundColor Red
        return $false
    }
    
    # Wait for databases to be ready
    Write-Host "`n⏳ Waiting for databases to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    
    # Test connections
    Write-Host "`n🧪 Testing connections..." -ForegroundColor Cyan
    
    # Test PostgreSQL
    $pgTest = docker exec crypto-postgres pg_isready -U crypto_admin 2>$null
    if ($pgTest -like "*accepting connections*") {
        Write-Host "✓ PostgreSQL is ready!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  PostgreSQL may still be starting..." -ForegroundColor Yellow
    }
    
    # Test Redis
    $redisTest = docker exec crypto-redis redis-cli ping 2>$null
    if ($redisTest -eq "PONG") {
        Write-Host "✓ Redis is ready!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Redis may still be starting..." -ForegroundColor Yellow
    }
    
    # Update .env.production
    Write-Host "`n📝 Updating .env.production..." -ForegroundColor Cyan
    $envFile = ".\.env.production"
    
    if (Test-Path $envFile) {
        $content = Get-Content $envFile -Raw
        
        # Update DATABASE_URL
        $content = $content -replace 'DATABASE_URL=.*', "DATABASE_URL=postgresql://crypto_admin:$pgPassword@localhost:5432/crypto_wallet"
        
        # Update REDIS_URL
        $content = $content -replace 'REDIS_URL=.*', "REDIS_URL=redis://localhost:6379"
        
        Set-Content -Path $envFile -Value $content
        Write-Host "✓ .env.production updated!" -ForegroundColor Green
    }
    
    return $true
}

# ===================================
# OPTION 2: Windows Native Installation
# ===================================

function Install-NativeDatabases {
    Write-Host "`n📦 Native installation guide...`n" -ForegroundColor Green
    
    Write-Host "POSTGRESQL:" -ForegroundColor Cyan
    Write-Host "1. Download from: https://www.postgresql.org/download/windows/" -ForegroundColor White
    Write-Host "2. Run installer (PostgreSQL 15 recommended)" -ForegroundColor White
    Write-Host "3. During setup:" -ForegroundColor White
    Write-Host "   - Set password: CryptoWallet2025!" -ForegroundColor Gray
    Write-Host "   - Port: 5432 (default)" -ForegroundColor Gray
    Write-Host "   - Create database: crypto_wallet" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "REDIS:" -ForegroundColor Cyan
    Write-Host "1. Download from: https://github.com/tporadowski/redis/releases" -ForegroundColor White
    Write-Host "2. Extract to C:\Redis" -ForegroundColor White
    Write-Host "3. Run: redis-server.exe" -ForegroundColor White
    Write-Host "4. Keep it running in background" -ForegroundColor White
    Write-Host ""
    
    Write-Host "After installation, run this script again to test connections." -ForegroundColor Yellow
}

# ===================================
# DATABASE MIGRATION
# ===================================

function Run-Migrations {
    Write-Host "`n📊 Running database migrations...`n" -ForegroundColor Cyan
    
    $migrationFile = ".\migrations\002_revenue_tracking.sql"
    
    if (-not (Test-Path $migrationFile)) {
        Write-Host "❌ Migration file not found: $migrationFile" -ForegroundColor Red
        return $false
    }
    
    # Get connection string from .env.production
    $envFile = ".\.env.production"
    if (Test-Path $envFile) {
        $dbUrl = (Get-Content $envFile | Select-String "^DATABASE_URL=").ToString().Split('=')[1]
        
        if ($dbUrl -like "*YOUR*" -or $dbUrl -like "*placeholder*") {
            Write-Host "❌ Database URL not configured in .env.production" -ForegroundColor Red
            return $false
        }
        
        Write-Host "📁 Migration file: $migrationFile" -ForegroundColor Gray
        Write-Host "🔗 Database: $dbUrl`n" -ForegroundColor Gray
        
        # Run migration using docker exec (if using Docker)
        if (Test-Docker) {
            $dockerPs = docker ps --filter "name=crypto-postgres" --format "{{.Names}}" 2>$null
            if ($dockerPs -eq "crypto-postgres") {
                Write-Host "Running migration via Docker..." -ForegroundColor Yellow
                
                # Copy migration file to container
                docker cp $migrationFile crypto-postgres:/tmp/migration.sql
                
                # Run migration
                docker exec crypto-postgres psql -U crypto_admin -d crypto_wallet -f /tmp/migration.sql
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n✓ Migration completed successfully!" -ForegroundColor Green
                    Write-Host "`nCreated tables:" -ForegroundColor Cyan
                    Write-Host "  • revenue_transactions" -ForegroundColor White
                    Write-Host "  • daily_revenue_summary" -ForegroundColor White
                    Write-Host "  • user_activity_log" -ForegroundColor White
                    Write-Host "  • security_events" -ForegroundColor White
                    return $true
                } else {
                    Write-Host "`n❌ Migration failed!" -ForegroundColor Red
                    return $false
                }
            }
        }
        
        # Try using psql command (if installed locally)
        try {
            $env:PGPASSWORD = ($dbUrl -split ':')[2].Split('@')[0]
            psql $dbUrl -f $migrationFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n✓ Migration completed successfully!" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "psql command not found. Please use Docker option." -ForegroundColor Yellow
        }
        
        return $false
    }
    
    return $false
}

# ===================================
# TEST CONNECTIONS
# ===================================

function Test-Connections {
    Write-Host "`n🧪 Testing database connections...`n" -ForegroundColor Cyan
    
    $envFile = ".\.env.production"
    if (-not (Test-Path $envFile)) {
        Write-Host "❌ .env.production not found!" -ForegroundColor Red
        return
    }
    
    $content = Get-Content $envFile
    $dbUrl = ($content | Select-String "^DATABASE_URL=").ToString().Split('=', 2)[1]
    $redisUrl = ($content | Select-String "^REDIS_URL=").ToString().Split('=', 2)[1]
    
    # Test PostgreSQL
    Write-Host "PostgreSQL:" -ForegroundColor Cyan
    if (Test-Docker) {
        $pgStatus = docker exec crypto-postgres pg_isready -U crypto_admin 2>$null
        if ($pgStatus -like "*accepting connections*") {
            Write-Host "  ✓ Connected!" -ForegroundColor Green
            Write-Host "  URL: $dbUrl" -ForegroundColor Gray
        } else {
            Write-Host "  ❌ Not connected" -ForegroundColor Red
        }
    } else {
        Write-Host "  URL: $dbUrl" -ForegroundColor Gray
        Write-Host "  ⚠️  Docker not available - cannot test" -ForegroundColor Yellow
    }
    
    # Test Redis
    Write-Host "`nRedis:" -ForegroundColor Cyan
    if (Test-Docker) {
        $redisStatus = docker exec crypto-redis redis-cli ping 2>$null
        if ($redisStatus -eq "PONG") {
            Write-Host "  ✓ Connected!" -ForegroundColor Green
            Write-Host "  URL: $redisUrl" -ForegroundColor Gray
        } else {
            Write-Host "  ❌ Not connected" -ForegroundColor Red
        }
    } else {
        Write-Host "  URL: $redisUrl" -ForegroundColor Gray
        Write-Host "  ⚠️  Docker not available - cannot test" -ForegroundColor Yellow
    }
}

# ===================================
# MAIN MENU
# ===================================

Write-Host "What would you like to do?`n" -ForegroundColor White
Write-Host "1. Install using Docker (RECOMMENDED - Fast and Easy)" -ForegroundColor Green
Write-Host "2. View native installation guide (Windows native)" -ForegroundColor Yellow
Write-Host "3. Run database migrations" -ForegroundColor Cyan
Write-Host "4. Test connections" -ForegroundColor Magenta
Write-Host "5. View current configuration" -ForegroundColor Gray
Write-Host "0. Exit" -ForegroundColor Red
Write-Host ""

$choice = Read-Host "Enter your choice (1-5)"

switch ($choice) {
    "1" {
        $success = Install-DockerDatabases
        if ($success) {
            Write-Host "`n🎉 Databases installed successfully!" -ForegroundColor Green
            Write-Host "`nNext steps:" -ForegroundColor Cyan
            Write-Host "1. Run migrations: .\setup-database.ps1 (choose option 3)" -ForegroundColor White
            Write-Host "2. Start your server: node server.js" -ForegroundColor White
            Write-Host "3. Check admin dashboard: http://localhost:3000/api/admin/dashboard`n" -ForegroundColor White
            
            # Ask if user wants to run migrations now
            $runMigrations = Read-Host "`nRun migrations now? (y/n)"
            if ($runMigrations -eq "y" -or $runMigrations -eq "Y") {
                Start-Sleep -Seconds 3
                Run-Migrations
            }
        }
    }
    "2" {
        Install-NativeDatabases
    }
    "3" {
        Run-Migrations
    }
    "4" {
        Test-Connections
    }
    "5" {
        Write-Host "`nCurrent Configuration:" -ForegroundColor Cyan
        Write-Host "=====================`n" -ForegroundColor Cyan
        
        if (Test-Path ".\.env.production") {
            $content = Get-Content ".\.env.production"
            $dbUrl = ($content | Select-String "^DATABASE_URL=").ToString()
            $redisUrl = ($content | Select-String "^REDIS_URL=").ToString()
            
            Write-Host $dbUrl -ForegroundColor White
            Write-Host $redisUrl -ForegroundColor White
            
            # Check Docker containers
            if (Test-Docker) {
                Write-Host "`nDocker Containers:" -ForegroundColor Cyan
                docker ps --filter "name=crypto-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            }
        } else {
            Write-Host "❌ .env.production not found" -ForegroundColor Red
        }
    }
    "0" {
        Write-Host "`nGoodbye!" -ForegroundColor Cyan
        exit
    }
    default {
        Write-Host "`n❌ Invalid choice!" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Setup script completed!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

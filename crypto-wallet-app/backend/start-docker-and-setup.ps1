# Check and Start Docker

Write-Host "`nChecking Docker status...`n" -ForegroundColor Cyan

# Check if Docker Desktop is running
$dockerProcess = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue

if (-not $dockerProcess) {
    Write-Host "Docker Desktop is not running. Starting it..." -ForegroundColor Yellow
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
    Write-Host "Waiting for Docker to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

# Test Docker
Write-Host "Testing Docker connection..." -ForegroundColor Cyan
$retries = 0
$maxRetries = 12

while ($retries -lt $maxRetries) {
    try {
        $result = docker ps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker is ready!" -ForegroundColor Green
            docker ps
            Write-Host "`nDocker is working! Running database setup...`n" -ForegroundColor Green
            
            # Run the setup script
            & ".\setup-database-simple.ps1"
            exit 0
        }
    } catch {}
    
    $retries++
    Write-Host "Waiting for Docker to be ready... ($retries/$maxRetries)" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

Write-Host "`nDocker is not responding after $($maxRetries * 5) seconds." -ForegroundColor Red
Write-Host "`nPlease:" -ForegroundColor Yellow
Write-Host "1. Make sure Docker Desktop is running (check system tray)" -ForegroundColor White
Write-Host "2. Wait for 'Docker Desktop is running' message" -ForegroundColor White
Write-Host "3. Then run: .\setup-database-simple.ps1`n" -ForegroundColor White

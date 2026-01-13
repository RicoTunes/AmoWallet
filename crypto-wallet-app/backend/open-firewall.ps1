# Open Windows Firewall for Crypto Wallet Backend
# Run this script as Administrator (Right-click -> Run as Administrator)

Write-Host "Opening Windows Firewall for port 3000..." -ForegroundColor Green

# Add firewall rule for port 3000
netsh advfirewall firewall add rule name="Crypto Wallet Backend - Port 3000" dir=in action=allow protocol=TCP localport=3000

Write-Host ""
Write-Host "Firewall rule added successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Now test from your phone's browser:" -ForegroundColor Yellow
Write-Host "http://172.20.10.5:3000/health" -ForegroundColor Cyan
Write-Host ""
Write-Host "You should see: {`"status`":`"OK`"}" -ForegroundColor Yellow
Write-Host ""

Pause

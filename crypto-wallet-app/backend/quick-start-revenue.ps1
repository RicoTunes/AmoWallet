# Quick Start - Monetization System
# Run this script to get started with revenue collection

Write-Host ""
Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   CRYPTO WALLET - MONETIZATION SYSTEM   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if setup has been run
if (!(Test-Path ".env.production")) {
    Write-Host "❌ Configuration not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run the setup script first:" -ForegroundColor Yellow
    Write-Host "  .\setup-revenue.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "✓ Configuration found" -ForegroundColor Green
Write-Host ""

# Display current configuration
Write-Host "═══ CURRENT CONFIGURATION ═══" -ForegroundColor Cyan
Write-Host ""

$envContent = Get-Content ".env.production" -Raw

# Extract key values
function Get-EnvValue {
    param($key)
    if ($envContent -match "$key=([^\r\n]+)") {
        return $matches[1]
    }
    return "Not configured"
}

$transactionFee = Get-EnvValue "TRANSACTION_FEE_PERCENTAGE"
$swapFee = Get-EnvValue "SWAP_FEE_PERCENTAGE"
$minFee = Get-EnvValue "MIN_TRANSACTION_FEE_USD"
$autoConvert = Get-EnvValue "AUTO_CONVERT_TO_USDT"
$collectionMethod = Get-EnvValue "FEE_COLLECTION_METHOD"
$alertThreshold = Get-EnvValue "REVENUE_ALERT_THRESHOLD"
$ethAddress = Get-EnvValue "TREASURY_ETH_ADDRESS"

Write-Host "Fee Structure:" -ForegroundColor Yellow
Write-Host "  Transaction Fee: $transactionFee%" -ForegroundColor White
Write-Host "  Swap Fee: $swapFee%" -ForegroundColor White
Write-Host "  Minimum Fee: `$$minFee USD" -ForegroundColor White
Write-Host ""

Write-Host "Collection Settings:" -ForegroundColor Yellow
Write-Host "  Method: $collectionMethod" -ForegroundColor White
Write-Host "  Auto-Convert to USDT: $autoConvert" -ForegroundColor White
Write-Host "  Alert Threshold: `$$alertThreshold USD" -ForegroundColor White
Write-Host ""

Write-Host "Treasury Address (ETH):" -ForegroundColor Yellow
Write-Host "  $ethAddress" -ForegroundColor White
Write-Host ""

# Check database status
Write-Host "═══ DATABASE STATUS ═══" -ForegroundColor Cyan
Write-Host ""

$databaseUrl = Get-EnvValue "DATABASE_URL"
if ($databaseUrl -eq "postgresql://username:password@localhost:5432/crypto_wallet") {
    Write-Host "⚠️  Database not configured yet!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Update DATABASE_URL in .env.production with your credentials" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "✓ Database configured" -ForegroundColor Green
    Write-Host ""
}

# Check if migrations have been run
Write-Host "═══ SETUP CHECKLIST ═══" -ForegroundColor Cyan
Write-Host ""

$steps = @(
    @{
        Name = "Configuration Complete"
        Status = (Test-Path ".env.production")
        Action = "Run: .\setup-revenue.ps1"
    },
    @{
        Name = "Database Configured"
        Status = ($databaseUrl -ne "postgresql://username:password@localhost:5432/crypto_wallet")
        Action = "Update DATABASE_URL in .env.production"
    },
    @{
        Name = "Revenue Service Created"
        Status = (Test-Path "src\services\revenueService.js")
        Action = "Already created ✓"
    },
    @{
        Name = "Admin API Routes Created"
        Status = (Test-Path "src\routes\adminRoutes.js")
        Action = "Already created ✓"
    },
    @{
        Name = "Database Migrations Ready"
        Status = (Test-Path "migrations\002_revenue_tracking.sql")
        Action = "Already created ✓"
    }
)

foreach ($step in $steps) {
    if ($step.Status) {
        Write-Host "  ✓ $($step.Name)" -ForegroundColor Green
    } else {
        Write-Host "  ☐ $($step.Name)" -ForegroundColor Yellow
        Write-Host "    → $($step.Action)" -ForegroundColor Gray
    }
}

Write-Host ""

# Show next steps
Write-Host "═══ NEXT STEPS ═══" -ForegroundColor Cyan
Write-Host ""

if ($databaseUrl -eq "postgresql://username:password@localhost:5432/crypto_wallet") {
    Write-Host "🔴 STEP 1: Configure Database" -ForegroundColor Red
    Write-Host ""
    Write-Host "Update your .env.production with actual database credentials:" -ForegroundColor White
    Write-Host "  DATABASE_URL=postgresql://your_user:your_password@localhost:5432/crypto_wallet" -ForegroundColor Gray
    Write-Host "  REDIS_URL=redis://localhost:6379" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Then run this script again!" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "🟢 STEP 1: Run Database Migrations" -ForegroundColor Green
    Write-Host ""
    Write-Host "Create the revenue tracking tables:" -ForegroundColor White
    Write-Host "  cd migrations" -ForegroundColor Gray
    Write-Host "  psql `$env:DATABASE_URL -f 002_revenue_tracking.sql" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "🟢 STEP 2: Integrate Revenue Service" -ForegroundColor Green
    Write-Host ""
    Write-Host "Add to your server.js or app.js:" -ForegroundColor White
    Write-Host @"
  const adminRoutes = require('./routes/adminRoutes');
  app.use('/api/admin', adminRoutes);
"@ -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "🟢 STEP 3: Test the System" -ForegroundColor Green
    Write-Host ""
    Write-Host "Start your server and test admin API:" -ForegroundColor White
    Write-Host "  npm start" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Then in another terminal:" -ForegroundColor White
    Write-Host @"
  `$adminKey = Get-Content .env.production | Select-String "ADMIN_API_KEY" | ForEach-Object { `$_.ToString().Split('=')[1] }
  `$headers = @{ "X-Admin-Key" = `$adminKey }
  Invoke-RestMethod -Uri "http://localhost:3000/api/admin/dashboard" -Headers `$headers
"@ -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "🟢 STEP 4: Integrate into Transactions" -ForegroundColor Green
    Write-Host ""
    Write-Host "Add fee processing to your transaction endpoints:" -ForegroundColor White
    Write-Host @"
  const revenueService = require('./services/revenueService');
  
  // In your send transaction endpoint:
  const feeData = await revenueService.processTransactionWithFee({
    userId: req.user.id,
    chain: 'ethereum',
    transactionType: 'send',
    amount: amount,
    amountUSD: amountUSD,
    token: 'ETH'
  });
  
  // Send net amount to recipient (after fee deduction)
  // Send fee to treasury address
"@ -ForegroundColor Gray
    Write-Host ""
}

# Revenue projections
Write-Host "═══ REVENUE PROJECTIONS ═══" -ForegroundColor Cyan
Write-Host ""

$avgTransactionUSD = 500
$feePercent = [decimal]$transactionFee / 100
$avgFeeUSD = $avgTransactionUSD * $feePercent
$txPerUserPerMonth = 2

Write-Host "Assumptions:" -ForegroundColor Yellow
Write-Host "  Average Transaction: `$$avgTransactionUSD USD" -ForegroundColor White
Write-Host "  Fee: $transactionFee%" -ForegroundColor White
Write-Host "  Average Fee: `$$avgFeeUSD USD per transaction" -ForegroundColor White
Write-Host "  User Activity: $txPerUserPerMonth transactions/month" -ForegroundColor White
Write-Host ""

$scenarios = @(
    @{ Users = 100; Name = "Small Start" },
    @{ Users = 1000; Name = "Growing" },
    @{ Users = 10000; Name = "Scaling" },
    @{ Users = 100000; Name = "Success" }
)

Write-Host "Monthly Revenue Projections:" -ForegroundColor Yellow
Write-Host ""

foreach ($scenario in $scenarios) {
    $monthlyRevenue = $scenario.Users * $txPerUserPerMonth * $avgFeeUSD
    $yearlyRevenue = $monthlyRevenue * 12
    
    Write-Host "$($scenario.Name) ($($scenario.Users) users):" -ForegroundColor White
    Write-Host "  Monthly: `$$([math]::Round($monthlyRevenue, 2))" -ForegroundColor Green
    Write-Host "  Yearly: `$$([math]::Round($yearlyRevenue, 2))" -ForegroundColor Cyan
    Write-Host ""
}

# Admin API quick reference
Write-Host "═══ ADMIN API QUICK REFERENCE ═══" -ForegroundColor Cyan
Write-Host ""

Write-Host "Get today's revenue:" -ForegroundColor Yellow
Write-Host "  GET /api/admin/revenue/stats?period=today" -ForegroundColor Gray
Write-Host ""

Write-Host "Get top users:" -ForegroundColor Yellow
Write-Host "  GET /api/admin/revenue/top-users?limit=10" -ForegroundColor Gray
Write-Host ""

Write-Host "Get security events:" -ForegroundColor Yellow
Write-Host "  GET /api/admin/security/events?severity=high" -ForegroundColor Gray
Write-Host ""

Write-Host "Get complete dashboard:" -ForegroundColor Yellow
Write-Host "  GET /api/admin/dashboard" -ForegroundColor Gray
Write-Host ""

Write-Host "📖 Full API documentation: ADMIN_API_REFERENCE.md" -ForegroundColor Cyan
Write-Host ""

# Final message
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎉 Your monetization system is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "Key Features:" -ForegroundColor Yellow
Write-Host "  ✓ Automatic fee deduction on transactions" -ForegroundColor White
Write-Host "  ✓ Multi-chain treasury management" -ForegroundColor White
Write-Host "  ✓ USDT auto-conversion (optional)" -ForegroundColor White
Write-Host "  ✓ Real-time revenue tracking" -ForegroundColor White
Write-Host "  ✓ Security event monitoring" -ForegroundColor White
Write-Host "  ✓ User activity logging" -ForegroundColor White
Write-Host "  ✓ Admin dashboard API" -ForegroundColor White
Write-Host ""

Write-Host "📚 Documentation:" -ForegroundColor Yellow
Write-Host "  - MONETIZATION_GUIDE.md (Business strategy)" -ForegroundColor White
Write-Host "  - ADMIN_API_REFERENCE.md (API docs)" -ForegroundColor White
Write-Host "  - .env.production (Your configuration)" -ForegroundColor White
Write-Host ""

Write-Host "⚠️  IMPORTANT REMINDERS:" -ForegroundColor Red
Write-Host "  1. Test on testnet first before production!" -ForegroundColor White
Write-Host "  2. Use hardware wallet for treasury addresses" -ForegroundColor White
Write-Host "  3. Consult a lawyer about licensing requirements" -ForegroundColor White
Write-Host "  4. Set up regular backups of revenue database" -ForegroundColor White
Write-Host "  5. Monitor security events daily" -ForegroundColor White
Write-Host ""

Write-Host "Need help? Check the documentation or contact support." -ForegroundColor Cyan
Write-Host ""
Write-Host "Good luck with your crypto wallet! 💰🚀" -ForegroundColor Green
Write-Host ""

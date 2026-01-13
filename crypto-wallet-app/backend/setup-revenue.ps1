# Revenue System Quick Setup Script
# This script helps you configure the monetization system

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Crypto Wallet Revenue Setup  " -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env.production exists
$envFile = ".env.production"
if (!(Test-Path $envFile)) {
    Write-Host "Creating .env.production file..." -ForegroundColor Yellow
    Copy-Item ".env.example" $envFile -ErrorAction SilentlyContinue
}

Write-Host "Let's configure your revenue system!" -ForegroundColor Green
Write-Host ""

# Step 1: Fee Configuration
Write-Host "=== STEP 1: Fee Configuration ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recommended fee structure:" -ForegroundColor Yellow
Write-Host "  - Transaction Fee: 0.5% (balanced)" -ForegroundColor Gray
Write-Host "  - Swap Fee: 1.0% (standard for DEX)" -ForegroundColor Gray
Write-Host "  - Minimum Fee: `$0.50 USD (prevents dust)" -ForegroundColor Gray
Write-Host ""

$transactionFee = Read-Host "Enter transaction fee percentage (default: 0.5)"
if ([string]::IsNullOrWhiteSpace($transactionFee)) { $transactionFee = "0.5" }

$swapFee = Read-Host "Enter swap fee percentage (default: 1.0)"
if ([string]::IsNullOrWhiteSpace($swapFee)) { $swapFee = "1.0" }

$minFee = Read-Host "Enter minimum fee in USD (default: 0.50)"
if ([string]::IsNullOrWhiteSpace($minFee)) { $minFee = "0.50" }

Write-Host ""
Write-Host "✓ Fee configuration set:" -ForegroundColor Green
Write-Host "  Transaction: $transactionFee%" -ForegroundColor Gray
Write-Host "  Swap: $swapFee%" -ForegroundColor Gray
Write-Host "  Minimum: `$$minFee USD" -ForegroundColor Gray
Write-Host ""

# Step 2: Treasury Addresses
Write-Host "=== STEP 2: Treasury Wallet Addresses ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Use hardware wallet addresses (Ledger/Trezor)" -ForegroundColor Red
Write-Host "NEVER share your private keys!" -ForegroundColor Red
Write-Host ""
Write-Host "Enter wallet addresses where you want to receive profits:" -ForegroundColor Yellow
Write-Host ""

$ethAddress = Read-Host "Ethereum Address (0x...)"
$btcAddress = Read-Host "Bitcoin Address (bc1... or 1...)"
$polygonAddress = Read-Host "Polygon Address (0x...)"
$bscAddress = Read-Host "BSC Address (0x...)"
$usdtAddress = Read-Host "USDT Receiving Address (0x...)"

Write-Host ""
Write-Host "✓ Treasury addresses configured" -ForegroundColor Green
Write-Host ""

# Step 3: USDT Conversion
Write-Host "=== STEP 3: USDT Auto-Conversion ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Do you want fees automatically converted to USDT?" -ForegroundColor Yellow
Write-Host "  YES: Stable income, no volatility risk" -ForegroundColor Gray
Write-Host "  NO: Keep fees in original crypto (ETH, BTC, etc.)" -ForegroundColor Gray
Write-Host ""

$autoConvertChoice = Read-Host "Auto-convert to USDT? (Y/N, default: Y)"
$autoConvert = if ($autoConvertChoice -eq "N" -or $autoConvertChoice -eq "n") { "false" } else { "true" }

Write-Host ""
Write-Host "✓ USDT conversion: $autoConvert" -ForegroundColor Green
Write-Host ""

# Step 4: Collection Method
Write-Host "=== STEP 4: Fee Collection Method ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Choose how to collect fees:" -ForegroundColor Yellow
Write-Host "  1. DEDUCTION (Recommended) - Deduct fee before sending to recipient" -ForegroundColor Gray
Write-Host "  2. SEPARATE - Charge fee as separate transaction" -ForegroundColor Gray
Write-Host "  3. USDT_CONVERSION - Convert fee to USDT then send" -ForegroundColor Gray
Write-Host ""

$methodChoice = Read-Host "Enter choice (1, 2, or 3, default: 1)"
$collectionMethod = switch ($methodChoice) {
    "2" { "separate" }
    "3" { "usdt_conversion" }
    default { "deduction" }
}

Write-Host ""
Write-Host "✓ Collection method: $collectionMethod" -ForegroundColor Green
Write-Host ""

# Step 5: Alerts Configuration
Write-Host "=== STEP 5: Alert System ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Get instant notifications on your phone!" -ForegroundColor Yellow
Write-Host ""
Write-Host "To set up Telegram bot:" -ForegroundColor Gray
Write-Host "  1. Open Telegram and search for @BotFather" -ForegroundColor Gray
Write-Host "  2. Send: /newbot" -ForegroundColor Gray
Write-Host "  3. Follow instructions to create your bot" -ForegroundColor Gray
Write-Host "  4. Copy the bot token" -ForegroundColor Gray
Write-Host "  5. Start a chat with your bot" -ForegroundColor Gray
Write-Host "  6. Get your chat ID from @userinfobot" -ForegroundColor Gray
Write-Host ""

$setupTelegram = Read-Host "Do you want to set up Telegram alerts now? (Y/N)"
$telegramToken = ""
$telegramChatId = ""

if ($setupTelegram -eq "Y" -or $setupTelegram -eq "y") {
    $telegramToken = Read-Host "Enter your Telegram bot token"
    $telegramChatId = Read-Host "Enter your Telegram chat ID"
    Write-Host ""
    Write-Host "✓ Telegram alerts configured" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "⊙ Telegram alerts skipped (you can set up later)" -ForegroundColor Yellow
}

Write-Host ""

# Step 6: Alert Threshold
Write-Host "=== STEP 6: Alert Threshold ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Get notified when daily revenue reaches a threshold" -ForegroundColor Yellow
Write-Host ""

$alertThreshold = Read-Host "Enter alert threshold in USD (default: 1000)"
if ([string]::IsNullOrWhiteSpace($alertThreshold)) { $alertThreshold = "1000" }

Write-Host ""
Write-Host "✓ Alert threshold: `$$alertThreshold USD" -ForegroundColor Green
Write-Host ""

# Step 7: Admin API Key
Write-Host "=== STEP 7: Admin API Security ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Generating secure admin API key..." -ForegroundColor Yellow

# Generate random admin key
$adminKey = [System.Guid]::NewGuid().ToString() + [System.Guid]::NewGuid().ToString().Replace("-", "")

Write-Host ""
Write-Host "✓ Admin API key generated" -ForegroundColor Green
Write-Host "  Save this key securely - you'll need it to access admin endpoints!" -ForegroundColor Red
Write-Host "  Key: $adminKey" -ForegroundColor Yellow
Write-Host ""

# Write to .env.production
Write-Host "=== Writing Configuration ===" -ForegroundColor Cyan
Write-Host ""

$envContent = @"
# ===================================
# REVENUE SYSTEM CONFIGURATION
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ===================================

# Fee Configuration
TRANSACTION_FEE_PERCENTAGE=$transactionFee
SWAP_FEE_PERCENTAGE=$swapFee
MIN_TRANSACTION_FEE_USD=$minFee

# Treasury Wallet Addresses (PROFIT DESTINATIONS)
TREASURY_ETH_ADDRESS=$ethAddress
TREASURY_BTC_ADDRESS=$btcAddress
TREASURY_POLYGON_ADDRESS=$polygonAddress
TREASURY_BSC_ADDRESS=$bscAddress
TREASURY_USDT_ADDRESS=$usdtAddress

# Collection Settings
FEE_COLLECTION_METHOD=$collectionMethod
AUTO_CONVERT_TO_USDT=$autoConvert
ENABLE_REVENUE_TRACKING=true

# Alert Configuration
REVENUE_ALERT_THRESHOLD=$alertThreshold
"@

if (![string]::IsNullOrWhiteSpace($telegramToken)) {
    $envContent += @"

TELEGRAM_BOT_TOKEN=$telegramToken
TELEGRAM_CHAT_ID=$telegramChatId
ENABLE_TELEGRAM_ALERTS=true
"@
}

$envContent += @"

# Admin API Security
ADMIN_API_KEY=$adminKey

# Database Configuration (UPDATE WITH YOUR CREDENTIALS)
DATABASE_URL=postgresql://username:password@localhost:5432/crypto_wallet
REDIS_URL=redis://localhost:6379

# ===================================
# IMPORTANT: Update DATABASE_URL with your actual credentials!
# ===================================
"@

Add-Content -Path $envFile -Value $envContent

Write-Host "✓ Configuration written to .env.production" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your revenue system is configured with:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Fees:" -ForegroundColor Cyan
Write-Host "    - Transactions: $transactionFee%" -ForegroundColor Gray
Write-Host "    - Swaps: $swapFee%" -ForegroundColor Gray
Write-Host "    - Minimum: `$$minFee USD" -ForegroundColor Gray
Write-Host ""
Write-Host "  Collection:" -ForegroundColor Cyan
Write-Host "    - Method: $collectionMethod" -ForegroundColor Gray
Write-Host "    - USDT Conversion: $autoConvert" -ForegroundColor Gray
Write-Host ""
Write-Host "  Treasury Addresses:" -ForegroundColor Cyan
Write-Host "    - Ethereum: $ethAddress" -ForegroundColor Gray
Write-Host "    - Bitcoin: $btcAddress" -ForegroundColor Gray
Write-Host "    - Polygon: $polygonAddress" -ForegroundColor Gray
Write-Host "    - BSC: $bscAddress" -ForegroundColor Gray
Write-Host "    - USDT: $usdtAddress" -ForegroundColor Gray
Write-Host ""
Write-Host "  Alerts:" -ForegroundColor Cyan
Write-Host "    - Threshold: `$$alertThreshold USD" -ForegroundColor Gray
if (![string]::IsNullOrWhiteSpace($telegramToken)) {
    Write-Host "    - Telegram: Enabled ✓" -ForegroundColor Gray
} else {
    Write-Host "    - Telegram: Not configured" -ForegroundColor Gray
}
Write-Host ""

# Next steps
Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. UPDATE DATABASE CREDENTIALS in .env.production" -ForegroundColor Yellow
Write-Host "   Current: postgresql://username:password@localhost:5432/crypto_wallet" -ForegroundColor Gray
Write-Host ""
Write-Host "2. INSTALL DATABASE:" -ForegroundColor Yellow
Write-Host "   npm run db:setup" -ForegroundColor Gray
Write-Host ""
Write-Host "3. RUN DATABASE MIGRATIONS:" -ForegroundColor Yellow
Write-Host "   npm run migrate" -ForegroundColor Gray
Write-Host ""
Write-Host "4. INTEGRATE REVENUE SERVICE:" -ForegroundColor Yellow
Write-Host "   The revenue service is ready in src/services/revenueService.js" -ForegroundColor Gray
Write-Host "   Next: Integrate into transaction endpoints" -ForegroundColor Gray
Write-Host ""
Write-Host "5. TEST ON TESTNET:" -ForegroundColor Yellow
Write-Host "   npm run test:revenue" -ForegroundColor Gray
Write-Host ""
Write-Host "6. ACCESS ADMIN DASHBOARD:" -ForegroundColor Yellow
Write-Host "   GET http://your-server/api/admin/dashboard" -ForegroundColor Gray
Write-Host "   Header: X-Admin-Key: $adminKey" -ForegroundColor Gray
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎉 Your crypto wallet will now generate revenue on every transaction!" -ForegroundColor Green
Write-Host "💰 Profits will be sent to your treasury addresses automatically" -ForegroundColor Green
Write-Host ""
Write-Host "Questions? Check MONETIZATION_GUIDE.md for detailed information" -ForegroundColor Yellow
Write-Host ""
Write-Host "IMPORTANT: Consult a crypto lawyer about licensing requirements!" -ForegroundColor Red
Write-Host ""

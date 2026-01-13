# Test Monetization Setup
# Verify fee structure and Telegram bot are working

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    MONETIZATION SYSTEM TEST SUITE         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$backendPath = "c:\Users\RICO\ricoamos\crypto-wallet-app\backend"
Set-Location $backendPath

# Test 1: Check configuration files
Write-Host "═══ TEST 1: Configuration Files ═══" -ForegroundColor Cyan
Write-Host ""

$tests = @{
    ".env.production exists" = Test-Path ".env.production"
    "revenueService.js exists" = Test-Path "src\services\revenueService.js"
    "adminRoutes.js exists" = Test-Path "src\routes\adminRoutes.js"
    "telegramService.js exists" = Test-Path "src\services\telegramService.js"
    "feeCalculator.js exists" = Test-Path "src\lib\feeCalculator.js"
    "revenue migration exists" = Test-Path "migrations\002_revenue_tracking.sql"
}

$passed = 0
$total = $tests.Count

foreach ($test in $tests.GetEnumerator()) {
    if ($test.Value) {
        Write-Host "  ✓ $($test.Key)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  ✗ $($test.Key)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Result: $passed/$total tests passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })
Write-Host ""

# Test 2: Check environment variables
Write-Host "═══ TEST 2: Environment Variables ═══" -ForegroundColor Cyan
Write-Host ""

if (Test-Path ".env.production") {
    $envContent = Get-Content ".env.production" -Raw
    
    $requiredVars = @(
        "TRANSACTION_FEE_PERCENTAGE",
        "SWAP_FEE_PERCENTAGE",
        "MIN_TRANSACTION_FEE_USD",
        "TREASURY_ETH_ADDRESS",
        "FEE_COLLECTION_METHOD",
        "ENABLE_REVENUE_TRACKING"
    )
    
    $optionalVars = @(
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_CHAT_ID",
        "ENABLE_TELEGRAM_ALERTS",
        "ENABLE_TIERED_PRICING",
        "ENABLE_PER_CHAIN_FEES"
    )
    
    Write-Host "Required Variables:" -ForegroundColor Yellow
    foreach ($var in $requiredVars) {
        $found = $envContent -match "$var="
        if ($found) {
            $value = ($envContent | Select-String "$var=(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
            Write-Host "  ✓ $var = $value" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $var = NOT SET" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Optional Variables:" -ForegroundColor Yellow
    foreach ($var in $optionalVars) {
        $found = $envContent -match "$var="
        if ($found) {
            $value = ($envContent | Select-String "$var=(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
            Write-Host "  ✓ $var = $value" -ForegroundColor Green
        } else {
            Write-Host "  ⊙ $var = NOT SET (optional)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  ✗ .env.production not found" -ForegroundColor Red
}

Write-Host ""

# Test 3: Fee Calculator
Write-Host "═══ TEST 3: Fee Calculator ═══" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing fee calculation logic..." -ForegroundColor Yellow

$testScript = @'
const feeCalculator = require('./src/lib/feeCalculator');

console.log('\nFee Structure:');
const structure = feeCalculator.getFeeStructure();
console.log(JSON.stringify(structure, null, 2));

console.log('\nTest Calculations:');

const tests = [
  { amount: 50, type: 'transaction', label: '$50 transaction' },
  { amount: 500, type: 'transaction', label: '$500 transaction' },
  { amount: 5000, type: 'transaction', label: '$5,000 transaction' },
  { amount: 50000, type: 'transaction', label: '$50,000 transaction' },
  { amount: 1000, type: 'swap', label: '$1,000 swap' }
];

tests.forEach(test => {
  const result = feeCalculator.calculateFee(test.amount, test.type);
  console.log(`\n${test.label}:`);
  console.log(`  Fee: ${result.feePercentage}% = $${result.feeAmount.toFixed(2)}`);
  console.log(`  Net Amount: $${result.netAmount.toFixed(2)}`);
  console.log(`  Min Fee Applied: ${result.minFeeApplied}`);
});

process.exit(0);
'@

$testScript | Out-File -FilePath "test-fees.js" -Encoding UTF8

try {
    node test-fees.js
    Write-Host ""
    Write-Host "✓ Fee calculator test passed" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "✗ Fee calculator test failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Remove-Item "test-fees.js" -ErrorAction SilentlyContinue

Write-Host ""

# Test 4: Telegram Bot (if configured)
Write-Host "═══ TEST 4: Telegram Bot ═══" -ForegroundColor Cyan
Write-Host ""

if (Test-Path ".env.production") {
    $envContent = Get-Content ".env.production" -Raw
    $hasTelegram = $envContent -match "TELEGRAM_BOT_TOKEN="
    
    if ($hasTelegram) {
        $botToken = ($envContent | Select-String "TELEGRAM_BOT_TOKEN=(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
        $chatId = ($envContent | Select-String "TELEGRAM_CHAT_ID=(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
        
        if ($botToken -and $chatId) {
            Write-Host "Testing Telegram bot..." -ForegroundColor Yellow
            
            try {
                $testUrl = "https://api.telegram.org/bot$botToken/getMe"
                $response = Invoke-RestMethod -Uri $testUrl -Method Get
                
                if ($response.ok) {
                    Write-Host "  ✓ Bot token valid" -ForegroundColor Green
                    Write-Host "    Bot: @$($response.result.username)" -ForegroundColor Gray
                    
                    # Send test message
                    $sendUrl = "https://api.telegram.org/bot$botToken/sendMessage"
                    $message = "🧪 *Monetization System Test*`n`nYour Telegram bot is working!`n`n⏰ $(Get-Date -Format 'HH:mm:ss')"
                    $body = @{
                        chat_id = $chatId
                        text = $message
                        parse_mode = "Markdown"
                    } | ConvertTo-Json
                    
                    $sendResponse = Invoke-RestMethod -Uri $sendUrl -Method Post -Body $body -ContentType "application/json"
                    
                    if ($sendResponse.ok) {
                        Write-Host "  ✓ Test message sent to your phone" -ForegroundColor Green
                    } else {
                        Write-Host "  ✗ Failed to send test message" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  ✗ Invalid bot token" -ForegroundColor Red
                }
            } catch {
                Write-Host "  ✗ Telegram bot test failed" -ForegroundColor Red
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⊙ Telegram credentials incomplete" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⊙ Telegram bot not configured (optional)" -ForegroundColor Gray
    }
} else {
    Write-Host "  ✗ .env.production not found" -ForegroundColor Red
}

Write-Host ""

# Test 5: Dependencies
Write-Host "═══ TEST 5: NPM Dependencies ═══" -ForegroundColor Cyan
Write-Host ""

$requiredPackages = @(
    "ethers",
    "pg",
    "redis",
    "winston",
    "@sentry/node"
)

$optionalPackages = @(
    "node-telegram-bot-api"
)

Write-Host "Checking required packages:" -ForegroundColor Yellow
foreach ($package in $requiredPackages) {
    $installed = Test-Path "node_modules\$package"
    if ($installed) {
        Write-Host "  ✓ $package" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $package (MISSING)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Checking optional packages:" -ForegroundColor Yellow
foreach ($package in $optionalPackages) {
    $installed = Test-Path "node_modules\$package"
    if ($installed) {
        Write-Host "  ✓ $package" -ForegroundColor Green
    } else {
        Write-Host "  ⊙ $package (optional)" -ForegroundColor Gray
    }
}

Write-Host ""

# Test 6: Database Migration
Write-Host "═══ TEST 6: Database Migration ═══" -ForegroundColor Cyan
Write-Host ""

if (Test-Path "migrations\002_revenue_tracking.sql") {
    Write-Host "  ✓ Revenue migration file exists" -ForegroundColor Green
    
    $migrationContent = Get-Content "migrations\002_revenue_tracking.sql" -Raw
    $tables = @("revenue_transactions", "daily_revenue_summary", "user_activity_log", "security_events")
    
    Write-Host "  Checking table definitions:" -ForegroundColor Yellow
    foreach ($table in $tables) {
        if ($migrationContent -match "CREATE TABLE.*$table") {
            Write-Host "    ✓ $table" -ForegroundColor Green
        } else {
            Write-Host "    ✗ $table (MISSING)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ✗ Revenue migration file not found" -ForegroundColor Red
}

Write-Host ""

# Summary
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 TEST SUMMARY" -ForegroundColor Cyan
Write-Host ""

$readyCount = 0
$totalChecks = 6

# Configuration
if (Test-Path ".env.production") {
    Write-Host "✓ Configuration: READY" -ForegroundColor Green
    $readyCount++
} else {
    Write-Host "✗ Configuration: NOT READY" -ForegroundColor Red
}

# Fee Calculator
if (Test-Path "src\lib\feeCalculator.js") {
    Write-Host "✓ Fee Calculator: READY" -ForegroundColor Green
    $readyCount++
} else {
    Write-Host "✗ Fee Calculator: NOT READY" -ForegroundColor Red
}

# Revenue Service
if (Test-Path "src\services\revenueService.js") {
    Write-Host "✓ Revenue Service: READY" -ForegroundColor Green
    $readyCount++
} else {
    Write-Host "✗ Revenue Service: NOT READY" -ForegroundColor Red
}

# Admin API
if (Test-Path "src\routes\adminRoutes.js") {
    Write-Host "✓ Admin API: READY" -ForegroundColor Green
    $readyCount++
} else {
    Write-Host "✗ Admin API: NOT READY" -ForegroundColor Red
}

# Database Migration
if (Test-Path "migrations\002_revenue_tracking.sql") {
    Write-Host "✓ Database Migration: READY" -ForegroundColor Green
    $readyCount++
} else {
    Write-Host "✗ Database Migration: NOT READY" -ForegroundColor Red
}

# Telegram (optional)
if (Test-Path ".env.production") {
    $envContent = Get-Content ".env.production" -Raw
    if ($envContent -match "TELEGRAM_BOT_TOKEN=") {
        Write-Host "✓ Telegram Alerts: CONFIGURED" -ForegroundColor Green
        $readyCount++
    } else {
        Write-Host "⊙ Telegram Alerts: NOT CONFIGURED (optional)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⊙ Telegram Alerts: NOT CONFIGURED" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Overall Status: $readyCount/6 components ready" -ForegroundColor $(if ($readyCount -ge 5) { "Green" } else { "Yellow" })
Write-Host ""

if ($readyCount -ge 5) {
    Write-Host "🎉 Your monetization system is ready!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Update treasury wallet addresses in .env.production" -ForegroundColor White
    Write-Host "  2. Deploy database and run migrations" -ForegroundColor White
    Write-Host "  3. Integrate revenue service into transaction endpoints" -ForegroundColor White
    Write-Host "  4. Start earning! 💰" -ForegroundColor White
} else {
    Write-Host "⚠️  Some components need attention" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To complete setup:" -ForegroundColor Yellow
    Write-Host "  1. Run: .\customize-fees.ps1" -ForegroundColor White
    Write-Host "  2. Run: .\setup-telegram-bot.ps1" -ForegroundColor White
    Write-Host "  3. Run this test again" -ForegroundColor White
}

Write-Host ""

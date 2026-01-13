# All-in-One Setup Script
# Combines fee structure and Telegram bot setup

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   COMPLETE MONETIZATION SETUP - ALL-IN-ONE         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "This wizard will set up:" -ForegroundColor Yellow
Write-Host "  1. Custom fee structure (flat/tiered/per-chain)" -ForegroundColor White
Write-Host "  2. Treasury wallet addresses" -ForegroundColor White
Write-Host "  3. Telegram bot for instant alerts" -ForegroundColor White
Write-Host "  4. Revenue tracking configuration" -ForegroundColor White
Write-Host ""

$continue = Read-Host "Ready to begin? (Y/N)"
if ($continue -ne "Y" -and $continue -ne "y") {
    Write-Host "Setup cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Let's get started! ⚡" -ForegroundColor Green
Write-Host ""

# Run fee customization
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PART 1: FEE STRUCTURE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

& ".\customize-fees.ps1"

Write-Host ""
Write-Host "✓ Fee structure configured!" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2

# Run Telegram setup
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "PART 2: TELEGRAM BOT" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$setupTelegram = Read-Host "Do you want to set up Telegram bot alerts? (Y/N)"

if ($setupTelegram -eq "Y" -or $setupTelegram -eq "y") {
    & ".\setup-telegram-bot.ps1"
} else {
    Write-Host ""
    Write-Host "⊙ Telegram bot setup skipped" -ForegroundColor Yellow
    Write-Host "  You can set it up later with: .\setup-telegram-bot.ps1" -ForegroundColor Gray
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SETUP COMPLETE!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Run tests
Write-Host "Running system tests..." -ForegroundColor Yellow
Write-Host ""

& ".\test-monetization.ps1"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎉 Your monetization system is ready!" -ForegroundColor Green
Write-Host ""
Write-Host "What's configured:" -ForegroundColor Yellow
Write-Host "  ✓ Fee structure and rates" -ForegroundColor White
Write-Host "  ✓ Fee calculation logic" -ForegroundColor White
Write-Host "  ✓ Revenue tracking system" -ForegroundColor White
Write-Host "  ✓ Admin dashboard API" -ForegroundColor White
if ($setupTelegram -eq "Y" -or $setupTelegram -eq "y") {
    Write-Host "  ✓ Telegram bot alerts" -ForegroundColor White
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review .env.production configuration" -ForegroundColor White
Write-Host "  2. Add your treasury wallet addresses" -ForegroundColor White
Write-Host "  3. Deploy database (PostgreSQL + Redis)" -ForegroundColor White
Write-Host "  4. Run migrations: psql `$env:DATABASE_URL -f migrations\002_revenue_tracking.sql" -ForegroundColor White
Write-Host "  5. Integrate into transaction endpoints" -ForegroundColor White
Write-Host "  6. Test on testnet first!" -ForegroundColor White
Write-Host "  7. Go live and start earning! 💰" -ForegroundColor White
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - MONETIZATION_GUIDE.md - Complete business strategy" -ForegroundColor Gray
Write-Host "  - ADMIN_API_REFERENCE.md - API documentation" -ForegroundColor Gray
Write-Host "  - SETUP_WIZARDS_GUIDE.md - Detailed setup help" -ForegroundColor Gray
Write-Host "  - MONETIZATION_COMPLETE.md - Quick reference" -ForegroundColor Gray
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

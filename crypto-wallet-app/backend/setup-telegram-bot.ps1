# Telegram Bot Setup Wizard
# Complete guide to set up instant alerts on your phone

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       TELEGRAM BOT SETUP WIZARD           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Get instant notifications on your phone for:" -ForegroundColor Yellow
Write-Host "  💰 Daily revenue targets reached" -ForegroundColor White
Write-Host "  💎 High-value transactions (>$10K)" -ForegroundColor White
Write-Host "  🚨 Security events (attacks, failed auth)" -ForegroundColor White
Write-Host "  ⚠️  Fee collection failures" -ForegroundColor White
Write-Host "  🔧 Server issues (high CPU, memory)" -ForegroundColor White
Write-Host ""

Write-Host "═══ STEP 1: CREATE YOUR BOT ═══" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Open Telegram on your phone or computer" -ForegroundColor Yellow
Write-Host "2. Search for: @BotFather" -ForegroundColor Yellow
Write-Host "3. Start a chat and send: /newbot" -ForegroundColor Yellow
Write-Host ""
Write-Host "BotFather will ask you two questions:" -ForegroundColor Gray
Write-Host "  Q: What name do you want for your bot?" -ForegroundColor Gray
Write-Host "  A: Crypto Wallet Monitor (or any name you like)" -ForegroundColor White
Write-Host ""
Write-Host "  Q: What username for your bot?" -ForegroundColor Gray
Write-Host "  A: cryptowallet_monitor_bot (must end in 'bot')" -ForegroundColor White
Write-Host ""
Write-Host "BotFather will send you a message with your bot token:" -ForegroundColor Gray
Write-Host "  Example: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz" -ForegroundColor Cyan
Write-Host ""

$botToken = Read-Host "Paste your bot token here"

if ([string]::IsNullOrWhiteSpace($botToken)) {
    Write-Host ""
    Write-Host "❌ No bot token provided. Exiting..." -ForegroundColor Red
    exit 1
}

# Validate bot token format
if ($botToken -notmatch '^\d+:[A-Za-z0-9_-]+$') {
    Write-Host ""
    Write-Host "⚠️  Warning: Bot token format looks incorrect" -ForegroundColor Yellow
    Write-Host "Expected format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz" -ForegroundColor Gray
    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -ne "Y" -and $continue -ne "y") {
        exit 1
    }
}

Write-Host ""
Write-Host "✓ Bot token saved!" -ForegroundColor Green
Write-Host ""

# Test bot token
Write-Host "Testing bot token..." -ForegroundColor Yellow
try {
    $testUrl = "https://api.telegram.org/bot$botToken/getMe"
    $response = Invoke-RestMethod -Uri $testUrl -Method Get
    
    if ($response.ok) {
        Write-Host "✓ Bot token is valid!" -ForegroundColor Green
        Write-Host "  Bot name: $($response.result.first_name)" -ForegroundColor White
        Write-Host "  Bot username: @$($response.result.username)" -ForegroundColor White
    } else {
        Write-Host "❌ Bot token validation failed!" -ForegroundColor Red
        Write-Host "Error: $($response.description)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "⚠️  Could not validate bot token (network issue?)" -ForegroundColor Yellow
    Write-Host "Continuing anyway..." -ForegroundColor Gray
}

Write-Host ""
Write-Host "═══ STEP 2: GET YOUR CHAT ID ═══" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now you need to get your Chat ID:" -ForegroundColor Yellow
Write-Host ""
Write-Host "METHOD 1 (Easy):" -ForegroundColor Cyan
Write-Host "1. Search for your bot: @$($response.result.username)" -ForegroundColor Yellow
Write-Host "2. Start a chat with your bot" -ForegroundColor Yellow
Write-Host "3. Send any message to your bot (e.g., 'Hello')" -ForegroundColor Yellow
Write-Host "4. I'll fetch your Chat ID automatically!" -ForegroundColor Yellow
Write-Host ""

$manual = Read-Host "Press Enter when you've sent a message to your bot (or type 'manual' for manual entry)"

if ($manual -eq "manual") {
    Write-Host ""
    Write-Host "METHOD 2 (Manual):" -ForegroundColor Cyan
    Write-Host "1. Search for @userinfobot in Telegram" -ForegroundColor Yellow
    Write-Host "2. Start a chat and it will show your User ID" -ForegroundColor Yellow
    Write-Host "3. That User ID is your Chat ID" -ForegroundColor Yellow
    Write-Host ""
    
    $chatId = Read-Host "Enter your Chat ID"
} else {
    Write-Host ""
    Write-Host "Fetching your Chat ID..." -ForegroundColor Yellow
    
    try {
        $updatesUrl = "https://api.telegram.org/bot$botToken/getUpdates"
        $updates = Invoke-RestMethod -Uri $updatesUrl -Method Get
        
        if ($updates.result.Count -gt 0) {
            $chatId = $updates.result[-1].message.chat.id
            $userName = $updates.result[-1].message.from.first_name
            
            Write-Host "✓ Chat ID found!" -ForegroundColor Green
            Write-Host "  Chat ID: $chatId" -ForegroundColor White
            Write-Host "  User: $userName" -ForegroundColor White
        } else {
            Write-Host "❌ No messages found. Please send a message to your bot first!" -ForegroundColor Red
            Write-Host ""
            Write-Host "Try again:" -ForegroundColor Yellow
            Write-Host "1. Open Telegram and search for your bot" -ForegroundColor Gray
            Write-Host "2. Send any message (e.g., 'Hello')" -ForegroundColor Gray
            Write-Host "3. Run this script again" -ForegroundColor Gray
            exit 1
        }
    } catch {
        Write-Host "❌ Could not fetch Chat ID automatically" -ForegroundColor Red
        Write-Host ""
        $chatId = Read-Host "Enter your Chat ID manually"
    }
}

if ([string]::IsNullOrWhiteSpace($chatId)) {
    Write-Host ""
    Write-Host "❌ No Chat ID provided. Exiting..." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✓ Chat ID saved!" -ForegroundColor Green
Write-Host ""

# Send test message
Write-Host "═══ STEP 3: SENDING TEST MESSAGE ═══" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sending test alert to your phone..." -ForegroundColor Yellow

try {
    $sendUrl = "https://api.telegram.org/bot$botToken/sendMessage"
    $message = @"
🎉 *Telegram Bot Setup Complete!*

Your crypto wallet monitoring bot is now active!

You will receive alerts for:
💰 Revenue milestones
💎 High-value transactions
🚨 Security events
⚠️ System issues

_Setup completed on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")_
"@

    $body = @{
        chat_id = $chatId
        text = $message
        parse_mode = "Markdown"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $sendUrl -Method Post -Body $body -ContentType "application/json"
    
    if ($response.ok) {
        Write-Host "✓ Test message sent successfully!" -ForegroundColor Green
        Write-Host "  Check your Telegram app!" -ForegroundColor White
    } else {
        Write-Host "❌ Failed to send test message" -ForegroundColor Red
    }
} catch {
    Write-Host "⚠️  Could not send test message" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "═══ STEP 4: CONFIGURE ALERT SETTINGS ═══" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configure when you want to receive alerts:" -ForegroundColor Yellow
Write-Host ""

$revenueThreshold = Read-Host "Daily revenue alert threshold in USD (default: 1000)"
if ([string]::IsNullOrWhiteSpace($revenueThreshold)) { $revenueThreshold = "1000" }

$highValueThreshold = Read-Host "High-value transaction alert threshold in USD (default: 10000)"
if ([string]::IsNullOrWhiteSpace($highValueThreshold)) { $highValueThreshold = "10000" }

Write-Host ""
Write-Host "Alert frequency for security events:" -ForegroundColor Yellow
Write-Host "1. INSTANT - Every security event (may be noisy)" -ForegroundColor White
Write-Host "2. IMPORTANT - Only medium/high/critical events" -ForegroundColor White
Write-Host "3. CRITICAL - Only critical events" -ForegroundColor White
Write-Host ""

$securityLevel = Read-Host "Choose alert level (1, 2, or 3, default: 2)"
if ([string]::IsNullOrWhiteSpace($securityLevel)) { $securityLevel = "2" }

$minSeverity = switch ($securityLevel) {
    "1" { "low" }
    "3" { "critical" }
    default { "medium" }
}

Write-Host ""
Write-Host "✓ Alert settings configured!" -ForegroundColor Green
Write-Host ""

# Save to .env.production
Write-Host "═══ STEP 5: SAVING CONFIGURATION ═══" -ForegroundColor Cyan
Write-Host ""

$envFile = "c:\Users\RICO\ricoamos\crypto-wallet-app\backend\.env.production"

$envContent = @"

# ===================================
# TELEGRAM BOT CONFIGURATION
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ===================================

# Telegram Bot Credentials
TELEGRAM_BOT_TOKEN=$botToken
TELEGRAM_CHAT_ID=$chatId
ENABLE_TELEGRAM_ALERTS=true

# Alert Thresholds
REVENUE_ALERT_THRESHOLD=$revenueThreshold
HIGH_VALUE_TX_THRESHOLD=$highValueThreshold
SECURITY_ALERT_MIN_SEVERITY=$minSeverity

# Alert Settings
TELEGRAM_ALERT_REVENUE=true
TELEGRAM_ALERT_HIGH_VALUE_TX=true
TELEGRAM_ALERT_SECURITY=true
TELEGRAM_ALERT_SYSTEM=true
TELEGRAM_ALERT_FEE_FAILURE=true

"@

if (Test-Path $envFile) {
    $existingContent = Get-Content $envFile -Raw
    if ($existingContent -notmatch "TELEGRAM BOT CONFIGURATION") {
        Add-Content -Path $envFile -Value $envContent
        Write-Host "✓ Configuration appended to .env.production" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Telegram configuration already exists" -ForegroundColor Yellow
        $overwrite = Read-Host "Overwrite existing config? (Y/N)"
        if ($overwrite -eq "Y" -or $overwrite -eq "y") {
            $existingContent -replace "(?s)# ===================================\s*# TELEGRAM BOT CONFIGURATION.*?(?=# ===================================|\z)", $envContent | Set-Content $envFile
            Write-Host "✓ Configuration updated" -ForegroundColor Green
        }
    }
} else {
    $envContent | Out-File -FilePath $envFile -Encoding UTF8
    Write-Host "✓ Configuration saved to .env.production" -ForegroundColor Green
}

# Install Telegram bot package
Write-Host ""
Write-Host "═══ STEP 6: INSTALLING DEPENDENCIES ═══" -ForegroundColor Cyan
Write-Host ""

$installTelegram = Read-Host "Install node-telegram-bot-api package? (Y/N, default: Y)"
if ($installTelegram -ne "N" -and $installTelegram -ne "n") {
    Write-Host "Installing node-telegram-bot-api..." -ForegroundColor Yellow
    Set-Location "c:\Users\RICO\ricoamos\crypto-wallet-app\backend"
    npm install node-telegram-bot-api --save
    Write-Host "✓ Package installed!" -ForegroundColor Green
}

# Create Telegram service
Write-Host ""
Write-Host "Creating Telegram alert service..." -ForegroundColor Yellow

$serviceContent = @'
const TelegramBot = require('node-telegram-bot-api');
const { logger } = require('../config/monitoring');

class TelegramAlertService {
  constructor() {
    this.enabled = process.env.ENABLE_TELEGRAM_ALERTS === 'true';
    
    if (this.enabled) {
      this.bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: false });
      this.chatId = process.env.TELEGRAM_CHAT_ID;
      this.revenueThreshold = parseFloat(process.env.REVENUE_ALERT_THRESHOLD || 1000);
      this.highValueThreshold = parseFloat(process.env.HIGH_VALUE_TX_THRESHOLD || 10000);
      this.minSeverity = process.env.SECURITY_ALERT_MIN_SEVERITY || 'medium';
      
      logger.info('Telegram alerts enabled', {
        chatId: this.chatId,
        revenueThreshold: this.revenueThreshold
      });
    } else {
      logger.info('Telegram alerts disabled');
    }
  }
  
  /**
   * Send revenue alert
   */
  async sendRevenueAlert(revenue, period = 'today') {
    if (!this.enabled || process.env.TELEGRAM_ALERT_REVENUE !== 'true') return;
    
    const message = `💰 *Revenue Alert*\n\n` +
      `Daily revenue has reached *$${revenue.toFixed(2)}*!\n\n` +
      `🎯 Target: $${this.revenueThreshold}\n` +
      `📊 Period: ${period}\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send high-value transaction alert
   */
  async sendHighValueTxAlert(transaction) {
    if (!this.enabled || process.env.TELEGRAM_ALERT_HIGH_VALUE_TX !== 'true') return;
    
    const message = `💎 *High-Value Transaction*\n\n` +
      `Amount: *$${transaction.amountUSD.toFixed(2)}*\n` +
      `Chain: ${transaction.chain}\n` +
      `Type: ${transaction.type}\n` +
      `Fee: $${transaction.feeUSD.toFixed(2)}\n\n` +
      `User: ${transaction.userId || 'Unknown'}\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send security alert
   */
  async sendSecurityAlert(event) {
    if (!this.enabled || process.env.TELEGRAM_ALERT_SECURITY !== 'true') return;
    
    // Check severity threshold
    const severityLevels = { low: 1, medium: 2, high: 3, critical: 4 };
    const minLevel = severityLevels[this.minSeverity];
    const eventLevel = severityLevels[event.severity];
    
    if (eventLevel < minLevel) return;
    
    const icon = event.severity === 'critical' ? '🚨' :
                 event.severity === 'high' ? '⚠️' :
                 event.severity === 'medium' ? '⚡' : 'ℹ️';
    
    const message = `${icon} *Security Alert*\n\n` +
      `Severity: *${event.severity.toUpperCase()}*\n` +
      `Type: ${event.eventType}\n\n` +
      `${event.description}\n\n` +
      `IP: ${event.ipAddress || 'Unknown'}\n` +
      `Action: ${event.actionTaken}\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send system alert
   */
  async sendSystemAlert(alert) {
    if (!this.enabled || process.env.TELEGRAM_ALERT_SYSTEM !== 'true') return;
    
    const icon = alert.type === 'error' ? '❌' :
                 alert.type === 'warning' ? '⚠️' : 'ℹ️';
    
    const message = `${icon} *System Alert*\n\n` +
      `${alert.message}\n\n` +
      `Component: ${alert.component || 'System'}\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send fee collection failure alert
   */
  async sendFeeFailureAlert(transaction) {
    if (!this.enabled || process.env.TELEGRAM_ALERT_FEE_FAILURE !== 'true') return;
    
    const message = `⚠️ *Fee Collection Failed*\n\n` +
      `Amount: $${transaction.feeUSD.toFixed(2)}\n` +
      `Chain: ${transaction.chain}\n` +
      `User: ${transaction.userId}\n\n` +
      `Error: ${transaction.error}\n\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send daily summary
   */
  async sendDailySummary(stats) {
    if (!this.enabled) return;
    
    const message = `📊 *Daily Summary*\n\n` +
      `💰 Revenue: $${stats.revenue.toFixed(2)}\n` +
      `📈 Transactions: ${stats.transactions}\n` +
      `👥 Active Users: ${stats.activeUsers}\n` +
      `🚨 Security Events: ${stats.securityEvents}\n\n` +
      `Top Chain: ${stats.topChain} ($${stats.topChainRevenue.toFixed(2)})\n\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
  
  /**
   * Send custom message
   */
  async sendMessage(message, options = {}) {
    if (!this.enabled) {
      logger.warn('Telegram alerts disabled, message not sent');
      return;
    }
    
    try {
      await this.bot.sendMessage(this.chatId, message, {
        parse_mode: 'Markdown',
        ...options
      });
      
      logger.info('Telegram alert sent', { preview: message.substring(0, 50) });
    } catch (error) {
      logger.error('Failed to send Telegram alert', {
        error: error.message,
        chatId: this.chatId
      });
    }
  }
  
  /**
   * Test alerts
   */
  async testAlerts() {
    const message = `🧪 *Test Alert*\n\n` +
      `All systems operational!\n\n` +
      `Your Telegram bot is working correctly.\n\n` +
      `⏰ ${new Date().toLocaleString()}`;
    
    await this.sendMessage(message);
  }
}

module.exports = new TelegramAlertService();
'@

$servicePath = "c:\Users\RICO\ricoamos\crypto-wallet-app\backend\src\services\telegramService.js"
$serviceContent | Out-File -FilePath $servicePath -Encoding UTF8
Write-Host "✓ Telegram service created: src\services\telegramService.js" -ForegroundColor Green

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎉 Telegram bot setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Bot Token: $($botToken.Substring(0,15))..." -ForegroundColor White
Write-Host "  Chat ID: $chatId" -ForegroundColor White
Write-Host "  Revenue Threshold: `$$revenueThreshold" -ForegroundColor White
Write-Host "  High-Value TX: `$$highValueThreshold" -ForegroundColor White
Write-Host "  Security Level: $minSeverity and above" -ForegroundColor White
Write-Host ""
Write-Host "Alert Types Enabled:" -ForegroundColor Cyan
Write-Host "  ✓ Revenue milestones" -ForegroundColor Green
Write-Host "  ✓ High-value transactions" -ForegroundColor Green
Write-Host "  ✓ Security events" -ForegroundColor Green
Write-Host "  ✓ System issues" -ForegroundColor Green
Write-Host "  ✓ Fee collection failures" -ForegroundColor Green
Write-Host ""
Write-Host "Files Created/Updated:" -ForegroundColor Cyan
Write-Host "  ✓ .env.production" -ForegroundColor Gray
Write-Host "  ✓ src\services\telegramService.js" -ForegroundColor Gray
Write-Host "  ✓ node_modules\node-telegram-bot-api" -ForegroundColor Gray
Write-Host ""
Write-Host "Test Your Bot:" -ForegroundColor Yellow
Write-Host "  1. Start your server: node server.js" -ForegroundColor White
Write-Host "  2. In Node.js console:" -ForegroundColor White
Write-Host "     const telegram = require('./src/services/telegramService');" -ForegroundColor Gray
Write-Host "     telegram.testAlerts();" -ForegroundColor Gray
Write-Host ""
Write-Host "You'll now receive instant alerts on your phone! 📱" -ForegroundColor Green
Write-Host ""

/**
 * Telegram Service
 * Sends real-time alerts and notifications for fee collection, sweeps, and app operations
 */

const TelegramBot = require('node-telegram-bot-api');
require('dotenv').config();

class TelegramService {
  constructor() {
    this.enabled = !!process.env.TELEGRAM_BOT_TOKEN && !!process.env.TELEGRAM_ADMIN_CHAT_ID;
    this.botToken = process.env.TELEGRAM_BOT_TOKEN;
    this.adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID;

    if (this.enabled) {
      this.bot = new TelegramBot(this.botToken, { polling: false });
      console.log('✅ Telegram service initialized');
    } else {
      console.warn('⚠️  Telegram alerts disabled (TELEGRAM_BOT_TOKEN or TELEGRAM_ADMIN_CHAT_ID not set)');
    }
  }

  /**
   * Send a generic alert message
   */
  async sendAlert(title, message, parseMode = 'HTML') {
    if (!this.enabled) return;

    try {
      const text = `<b>${title}</b>\n${message}`;
      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: parseMode });
    } catch (error) {
      console.error('Error sending Telegram alert:', error);
    }
  }

  /**
   * Send fee collection notification
   */
  async sendFeeCollection(data) {
    if (!this.enabled) return;

    try {
      const { network, amount, fee, txHash, from, to } = data;
      
      const text = `
<b>💰 Fee Collected</b>
━━━━━━━━━━━━━━━━
<b>Network:</b> ${network}
<b>Transaction:</b> ${txHash}
<b>Amount:</b> ${amount} ${network}
<b>Fee:</b> ${fee} ${network}
<b>From:</b> <code>${from}</code>
<b>To:</b> <code>${to}</code>
<b>Time:</b> ${new Date().toLocaleString()}
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending fee collection alert:', error);
    }
  }

  /**
   * Send sweep summary (most important for admin)
   */
  async sendSweepSummary(data) {
    if (!this.enabled) return;

    try {
      const { feeCount, totalUSDT, txHash, duration, aggregatedFees } = data;

      // Build breakdown by chain
      let breakdown = '';
      for (const [chain, amount] of Object.entries(aggregatedFees)) {
        breakdown += `  • <b>${chain}:</b> ${amount.toFixed(6)}\n`;
      }

      const text = `
<b>🎯 Fee Sweep Complete!</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
<b>📊 Summary</b>
  Fees Collected: ${feeCount}
  Total Value: <b>$${totalUSDT.toFixed(2)}</b> USDT
  Duration: ${duration}s

<b>💵 Breakdown by Chain</b>
${breakdown}
<b>🚀 Transfer Details</b>
  Destination: <code>${process.env.TREASURY_USDT_ADDRESS || '0x726dac...'}</code>
  TX Hash: <code>${txHash}</code>
  Status: ✅ COMPLETED

<b>⏰ Timestamp:</b> ${new Date().toLocaleString()}
━━━━━━━━━━━━━━━━━━━━━━━━━
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending sweep summary:', error);
    }
  }

  /**
   * Send transaction notification
   */
  async sendTransaction(data) {
    if (!this.enabled) return;

    try {
      const { type, network, amount, from, to, txHash, status = 'pending' } = data;
      
      const emoji = type === 'send' ? '📤' : '📥';
      const statusEmoji = status === 'completed' ? '✅' : '⏳';

      const text = `
<b>${emoji} Transaction ${type.toUpperCase()}</b>
━━━━━━━━━━━━━━━━
<b>Network:</b> ${network}
<b>Amount:</b> ${amount}
<b>From:</b> <code>${from}</code>
<b>To:</b> <code>${to}</code>
<b>Status:</b> ${statusEmoji} ${status.toUpperCase()}
<b>TX Hash:</b> <code>${txHash}</code>
<b>Time:</b> ${new Date().toLocaleString()}
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending transaction alert:', error);
    }
  }

  /**
   * Send wallet balance update
   */
  async sendBalanceUpdate(data) {
    if (!this.enabled) return;

    try {
      const { walletAddress, balances, network } = data;

      let balanceText = '';
      for (const [coin, balance] of Object.entries(balances)) {
        balanceText += `  • <b>${coin}:</b> ${balance}\n`;
      }

      const text = `
<b>💼 Balance Update</b>
━━━━━━━━━━━━━━━━
<b>Wallet:</b> <code>${walletAddress}</code>
<b>Network:</b> ${network}

<b>Balances:</b>
${balanceText}
<b>Time:</b> ${new Date().toLocaleString()}
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending balance update:', error);
    }
  }

  /**
   * Send error/warning alert
   */
  async sendError(title, errorMessage, severity = 'error') {
    if (!this.enabled) return;

    try {
      const emoji = severity === 'error' ? '❌' : '⚠️';
      const text = `
<b>${emoji} ${title}</b>
━━━━━━━━━━━━━━━━
<code>${errorMessage}</code>

<b>Time:</b> ${new Date().toLocaleString()}
<b>Severity:</b> ${severity.toUpperCase()}
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending error alert:', error);
    }
  }

  /**
   * Send app startup notification
   */
  async sendStartupNotification(data = {}) {
    if (!this.enabled) return;

    try {
      const { port = 3000, environment = 'development', features = [] } = data;

      let featureList = '';
      if (features.length > 0) {
        featureList = features.map(f => `  ✓ ${f}`).join('\n') + '\n';
      }

      const text = `
<b>🚀 Crypto Wallet App Started</b>
━━━━━━━━━━━━━━━━━━━━━━━━
<b>Port:</b> ${port}
<b>Environment:</b> ${environment}
<b>Status:</b> ✅ ONLINE

<b>Features Enabled:</b>
${featureList || '  • Fee Collection\n  • Transaction Monitoring\n  • Telegram Alerts'}
<b>Time:</b> ${new Date().toLocaleString()}
━━━━━━━━━━━━━━━━━━━━━━━━
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending startup notification:', error);
    }
  }

  /**
   * Send daily statistics report
   */
  async sendDailyReport(stats) {
    if (!this.enabled) return;

    try {
      const { date, totalTransactions, totalVolume, totalFees, topCoin } = stats;

      const text = `
<b>📈 Daily Report</b>
━━━━━━━━━━━━━━━━
<b>Date:</b> ${date}

<b>Metrics:</b>
  • Transactions: ${totalTransactions}
  • Volume: $${totalVolume.toFixed(2)}
  • Fees Collected: $${totalFees.toFixed(2)}
  • Top Asset: ${topCoin}

<b>Status:</b> ✅ ALL SYSTEMS OPERATIONAL
<b>Time:</b> ${new Date().toLocaleString()}
`.trim();

      await this.bot.sendMessage(this.adminChatId, text, { parse_mode: 'HTML' });
    } catch (error) {
      console.error('Error sending daily report:', error);
    }
  }

  /**
   * Test Telegram connectivity
   */
  async testConnection() {
    if (!this.enabled) {
      console.log('⚠️  Telegram service is disabled');
      return false;
    }

    try {
      await this.bot.sendMessage(
        this.adminChatId,
        '🧪 <b>Telegram Service Test</b>\nConnection successful! ✅',
        { parse_mode: 'HTML' }
      );
      console.log('✅ Telegram connection test successful');
      return true;
    } catch (error) {
      console.error('❌ Telegram connection test failed:', error);
      return false;
    }
  }
}

module.exports = TelegramService;

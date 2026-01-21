/**
 * Telegram Service (Stub)
 * 
 * This is a no-op stub that maintains API compatibility.
 * The actual Telegram integration was removed to eliminate security vulnerabilities
 * in the node-telegram-bot-api dependency.
 * 
 * All methods are preserved but do nothing, so existing code won't break.
 * 
 * To re-enable Telegram alerts in the future:
 * 1. Wait for node-telegram-bot-api to fix vulnerabilities, or
 * 2. Use a webhook-based solution with axios instead
 */

require('dotenv').config();

class TelegramService {
  constructor() {
    this.enabled = false;
    console.log('ℹ️  Telegram alerts disabled (dependency removed for security)');
  }

  async sendAlert(title, message, parseMode = 'HTML') {
    return;
  }

  async sendFeeCollection(data) {
    return;
  }

  async sendSweepSummary(data) {
    return;
  }

  async sendTransaction(data) {
    return;
  }

  async sendBalanceUpdate(data) {
    return;
  }

  async sendError(title, errorMessage, severity = 'error') {
    return;
  }

  async sendStartupNotification(data = {}) {
    return;
  }

  async sendDailyReport(stats) {
    return;
  }

  async testConnection() {
    return false;
  }
}

module.exports = TelegramService;

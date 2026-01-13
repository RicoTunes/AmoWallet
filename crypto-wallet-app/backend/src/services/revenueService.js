const { ethers } = require('ethers');
const database = require('../config/database');
const { logger } = require('../config/monitoring');

/**
 * Revenue Collection Service
 * Handles fee collection, tracking, and treasury management
 */

class RevenueService {
  constructor() {
    // Load configuration from environment
    this.config = {
      // Treasury addresses (YOUR PROFIT WALLETS)
      treasuryAddresses: {
        ethereum: process.env.TREASURY_ETH_ADDRESS,
        bitcoin: process.env.TREASURY_BTC_ADDRESS,
        polygon: process.env.TREASURY_POLYGON_ADDRESS,
        bsc: process.env.TREASURY_BSC_ADDRESS,
        usdt: process.env.TREASURY_USDT_ADDRESS,
      },
      
      // Fee structure
      transactionFeePercentage: parseFloat(process.env.TRANSACTION_FEE_PERCENTAGE || '0.5'),
      minTransactionFeeUSD: parseFloat(process.env.MIN_TRANSACTION_FEE_USD || '0.50'),
      swapFeePercentage: parseFloat(process.env.SWAP_FEE_PERCENTAGE || '1.0'),
      
      // Collection method
      collectionMethod: process.env.FEE_COLLECTION_METHOD || 'deduction',
      autoConvertToUSDT: process.env.AUTO_CONVERT_TO_USDT === 'true',
      
      // Tracking
      enableTracking: process.env.ENABLE_REVENUE_TRACKING !== 'false',
      alertThreshold: parseFloat(process.env.REVENUE_ALERT_THRESHOLD || '1000'),
    };
    
    this.dailyRevenue = 0;
  }
  
  /**
   * Calculate fee for a transaction
   */
  calculateFee(amount, amountUSD, type = 'transaction') {
    const feePercentage = type === 'swap' 
      ? this.config.swapFeePercentage 
      : this.config.transactionFeePercentage;
    
    // Calculate fee
    const feeAmount = amount * (feePercentage / 100);
    const feeAmountUSD = amountUSD * (feePercentage / 100);
    
    // Apply minimum fee
    const finalFeeUSD = Math.max(feeAmountUSD, this.config.minTransactionFeeUSD);
    const finalFeeAmount = finalFeeUSD / amountUSD * amount;
    
    return {
      feeAmount: finalFeeAmount,
      feeAmountUSD: finalFeeUSD,
      feePercentage,
      netAmount: amount - finalFeeAmount,
      netAmountUSD: amountUSD - finalFeeUSD,
    };
  }
  
  /**
   * Process transaction with fee deduction
   */
  async processTransactionWithFee(transactionData) {
    const {
      amount,
      amountUSD,
      chain,
      userId,
      transactionType = 'send',
    } = transactionData;
    
    try {
      // Calculate fee
      const feeDetails = this.calculateFee(amount, amountUSD, transactionType);
      
      logger.info('Fee calculated', {
        userId,
        amount,
        feeAmount: feeDetails.feeAmount,
        feeAmountUSD: feeDetails.feeAmountUSD,
        netAmount: feeDetails.netAmount,
      });
      
      // Track revenue if enabled
      if (this.config.enableTracking) {
        await this.trackRevenue({
          userId,
          chain,
          transactionType,
          originalAmount: amount,
          originalAmountUSD: amountUSD,
          feeAmount: feeDetails.feeAmount,
          feeAmountUSD: feeDetails.feeAmountUSD,
          feePercentage: feeDetails.feePercentage,
          status: 'pending',
        });
      }
      
      // Update daily revenue
      this.dailyRevenue += feeDetails.feeAmountUSD;
      
      // Check alert threshold
      if (this.dailyRevenue >= this.config.alertThreshold) {
        await this.sendRevenueAlert();
      }
      
      return {
        success: true,
        ...feeDetails,
        treasuryAddress: this.getTreasuryAddress(chain),
      };
      
    } catch (error) {
      logger.error('Error processing transaction fee:', error);
      throw error;
    }
  }
  
  /**
   * Get treasury address for a specific chain
   */
  getTreasuryAddress(chain) {
    const chainKey = chain.toLowerCase();
    return this.config.treasuryAddresses[chainKey] || this.config.treasuryAddresses.ethereum;
  }
  
  /**
   * Track revenue in database
   */
  async trackRevenue(revenueData) {
    if (!this.config.enableTracking) return;
    
    try {
      const query = `
        INSERT INTO revenue_transactions (
          id, user_id, chain, transaction_type,
          original_amount, original_amount_usd,
          fee_amount, fee_amount_usd, fee_percentage,
          treasury_address, status, collection_method,
          created_at
        ) VALUES (
          gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW()
        )
        RETURNING id
      `;
      
      const values = [
        revenueData.userId,
        revenueData.chain,
        revenueData.transactionType,
        revenueData.originalAmount,
        revenueData.originalAmountUSD,
        revenueData.feeAmount,
        revenueData.feeAmountUSD,
        revenueData.feePercentage,
        this.getTreasuryAddress(revenueData.chain),
        revenueData.status,
        this.config.collectionMethod,
      ];
      
      const result = await database.query(query, values);
      logger.info('Revenue tracked', { revenueId: result.rows[0].id });
      
      // Update daily summary
      await this.updateDailySummary(revenueData);
      
    } catch (error) {
      logger.error('Error tracking revenue:', error);
      // Don't throw - revenue tracking shouldn't break transactions
    }
  }
  
  /**
   * Update daily revenue summary
   */
  async updateDailySummary(revenueData) {
    try {
      const query = `
        INSERT INTO daily_revenue_summary (
          date, total_transactions, total_revenue_usd
        ) VALUES (
          CURRENT_DATE, 1, $1
        )
        ON CONFLICT (date) DO UPDATE SET
          total_transactions = daily_revenue_summary.total_transactions + 1,
          total_revenue_usd = daily_revenue_summary.total_revenue_usd + $1
      `;
      
      await database.query(query, [revenueData.feeAmountUSD]);
      
    } catch (error) {
      logger.error('Error updating daily summary:', error);
    }
  }
  
  /**
   * Get revenue statistics
   */
  async getRevenueStats(period = 'today') {
    try {
      let query;
      
      if (period === 'today') {
        query = `
          SELECT 
            COUNT(*) as transaction_count,
            SUM(fee_amount_usd) as total_revenue_usd,
            AVG(fee_amount_usd) as avg_fee_usd,
            MAX(fee_amount_usd) as max_fee_usd
          FROM revenue_transactions
          WHERE DATE(created_at) = CURRENT_DATE
        `;
      } else if (period === 'month') {
        query = `
          SELECT 
            COUNT(*) as transaction_count,
            SUM(fee_amount_usd) as total_revenue_usd,
            AVG(fee_amount_usd) as avg_fee_usd,
            MAX(fee_amount_usd) as max_fee_usd
          FROM revenue_transactions
          WHERE DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE)
        `;
      } else if (period === 'all') {
        query = `
          SELECT 
            COUNT(*) as transaction_count,
            SUM(fee_amount_usd) as total_revenue_usd,
            AVG(fee_amount_usd) as avg_fee_usd,
            MAX(fee_amount_usd) as max_fee_usd
          FROM revenue_transactions
        `;
      }
      
      const result = await database.query(query);
      return result.rows[0];
      
    } catch (error) {
      logger.error('Error getting revenue stats:', error);
      return null;
    }
  }
  
  /**
   * Get revenue by chain
   */
  async getRevenueByChain(period = 'today') {
    try {
      let dateFilter = "DATE(created_at) = CURRENT_DATE";
      if (period === 'month') {
        dateFilter = "DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE)";
      } else if (period === 'all') {
        dateFilter = "1=1";
      }
      
      const query = `
        SELECT 
          chain,
          COUNT(*) as transaction_count,
          SUM(fee_amount_usd) as total_revenue_usd
        FROM revenue_transactions
        WHERE ${dateFilter}
        GROUP BY chain
        ORDER BY total_revenue_usd DESC
      `;
      
      const result = await database.query(query);
      return result.rows;
      
    } catch (error) {
      logger.error('Error getting revenue by chain:', error);
      return [];
    }
  }
  
  /**
   * Get top revenue-generating users
   */
  async getTopRevenueUsers(limit = 10) {
    try {
      const query = `
        SELECT 
          user_id,
          COUNT(*) as transaction_count,
          SUM(fee_amount_usd) as total_revenue_usd,
          AVG(fee_amount_usd) as avg_fee_usd
        FROM revenue_transactions
        WHERE user_id IS NOT NULL
        GROUP BY user_id
        ORDER BY total_revenue_usd DESC
        LIMIT $1
      `;
      
      const result = await database.query(query, [limit]);
      return result.rows;
      
    } catch (error) {
      logger.error('Error getting top revenue users:', error);
      return [];
    }
  }
  
  /**
   * Send revenue alert (via Telegram, Email, etc.)
   */
  async sendRevenueAlert() {
    const stats = await this.getRevenueStats('today');
    
    logger.info('Revenue alert triggered', {
      dailyRevenue: this.dailyRevenue,
      threshold: this.config.alertThreshold,
      stats,
    });
    
    // Send Telegram alert if configured
    try {
      const telegramService = require('./telegramService');
      await telegramService.sendRevenueAlert(this.dailyRevenue, 'today');
    } catch (error) {
      logger.warn('Could not send Telegram alert', { error: error.message });
    }
  }
  
  /**
   * Log security event
   */
  async logSecurityEvent(eventData) {
    try {
      const query = `
        INSERT INTO security_events (
          id, event_type, severity, ip_address, user_agent,
          description, event_data, action_taken, created_at
        ) VALUES (
          gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, NOW()
        )
      `;
      
      const values = [
        eventData.eventType,
        eventData.severity || 'medium',
        eventData.ipAddress,
        eventData.userAgent,
        eventData.description,
        JSON.stringify(eventData.data || {}),
        eventData.actionTaken || 'logged',
      ];
      
      await database.query(query, values);
      
      // Send alert for high/critical events
      if (eventData.severity === 'high' || eventData.severity === 'critical') {
        logger.warn('Security event', eventData);
        // TODO: Send immediate alert
      }
      
    } catch (error) {
      logger.error('Error logging security event:', error);
    }
  }
  
  /**
   * Log user activity
   */
  async logUserActivity(activityData) {
    try {
      const query = `
        INSERT INTO user_activity_log (
          id, user_id, ip_address, user_agent,
          activity_type, endpoint, method,
          request_data, response_status, response_time_ms,
          is_suspicious, risk_score, created_at
        ) VALUES (
          gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW()
        )
      `;
      
      const values = [
        activityData.userId,
        activityData.ipAddress,
        activityData.userAgent,
        activityData.activityType,
        activityData.endpoint,
        activityData.method,
        JSON.stringify(activityData.requestData || {}),
        activityData.responseStatus,
        activityData.responseTimeMs,
        activityData.isSuspicious || false,
        activityData.riskScore || 0,
      ];
      
      await database.query(query, values);
      
    } catch (error) {
      logger.error('Error logging user activity:', error);
    }
  }
}

// Export singleton instance
module.exports = new RevenueService();

-- ===================================
-- Revenue & Monitoring Database Schema
-- Migration: 002_revenue_tracking
-- ===================================

-- Table 1: Revenue Transactions
-- Tracks all fee collections from user transactions
CREATE TABLE IF NOT EXISTS revenue_transactions (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR(255),
  chain VARCHAR(50) NOT NULL,
  transaction_type VARCHAR(50) NOT NULL, -- 'send', 'swap', 'other'
  
  -- Original transaction details
  original_amount DECIMAL(36, 18) NOT NULL,
  original_amount_usd DECIMAL(18, 2) NOT NULL,
  original_token VARCHAR(50),
  
  -- Fee details
  fee_amount DECIMAL(36, 18) NOT NULL,
  fee_amount_usd DECIMAL(18, 2) NOT NULL,
  fee_percentage DECIMAL(5, 2) NOT NULL,
  
  -- Net amounts (after fee deduction)
  net_amount DECIMAL(36, 18) NOT NULL,
  net_amount_usd DECIMAL(18, 2) NOT NULL,
  
  -- USDT conversion (if auto-convert enabled)
  usdt_amount DECIMAL(18, 6),
  usdt_conversion_rate DECIMAL(18, 6),
  usdt_transaction_hash VARCHAR(255),
  
  -- Treasury details
  treasury_address VARCHAR(255) NOT NULL,
  collection_method VARCHAR(50) NOT NULL, -- 'deduction', 'separate', 'usdt_conversion'
  
  -- Transaction tracking
  user_transaction_hash VARCHAR(255),
  fee_transaction_hash VARCHAR(255),
  
  -- Status
  status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'completed', 'failed'
  error_message TEXT,
  
  -- Metadata
  metadata JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for revenue_transactions
CREATE INDEX idx_revenue_user_id ON revenue_transactions(user_id);
CREATE INDEX idx_revenue_chain ON revenue_transactions(chain);
CREATE INDEX idx_revenue_type ON revenue_transactions(transaction_type);
CREATE INDEX idx_revenue_created_at ON revenue_transactions(created_at);
CREATE INDEX idx_revenue_status ON revenue_transactions(status);
CREATE INDEX idx_revenue_user_created ON revenue_transactions(user_id, created_at);

-- Table 2: Daily Revenue Summary
-- Aggregated daily statistics for quick dashboard queries
CREATE TABLE IF NOT EXISTS daily_revenue_summary (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL UNIQUE,
  
  -- Transaction counts
  total_transactions INTEGER DEFAULT 0,
  successful_transactions INTEGER DEFAULT 0,
  failed_transactions INTEGER DEFAULT 0,
  
  -- Revenue totals
  total_revenue_usd DECIMAL(18, 2) DEFAULT 0,
  total_original_amount_usd DECIMAL(18, 2) DEFAULT 0,
  
  -- Averages
  avg_fee_usd DECIMAL(18, 2) DEFAULT 0,
  avg_transaction_size_usd DECIMAL(18, 2) DEFAULT 0,
  
  -- Highs
  highest_fee_usd DECIMAL(18, 2) DEFAULT 0,
  highest_transaction_usd DECIMAL(18, 2) DEFAULT 0,
  
  -- Revenue by chain (JSON for flexibility)
  revenue_by_chain JSONB DEFAULT '{}',
  revenue_by_type JSONB DEFAULT '{}',
  
  -- Conversion stats (if USDT auto-convert enabled)
  total_usdt_converted DECIMAL(18, 6) DEFAULT 0,
  usdt_conversion_count INTEGER DEFAULT 0,
  
  -- Metadata
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for daily_revenue_summary
CREATE INDEX idx_daily_revenue_date ON daily_revenue_summary(date);

-- Table 3: User Activity Log
-- Complete audit trail of all user actions
CREATE TABLE IF NOT EXISTS user_activity_log (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR(255),
  
  -- Activity details
  activity_type VARCHAR(100) NOT NULL, -- 'login', 'transaction', 'swap', 'wallet_create', etc.
  endpoint VARCHAR(255),
  method VARCHAR(10), -- 'GET', 'POST', etc.
  
  -- Request details
  ip_address VARCHAR(45),
  user_agent TEXT,
  country VARCHAR(2),
  city VARCHAR(100),
  
  -- Request/Response data
  request_data JSONB,
  response_status INTEGER,
  response_data JSONB,
  
  -- Security flags
  is_suspicious BOOLEAN DEFAULT false,
  risk_score INTEGER DEFAULT 0, -- 0-100
  suspicious_reasons TEXT[],
  
  -- Timing
  response_time_ms INTEGER,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for user_activity_log
CREATE INDEX idx_activity_user_id ON user_activity_log(user_id);
CREATE INDEX idx_activity_type ON user_activity_log(activity_type);
CREATE INDEX idx_activity_ip ON user_activity_log(ip_address);
CREATE INDEX idx_activity_suspicious ON user_activity_log(is_suspicious);
CREATE INDEX idx_activity_created_at ON user_activity_log(created_at);
CREATE INDEX idx_activity_user_created ON user_activity_log(user_id, created_at);

-- Table 4: Security Events
-- Tracks all security-related events and attacks
CREATE TABLE IF NOT EXISTS security_events (
  id SERIAL PRIMARY KEY,
  
  -- Event classification
  event_type VARCHAR(100) NOT NULL, -- 'failed_auth', 'rate_limit', 'invalid_signature', 'sql_injection', etc.
  severity VARCHAR(20) NOT NULL, -- 'low', 'medium', 'high', 'critical'
  
  -- Source information
  ip_address VARCHAR(45),
  user_id VARCHAR(255),
  user_agent TEXT,
  country VARCHAR(2),
  
  -- Event details
  description TEXT NOT NULL,
  endpoint VARCHAR(255),
  method VARCHAR(10),
  
  -- Attack data
  attack_payload TEXT,
  blocked BOOLEAN DEFAULT true,
  action_taken VARCHAR(255), -- 'blocked', 'rate_limited', 'banned', 'alerted', etc.
  
  -- Context
  metadata JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for security_events
CREATE INDEX idx_security_event_type ON security_events(event_type);
CREATE INDEX idx_security_severity ON security_events(severity);
CREATE INDEX idx_security_ip ON security_events(ip_address);
CREATE INDEX idx_security_user_id ON security_events(user_id);
CREATE INDEX idx_security_created_at ON security_events(created_at);
CREATE INDEX idx_security_severity_created ON security_events(severity, created_at);

-- ===================================
-- Utility Functions
-- ===================================

-- Function to update daily summary
CREATE OR REPLACE FUNCTION update_daily_summary() 
RETURNS TRIGGER AS $$
BEGIN
  -- Only process completed transactions
  IF NEW.status = 'completed' THEN
    INSERT INTO daily_revenue_summary (
      date, 
      total_transactions, 
      successful_transactions,
      total_revenue_usd,
      total_original_amount_usd,
      avg_fee_usd,
      avg_transaction_size_usd,
      highest_fee_usd,
      highest_transaction_usd
    )
    VALUES (
      DATE(NEW.created_at),
      1,
      1,
      NEW.fee_amount_usd,
      NEW.original_amount_usd,
      NEW.fee_amount_usd,
      NEW.original_amount_usd,
      NEW.fee_amount_usd,
      NEW.original_amount_usd
    )
    ON CONFLICT (date) DO UPDATE SET
      total_transactions = daily_revenue_summary.total_transactions + 1,
      successful_transactions = daily_revenue_summary.successful_transactions + 1,
      total_revenue_usd = daily_revenue_summary.total_revenue_usd + NEW.fee_amount_usd,
      total_original_amount_usd = daily_revenue_summary.total_original_amount_usd + NEW.original_amount_usd,
      avg_fee_usd = (daily_revenue_summary.total_revenue_usd + NEW.fee_amount_usd) / (daily_revenue_summary.successful_transactions + 1),
      avg_transaction_size_usd = (daily_revenue_summary.total_original_amount_usd + NEW.original_amount_usd) / (daily_revenue_summary.successful_transactions + 1),
      highest_fee_usd = GREATEST(daily_revenue_summary.highest_fee_usd, NEW.fee_amount_usd),
      highest_transaction_usd = GREATEST(daily_revenue_summary.highest_transaction_usd, NEW.original_amount_usd),
      updated_at = CURRENT_TIMESTAMP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update daily summary
CREATE TRIGGER trigger_update_daily_summary
AFTER INSERT OR UPDATE ON revenue_transactions
FOR EACH ROW
EXECUTE FUNCTION update_daily_summary();

-- ===================================
-- Sample Queries for Testing
-- ===================================

-- Get today's revenue
-- SELECT * FROM daily_revenue_summary WHERE date = CURRENT_DATE;

-- Get top revenue users
-- SELECT user_id, SUM(fee_amount_usd) as total_revenue
-- FROM revenue_transactions
-- WHERE status = 'completed'
-- GROUP BY user_id
-- ORDER BY total_revenue DESC
-- LIMIT 10;

-- Get recent security events
-- SELECT * FROM security_events
-- WHERE severity IN ('high', 'critical')
-- ORDER BY created_at DESC
-- LIMIT 20;

-- Get suspicious activities
-- SELECT * FROM user_activity_log
-- WHERE is_suspicious = true
-- ORDER BY created_at DESC
-- LIMIT 20;

-- Revenue by chain today
-- SELECT chain, COUNT(*) as tx_count, SUM(fee_amount_usd) as revenue
-- FROM revenue_transactions
-- WHERE DATE(created_at) = CURRENT_DATE AND status = 'completed'
-- GROUP BY chain;

-- ===================================
-- Migration Complete
-- ===================================

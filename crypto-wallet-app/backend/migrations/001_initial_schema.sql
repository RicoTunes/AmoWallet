-- Migration 001: Initial Schema
-- Created: 2024
-- Description: Create initial database schema for Crypto Wallet Pro

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- API Keys Table
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    api_key VARCHAR(64) UNIQUE NOT NULL,
    secret_hash VARCHAR(128) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_revoked BOOLEAN DEFAULT FALSE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for API keys
CREATE INDEX idx_api_keys_key ON api_keys(api_key) WHERE is_revoked = FALSE;
CREATE INDEX idx_api_keys_created_at ON api_keys(created_at);
CREATE INDEX idx_api_keys_last_used ON api_keys(last_used_at);

-- Transactions Table
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) UNIQUE NOT NULL,
    chain VARCHAR(50) NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42) NOT NULL,
    amount DECIMAL(36, 18) NOT NULL,
    amount_usd DECIMAL(20, 2),
    gas_price BIGINT,
    gas_used BIGINT,
    nonce INTEGER,
    status VARCHAR(20) DEFAULT 'pending',
    confirmations INTEGER DEFAULT 0,
    block_number BIGINT,
    block_hash VARCHAR(66),
    timestamp TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for transactions
CREATE INDEX idx_transactions_hash ON transactions(tx_hash);
CREATE INDEX idx_transactions_chain ON transactions(chain);
CREATE INDEX idx_transactions_from ON transactions(from_address);
CREATE INDEX idx_transactions_to ON transactions(to_address);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_block_number ON transactions(block_number);

-- Spending History Table
CREATE TABLE IF NOT EXISTS spending_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    date DATE NOT NULL,
    total_spent_usd DECIMAL(20, 2) DEFAULT 0,
    transaction_count INTEGER DEFAULT 0,
    reset_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(date)
);

-- Indexes for spending history
CREATE INDEX idx_spending_history_date ON spending_history(date DESC);
CREATE INDEX idx_spending_history_reset_at ON spending_history(reset_at);

-- User Sessions Table (for Redis backup)
CREATE TABLE IF NOT EXISTS sessions (
    sid VARCHAR(255) PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Indexes for sessions
CREATE INDEX idx_sessions_expire ON sessions(expire);

-- Wallet Addresses Table
CREATE TABLE IF NOT EXISTS wallet_addresses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    address VARCHAR(42) UNIQUE NOT NULL,
    chain VARCHAR(50) NOT NULL,
    label VARCHAR(255),
    is_watched BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_activity_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for wallet addresses
CREATE INDEX idx_wallet_addresses_address ON wallet_addresses(address);
CREATE INDEX idx_wallet_addresses_chain ON wallet_addresses(chain);
CREATE INDEX idx_wallet_addresses_watched ON wallet_addresses(is_watched) WHERE is_watched = TRUE;

-- Confirmation Tracking Table
CREATE TABLE IF NOT EXISTS confirmation_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tx_hash VARCHAR(66) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    current_confirmations INTEGER DEFAULT 0,
    target_confirmations INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    last_checked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(tx_hash, chain)
);

-- Indexes for confirmation tracking
CREATE INDEX idx_confirmation_tracking_hash ON confirmation_tracking(tx_hash);
CREATE INDEX idx_confirmation_tracking_status ON confirmation_tracking(status);
CREATE INDEX idx_confirmation_tracking_last_checked ON confirmation_tracking(last_checked_at);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL,
    event_category VARCHAR(50) NOT NULL,
    api_key_id UUID REFERENCES api_keys(id),
    description TEXT,
    ip_address INET,
    user_agent TEXT,
    request_data JSONB,
    response_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit log
CREATE INDEX idx_audit_log_event_type ON audit_log(event_type);
CREATE INDEX idx_audit_log_created_at ON audit_log(created_at DESC);
CREATE INDEX idx_audit_log_api_key ON audit_log(api_key_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at trigger to tables
CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_spending_history_updated_at BEFORE UPDATE ON spending_history
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial migration record
INSERT INTO schema_migrations (version, name) VALUES (1, '001_initial_schema');

-- Grant permissions (adjust for your production user)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO crypto_wallet_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO crypto_wallet_user;

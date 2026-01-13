use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// Transaction for spending limit tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transaction {
    pub address: String,
    pub amount: f64,
    pub currency: String,
    pub timestamp: u64,
    pub tx_hash: Option<String>,
    pub status: TransactionStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TransactionStatus {
    Pending,
    Confirmed,
    Failed,
}

/// Spending limit configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpendingLimits {
    pub daily_limit_usd: f64,
    pub weekly_limit_usd: f64,
    pub monthly_limit_usd: f64,
    pub per_transaction_limit_usd: f64,
    pub elevated_auth_threshold_usd: f64,
    pub cooling_off_period_hours: u32,
}

impl Default for SpendingLimits {
    fn default() -> Self {
        Self {
            daily_limit_usd: 5000.0,
            weekly_limit_usd: 20000.0,
            monthly_limit_usd: 50000.0,
            per_transaction_limit_usd: 10000.0,
            elevated_auth_threshold_usd: 5000.0,
            cooling_off_period_hours: 24,
        }
    }
}

/// Spending velocity result
#[derive(Debug, Serialize, Deserialize)]
pub struct VelocityCheck {
    pub allowed: bool,
    pub reason: Option<String>,
    pub daily_spent: f64,
    pub weekly_spent: f64,
    pub monthly_spent: f64,
    pub daily_remaining: f64,
    pub weekly_remaining: f64,
    pub monthly_remaining: f64,
    pub requires_elevated_auth: bool,
    pub requires_cooling_off: bool,
}

/// Transaction monitor with in-memory storage
pub struct TransactionMonitor {
    transactions: Arc<Mutex<HashMap<String, Vec<Transaction>>>>,
    limits: Arc<Mutex<HashMap<String, SpendingLimits>>>,
}

impl TransactionMonitor {
    pub fn new() -> Self {
        Self {
            transactions: Arc::new(Mutex::new(HashMap::new())),
            limits: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Get current timestamp in seconds
    fn now() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
    }

    /// Set custom spending limits for an address
    pub fn set_limits(&self, address: &str, limits: SpendingLimits) {
        let mut limits_map = self.limits.lock().unwrap();
        limits_map.insert(address.to_string(), limits);
    }

    /// Get spending limits for an address (or default)
    pub fn get_limits(&self, address: &str) -> SpendingLimits {
        let limits_map = self.limits.lock().unwrap();
        limits_map
            .get(address)
            .cloned()
            .unwrap_or_else(SpendingLimits::default)
    }

    /// Record a transaction
    pub fn record_transaction(&self, transaction: Transaction) {
        let mut txs = self.transactions.lock().unwrap();
        let address_txs = txs.entry(transaction.address.clone()).or_insert_with(Vec::new);
        address_txs.push(transaction);
    }

    /// Get transactions for an address within a time window
    fn get_transactions_since(&self, address: &str, since: u64) -> Vec<Transaction> {
        let txs = self.transactions.lock().unwrap();
        match txs.get(address) {
            Some(address_txs) => address_txs
                .iter()
                .filter(|tx| tx.timestamp >= since && tx.status == TransactionStatus::Confirmed)
                .cloned()
                .collect(),
            None => Vec::new(),
        }
    }

    /// Calculate total spent in USD within a time window
    fn calculate_spent(&self, address: &str, hours: u32) -> f64 {
        let now = Self::now();
        let since = now - (hours as u64 * 3600);
        let txs = self.get_transactions_since(address, since);
        
        txs.iter()
            .map(|tx| tx.amount) // Amount should be in USD already
            .sum()
    }

    /// Check if transaction is allowed based on velocity limits
    pub fn check_velocity(&self, address: &str, amount_usd: f64) -> VelocityCheck {
        let limits = self.get_limits(address);
        
        // Calculate spent amounts
        let daily_spent = self.calculate_spent(address, 24);
        let weekly_spent = self.calculate_spent(address, 24 * 7);
        let monthly_spent = self.calculate_spent(address, 24 * 30);
        
        // Calculate remaining
        let daily_remaining = (limits.daily_limit_usd - daily_spent).max(0.0);
        let weekly_remaining = (limits.weekly_limit_usd - weekly_spent).max(0.0);
        let monthly_remaining = (limits.monthly_limit_usd - monthly_spent).max(0.0);
        
        // Check per-transaction limit
        if amount_usd > limits.per_transaction_limit_usd {
            return VelocityCheck {
                allowed: false,
                reason: Some(format!(
                    "Transaction amount ${:.2} exceeds per-transaction limit ${:.2}",
                    amount_usd, limits.per_transaction_limit_usd
                )),
                daily_spent,
                weekly_spent,
                monthly_spent,
                daily_remaining,
                weekly_remaining,
                monthly_remaining,
                requires_elevated_auth: true,
                requires_cooling_off: false,
            };
        }
        
        // Check daily limit
        if daily_spent + amount_usd > limits.daily_limit_usd {
            return VelocityCheck {
                allowed: false,
                reason: Some(format!(
                    "Daily limit exceeded. Spent: ${:.2}, Limit: ${:.2}",
                    daily_spent, limits.daily_limit_usd
                )),
                daily_spent,
                weekly_spent,
                monthly_spent,
                daily_remaining,
                weekly_remaining,
                monthly_remaining,
                requires_elevated_auth: false,
                requires_cooling_off: true,
            };
        }
        
        // Check weekly limit
        if weekly_spent + amount_usd > limits.weekly_limit_usd {
            return VelocityCheck {
                allowed: false,
                reason: Some(format!(
                    "Weekly limit exceeded. Spent: ${:.2}, Limit: ${:.2}",
                    weekly_spent, limits.weekly_limit_usd
                )),
                daily_spent,
                weekly_spent,
                monthly_spent,
                daily_remaining,
                weekly_remaining,
                monthly_remaining,
                requires_elevated_auth: false,
                requires_cooling_off: true,
            };
        }
        
        // Check monthly limit
        if monthly_spent + amount_usd > limits.monthly_limit_usd {
            return VelocityCheck {
                allowed: false,
                reason: Some(format!(
                    "Monthly limit exceeded. Spent: ${:.2}, Limit: ${:.2}",
                    monthly_spent, limits.monthly_limit_usd
                )),
                daily_spent,
                weekly_spent,
                monthly_spent,
                daily_remaining,
                weekly_remaining,
                monthly_remaining,
                requires_elevated_auth: false,
                requires_cooling_off: true,
            };
        }
        
        // Check if elevated auth is required
        let requires_elevated_auth = amount_usd >= limits.elevated_auth_threshold_usd;
        
        // Transaction allowed
        VelocityCheck {
            allowed: true,
            reason: None,
            daily_spent,
            weekly_spent,
            monthly_spent,
            daily_remaining,
            weekly_remaining,
            monthly_remaining,
            requires_elevated_auth,
            requires_cooling_off: false,
        }
    }

    /// Get transaction history for an address
    pub fn get_history(&self, address: &str, limit: usize) -> Vec<Transaction> {
        let txs = self.transactions.lock().unwrap();
        match txs.get(address) {
            Some(address_txs) => {
                let mut sorted = address_txs.clone();
                sorted.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
                sorted.into_iter().take(limit).collect()
            }
            None => Vec::new(),
        }
    }

    /// Clear old transactions (older than 90 days)
    pub fn cleanup_old_transactions(&self) {
        let now = Self::now();
        let cutoff = now - (90 * 24 * 3600); // 90 days
        
        let mut txs = self.transactions.lock().unwrap();
        for address_txs in txs.values_mut() {
            address_txs.retain(|tx| tx.timestamp >= cutoff);
        }
    }

    /// Get spending statistics
    pub fn get_statistics(&self, address: &str) -> serde_json::Value {
        let limits = self.get_limits(address);
        let daily_spent = self.calculate_spent(address, 24);
        let weekly_spent = self.calculate_spent(address, 24 * 7);
        let monthly_spent = self.calculate_spent(address, 24 * 30);
        
        serde_json::json!({
            "limits": {
                "daily": limits.daily_limit_usd,
                "weekly": limits.weekly_limit_usd,
                "monthly": limits.monthly_limit_usd,
                "per_transaction": limits.per_transaction_limit_usd,
                "elevated_auth_threshold": limits.elevated_auth_threshold_usd,
            },
            "spent": {
                "daily": daily_spent,
                "weekly": weekly_spent,
                "monthly": monthly_spent,
            },
            "remaining": {
                "daily": (limits.daily_limit_usd - daily_spent).max(0.0),
                "weekly": (limits.weekly_limit_usd - weekly_spent).max(0.0),
                "monthly": (limits.monthly_limit_usd - monthly_spent).max(0.0),
            },
            "percentages": {
                "daily": (daily_spent / limits.daily_limit_usd * 100.0).min(100.0),
                "weekly": (weekly_spent / limits.weekly_limit_usd * 100.0).min(100.0),
                "monthly": (monthly_spent / limits.monthly_limit_usd * 100.0).min(100.0),
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_velocity_check_under_limit() {
        let monitor = TransactionMonitor::new();
        let check = monitor.check_velocity("0x123", 1000.0);
        
        assert!(check.allowed);
        assert!(check.reason.is_none());
        assert!(!check.requires_elevated_auth);
    }

    #[test]
    fn test_velocity_check_exceeds_daily_limit() {
        let monitor = TransactionMonitor::new();
        
        // Record transaction at daily limit
        monitor.record_transaction(Transaction {
            address: "0x123".to_string(),
            amount: 5000.0,
            currency: "USD".to_string(),
            timestamp: TransactionMonitor::now(),
            tx_hash: None,
            status: TransactionStatus::Confirmed,
        });
        
        let check = monitor.check_velocity("0x123", 1000.0);
        
        assert!(!check.allowed);
        assert!(check.reason.is_some());
        assert!(check.requires_cooling_off);
    }

    #[test]
    fn test_elevated_auth_required() {
        let monitor = TransactionMonitor::new();
        let check = monitor.check_velocity("0x123", 6000.0);
        
        assert!(check.allowed);
        assert!(check.requires_elevated_auth);
    }

    #[test]
    fn test_custom_limits() {
        let monitor = TransactionMonitor::new();
        
        let custom_limits = SpendingLimits {
            daily_limit_usd: 1000.0,
            weekly_limit_usd: 5000.0,
            monthly_limit_usd: 15000.0,
            per_transaction_limit_usd: 500.0,
            elevated_auth_threshold_usd: 300.0,
            cooling_off_period_hours: 12,
        };
        
        monitor.set_limits("0x456", custom_limits);
        
        let check = monitor.check_velocity("0x456", 600.0);
        assert!(!check.allowed); // Exceeds per-transaction limit
    }
}

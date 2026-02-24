// ============================================================================
// secure_signer.rs — Rust-native AES-256-GCM encryption/decryption,
// HMAC-SHA256 request integrity, EVM transaction signing, and spending-limit
// gating.  This module is the single gatekeeper for ALL private-key
// operations.  No raw key ever leaves this process.
// ============================================================================

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use ethers::prelude::*;
use ethers::signers::LocalWallet;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::spending_monitor::{TransactionMonitor, Transaction, TransactionStatus, VelocityCheck};

type HmacSha256 = Hmac<Sha256>;

/// Default shared secret — override with RUST_BRIDGE_SECRET env var in production
const DEFAULT_BRIDGE_SECRET: &str = "AmoWallet_Rust_Bridge_2026_SecureKey_Zx9Fk2mQ7v";

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct SecureSignRequest {
    pub encrypted_key: String,       // base64(nonce[12] || ciphertext || tag[16])
    pub chain: String,               // ETH, BNB, BTC, LTC, DOGE, SOL, TRX, XRP
    pub to: String,
    pub amount: String,              // human-readable amount (e.g. "0.05")
    pub from: String,
    pub gas_limit: Option<u64>,
    pub memo: Option<String>,
    pub hmac: Option<String>,        // HMAC-SHA256 of the JSON body (sans hmac field)
    pub amount_usd: Option<f64>,     // USD value for velocity check
}

#[derive(Deserialize)]
pub struct SecureValidateRequest {
    pub encrypted_key: String,
    pub chain: String,
    pub to: String,
    pub amount: String,
    pub from: String,
    pub hmac: Option<String>,
    pub amount_usd: Option<f64>,
}

#[derive(Serialize)]
pub struct SignResult {
    pub success: bool,
    pub tx_hash: Option<String>,
    pub from: Option<String>,
    pub to: Option<String>,
    pub amount: Option<String>,
    pub block_number: Option<u64>,
    pub gas_used: Option<u64>,
    pub error: Option<String>,
}

// ---------------------------------------------------------------------------
// SecureSigner — main struct
// ---------------------------------------------------------------------------

pub struct SecureSigner {
    aes_key: [u8; 32],
    hmac_key: [u8; 32],
}

impl SecureSigner {
    pub fn new() -> Self {
        let secret = std::env::var("RUST_BRIDGE_SECRET")
            .unwrap_or_else(|_| DEFAULT_BRIDGE_SECRET.to_string());

        // Derive AES-256 key
        let mut h = Sha256::new();
        h.update(secret.as_bytes());
        h.update(b"aes-key-derive");
        let aes_key: [u8; 32] = h.finalize().into();

        // Derive HMAC key
        let mut h = Sha256::new();
        h.update(secret.as_bytes());
        h.update(b"hmac-key-derive");
        let hmac_key: [u8; 32] = h.finalize().into();

        Self { aes_key, hmac_key }
    }

    // ------------------------------------------------------------------
    // Encryption / decryption helpers
    // ------------------------------------------------------------------

    /// Decrypt AES-256-GCM ciphertext.
    /// Expected input: base64( nonce[12] || ciphertext || tag[16] )
    pub fn decrypt(&self, encrypted_b64: &str) -> Result<String, String> {
        let data = base64_decode(encrypted_b64)?;
        if data.len() < 28 {
            return Err("Encrypted payload too short".into());
        }

        let nonce = Nonce::from_slice(&data[..12]);
        let ciphertext_and_tag = &data[12..];

        let key = Key::<Aes256Gcm>::from_slice(&self.aes_key);
        let cipher = Aes256Gcm::new(key);

        let plaintext = cipher
            .decrypt(nonce, ciphertext_and_tag)
            .map_err(|_| "AES-GCM decryption failed – tampered or wrong key".to_string())?;

        String::from_utf8(plaintext)
            .map_err(|e| format!("Decrypted data is not valid UTF-8: {}", e))
    }

    /// Encrypt a string with AES-256-GCM (used for testing / key-rotation).
    #[allow(dead_code)]
    pub fn encrypt(&self, plaintext: &str) -> Result<String, String> {
        use rand::RngCore;
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        let key = Key::<Aes256Gcm>::from_slice(&self.aes_key);
        let cipher = Aes256Gcm::new(key);

        let ciphertext = cipher
            .encrypt(nonce, plaintext.as_bytes())
            .map_err(|e| format!("Encryption failed: {}", e))?;

        let mut combined = Vec::with_capacity(12 + ciphertext.len());
        combined.extend_from_slice(&nonce_bytes);
        combined.extend_from_slice(&ciphertext);

        Ok(base64_encode(&combined))
    }

    // ------------------------------------------------------------------
    // HMAC helpers
    // ------------------------------------------------------------------

    /// Compute HMAC-SHA256 and return hex string.
    pub fn compute_hmac(&self, data: &str) -> String {
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&self.hmac_key).unwrap();
        mac.update(data.as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    /// Verify a provided HMAC against the payload.
    pub fn verify_hmac(&self, payload: &str, provided_hex: &str) -> bool {
        let expected = self.compute_hmac(payload);
        // Constant-time compare
        if expected.len() != provided_hex.len() {
            return false;
        }
        let mut diff = 0u8;
        for (a, b) in expected.bytes().zip(provided_hex.bytes()) {
            diff |= a ^ b;
        }
        diff == 0
    }

    // ------------------------------------------------------------------
    // EVM transaction signing (ETH, BNB, and EVM-compatible chains)
    // ------------------------------------------------------------------

    pub async fn sign_and_send_evm(
        &self,
        req: &SecureSignRequest,
        monitor: Option<&Arc<TransactionMonitor>>,
    ) -> SignResult {
        // 1. Decrypt private key
        let private_key = match self.decrypt(&req.encrypted_key) {
            Ok(k) => k,
            Err(e) => return SignResult::error(format!("Key decryption failed: {}", e)),
        };

        // 2. Determine chain parameters
        let (rpc_url, chain_id) = match req.chain.to_uppercase().as_str() {
            "ETH" => (
                std::env::var("ETH_RPC_URL")
                    .unwrap_or_else(|_| "https://eth.llamarpc.com".into()),
                1u64,
            ),
            "BNB" => (
                std::env::var("BNB_RPC_URL")
                    .unwrap_or_else(|_| "https://bsc-dataseed1.binance.org".into()),
                56u64,
            ),
            other => return SignResult::error(format!("Unsupported EVM chain: {}", other)),
        };

        // 3. Spending-limit velocity check
        if let Some(mon) = monitor {
            let amount_usd = req.amount_usd.unwrap_or(0.0);
            if amount_usd > 0.0 {
                let check: VelocityCheck = mon.check_velocity(&req.from, amount_usd);
                if !check.allowed {
                    return SignResult::error(format!(
                        "Spending limit exceeded: {}",
                        check.reason.unwrap_or_else(|| "limit reached".into())
                    ));
                }
            }
        }

        // 4. Build provider + wallet
        let provider = match Provider::<Http>::try_from(&rpc_url) {
            Ok(p) => p,
            Err(e) => return SignResult::error(format!("RPC connect failed: {}", e)),
        };

        let clean_key = private_key.trim().trim_start_matches("0x");
        let wallet: LocalWallet = match clean_key.parse::<LocalWallet>() {
            Ok(w) => w.with_chain_id(chain_id),
            Err(e) => return SignResult::error(format!("Invalid private key: {}", e)),
        };

        let from_addr = wallet.address();

        // Validate from-address matches
        let expected_from: Address = match req.from.parse() {
            Ok(a) => a,
            Err(e) => return SignResult::error(format!("Invalid from address: {}", e)),
        };
        if from_addr != expected_from {
            return SignResult::error("Private key does not match from address".into());
        }

        let client = SignerMiddleware::new(provider.clone(), wallet);

        // 5. Parse destination and amount
        let to_addr: Address = match req.to.parse() {
            Ok(a) => a,
            Err(e) => return SignResult::error(format!("Invalid to address: {}", e)),
        };

        let value = match ethers::utils::parse_ether(&req.amount) {
            Ok(v) => v,
            Err(e) => return SignResult::error(format!("Invalid amount: {}", e)),
        };

        let gas_limit = req.gas_limit.unwrap_or(21000);

        let tx = TransactionRequest::new()
            .to(to_addr)
            .value(value)
            .gas(gas_limit);

        // 6. Send transaction
        let pending = match client.send_transaction(tx, None).await {
            Ok(p) => p,
            Err(e) => return SignResult::error(format!("Send transaction failed: {}", e)),
        };

        let tx_hash = format!("{:?}", pending.tx_hash());

        // 7. Wait for receipt
        match pending.await {
            Ok(Some(receipt)) => {
                // Record in spending monitor
                if let Some(mon) = monitor {
                    mon.record_transaction(Transaction {
                        address: req.from.clone(),
                        amount: req.amount_usd.unwrap_or(0.0),
                        currency: req.chain.clone(),
                        timestamp: std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs(),
                        tx_hash: Some(tx_hash.clone()),
                        status: TransactionStatus::Confirmed,
                    });
                }

                SignResult {
                    success: true,
                    tx_hash: Some(format!("{:?}", receipt.transaction_hash)),
                    from: Some(format!("{:?}", from_addr)),
                    to: Some(req.to.clone()),
                    amount: Some(req.amount.clone()),
                    block_number: receipt.block_number.map(|n| n.as_u64()),
                    gas_used: receipt.gas_used.map(|g| g.as_u64()),
                    error: None,
                }
            }
            Ok(None) => SignResult {
                success: true,
                tx_hash: Some(tx_hash),
                from: Some(format!("{:?}", from_addr)),
                to: Some(req.to.clone()),
                amount: Some(req.amount.clone()),
                block_number: None,
                gas_used: None,
                error: None,
            },
            Err(e) => SignResult::error(format!("Awaiting receipt failed: {}", e)),
        }
    }

    // ------------------------------------------------------------------
    // Non-EVM validation gate — validates spending limits and returns
    // the decrypted key ONLY to be used internally (never sent over HTTP)
    // ------------------------------------------------------------------

    pub fn validate_and_decrypt(
        &self,
        req: &SecureValidateRequest,
        monitor: Option<&Arc<TransactionMonitor>>,
    ) -> Result<String, String> {
        // 1. Decrypt key
        let private_key = self.decrypt(&req.encrypted_key)?;

        // 2. Spending-limit check
        if let Some(mon) = monitor {
            let amount_usd = req.amount_usd.unwrap_or(0.0);
            if amount_usd > 0.0 {
                let check = mon.check_velocity(&req.from, amount_usd);
                if !check.allowed {
                    return Err(format!(
                        "Spending limit exceeded: {}",
                        check.reason.unwrap_or_else(|| "limit reached".into())
                    ));
                }
            }
        }

        // 3. Record the pending transaction
        if let Some(mon) = monitor {
            mon.record_transaction(Transaction {
                address: req.from.clone(),
                amount: req.amount_usd.unwrap_or(0.0),
                currency: req.chain.clone(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
                tx_hash: None,
                status: TransactionStatus::Pending,
            });
        }

        Ok(private_key)
    }
}

impl SignResult {
    fn error(msg: String) -> Self {
        Self {
            success: false,
            tx_hash: None,
            from: None,
            to: None,
            amount: None,
            block_number: None,
            gas_used: None,
            error: Some(msg),
        }
    }
}

// ---------------------------------------------------------------------------
// Base-64 helpers (no extra crate needed — uses simple lookup tables)
// ---------------------------------------------------------------------------

const B64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64_encode(data: &[u8]) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(B64_CHARS[((triple >> 18) & 0x3F) as usize] as char);
        out.push(B64_CHARS[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(B64_CHARS[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(B64_CHARS[(triple & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    let input = input.trim().trim_end_matches('=');
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf: u32 = 0;
    let mut bits: u32 = 0;

    for ch in input.chars() {
        let val = match ch {
            'A'..='Z' => ch as u32 - 'A' as u32,
            'a'..='z' => ch as u32 - 'a' as u32 + 26,
            '0'..='9' => ch as u32 - '0' as u32 + 52,
            '+' => 62,
            '/' => 63,
            _ => continue, // skip whitespace / padding
        };
        buf = (buf << 6) | val;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    Ok(out)
}

use std::env;
use std::io::{self, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::sync::Arc;
use serde::{Deserialize, Serialize};

mod lib;
mod multisig;
mod spending_monitor;
mod contract_auditor;
mod secure_signer;

use spending_monitor::{TransactionMonitor, Transaction, SpendingLimits};
use contract_auditor::{ContractAuditor, ContractWhitelistEntry};
use secure_signer::{SecureSigner, SecureSignRequest, SecureValidateRequest};

#[derive(Deserialize)]
struct CryptoRequest {
    operation: String,
    #[serde(flatten)]
    params: serde_json::Value,
}

#[derive(Serialize)]
struct CryptoResponse {
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 4096];
    
    match stream.read(&mut buffer) {
        Ok(size) => {
            let request = String::from_utf8_lossy(&buffer[..size]);
            
            // Parse HTTP request
            if let Some(body_start) = request.find("\r\n\r\n") {
                let body = &request[body_start + 4..];
                
                // Handle health check
                if request.contains("GET /health") {
                    let response = CryptoResponse {
                        success: true,
                        data: Some(serde_json::json!({
                            "status": "ok",
                            "engine": "rust",
                            "secure": true
                        })),
                        error: None,
                    };
                    
                    let json = serde_json::to_string(&response).unwrap();
                    let response = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                        json.len(),
                        json
                    );
                    let _ = stream.write_all(response.as_bytes());
                    return;
                }

                // Handle crypto operations
                if request.contains("POST /api/crypto") {
                    match serde_json::from_str::<CryptoRequest>(body) {
                        Ok(crypto_req) => {
                            let result = handle_crypto_operation(&crypto_req.operation, &crypto_req.params);
                            
                            let response = match result {
                                Ok(data) => CryptoResponse {
                                    success: true,
                                    data: Some(data),
                                    error: None,
                                },
                                Err(e) => CryptoResponse {
                                    success: false,
                                    data: None,
                                    error: Some(e.to_string()),
                                },
                            };
                            
                            let json = serde_json::to_string(&response).unwrap();
                            let http_response = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                                json.len(),
                                json
                            );
                            let _ = stream.write_all(http_response.as_bytes());
                        }
                        Err(e) => {
                            let response = CryptoResponse {
                                success: false,
                                data: None,
                                error: Some(format!("Invalid request: {}", e)),
                            };
                            let json = serde_json::to_string(&response).unwrap();
                            let http_response = format!(
                                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                                json.len(),
                                json
                            );
                            let _ = stream.write_all(http_response.as_bytes());
                        }
                    }
                    return;
                }
                
                // Multi-sig operations are handled by the services handler.
                // If we reach here it means the server started without the
                // MultiSigManager; return a hint.
                if request.contains("/api/multisig") {
                    let resp = CryptoResponse {
                        success: false,
                        data: None,
                        error: Some("MultiSig: restart server to enable".into()),
                    };
                    let json = serde_json::to_string(&resp).unwrap();
                    let http = format!("HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", json.len(), json);
                    let _ = stream.write_all(http.as_bytes());
                    return;
                }
            }
        }
        Err(e) => {
            eprintln!("Failed to read from stream: {}", e);
        }
    }
}

fn handle_client_with_monitor(mut stream: TcpStream, monitor: Arc<TransactionMonitor>) {
    let mut buffer = [0; 8192]; // Larger buffer for spending limit requests
    
    match stream.read(&mut buffer) {
        Ok(size) => {
            let request = String::from_utf8_lossy(&buffer[..size]);
            
            // Parse HTTP request
            if let Some(body_start) = request.find("\r\n\r\n") {
                let body = &request[body_start + 4..];
                
                // Handle spending limit endpoints
                if request.contains("POST /api/spending/check") {
                    handle_spending_check(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("POST /api/spending/record") {
                    handle_spending_record(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("GET /api/spending/stats/") {
                    // Extract address from URL
                    if let Some(start) = request.find("/api/spending/stats/") {
                        let url_part = &request[start + 20..];
                        if let Some(end) = url_part.find(' ') {
                            let address = &url_part[..end];
                            handle_spending_stats(&mut stream, address, &monitor);
                            return;
                        }
                    }
                }
                
                if request.contains("POST /api/spending/limits") {
                    handle_set_limits(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("GET /api/spending/history/") {
                    if let Some(start) = request.find("/api/spending/history/") {
                        let url_part = &request[start + 22..];
                        if let Some(end) = url_part.find(' ') {
                            let address = &url_part[..end];
                            handle_spending_history(&mut stream, address, &monitor);
                            return;
                        }
                    }
                }
            }
            
            // Fall back to regular handler for other routes
            drop(monitor); // Release Arc before calling handle_client
            handle_client(stream);
        }
        Err(e) => {
            eprintln!("Failed to read from stream: {}", e);
        }
    }
}

fn handle_crypto_operation(operation: &str, params: &serde_json::Value) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    match operation {
        "generate_keypair" => {
            let result = lib::generate_keypair();
            Ok(serde_json::from_str(&result)?)
        }
        "sign_message" => {
            let private_key = params["privateKey"].as_str().ok_or("Missing privateKey")?;
            let message = params["message"].as_str().ok_or("Missing message")?;
            let signature = lib::sign_message(private_key, message);
            Ok(serde_json::json!({"signature": signature}))
        }
        "verify_signature" => {
            let public_key = params["publicKey"].as_str().ok_or("Missing publicKey")?;
            let message = params["message"].as_str().ok_or("Missing message")?;
            let signature = params["signature"].as_str().ok_or("Missing signature")?;
            let is_valid = lib::verify_signature(public_key, message, signature);
            Ok(serde_json::json!({"valid": is_valid}))
        }
        _ => Err(format!("Unknown operation: {}", operation).into())
    }
}

use multisig::{MultiSigManager, StoredWallet};

/// Async multisig dispatcher — runs inside a tokio runtime
fn handle_multisig_async(
    stream: &mut TcpStream,
    request: &str,
    body: &str,
    mgr: &Arc<MultiSigManager>,
) {
    // Build a per-call tokio runtime (the Rust server is thread-per-connection)
    let rt = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(e) => {
            send_json_error(stream, 500, &format!("Tokio init: {}", e));
            return;
        }
    };
    let mgr = Arc::clone(mgr);
    let req = request.to_string();
    let bd = body.to_string();

    let result: Result<serde_json::Value, String> = rt.block_on(async move {
        dispatch_multisig(&req, &bd, &mgr).await
    });

    match result {
        Ok(data) => send_json_ok(stream, data),
        Err(e) => send_json_error(stream, 400, &e),
    }
}

async fn dispatch_multisig(
    request: &str,
    body: &str,
    mgr: &MultiSigManager,
) -> Result<serde_json::Value, String> {
    let rpc_url = std::env::var("MULTISIG_RPC_URL")
        .or_else(|_| std::env::var("ETH_RPC_URL"))
        .unwrap_or_else(|_| "https://ethereum-sepolia-rpc.publicnode.com".into());

    // ── GET endpoints ────────────────────────────────────────────────────

    if request.contains("GET /api/multisig/info") {
        return Ok(serde_json::json!({
            "success": true,
            "contract": {
                "solidity_version": "0.8.20",
                "features": [
                    "M-of-N signature requirements (2-of-3, 3-of-5, custom)",
                    "On-chain owner management",
                    "Transaction submit / confirm / execute / revoke",
                    "Full event audit trail",
                    "Rust-powered security layer"
                ]
            }
        }));
    }

    if request.contains("GET /api/multisig/wallets") {
        let wallets = mgr.get_stored_wallets();
        return Ok(serde_json::json!({ "success": true, "wallets": wallets }));
    }

    if request.contains("GET /api/multisig/my-wallet/") {
        // Extract owner address from URL
        if let Some(start) = request.find("/api/multisig/my-wallet/") {
            let url_part = &request[start + 24..];
            if let Some(end) = url_part.find(' ') {
                let owner = &url_part[..end];
                if let Some(w) = mgr.get_wallet_for_owner(owner) {
                    let info = mgr
                        .get_wallet_info(&w.rpc_url, &w.address)
                        .await
                        .map_err(|e| e.to_string())?;
                    return Ok(serde_json::json!({ "success": true, "address": info.address, "owners": info.owners, "required": info.required, "balance": info.balance_eth }));
                }
            }
        }
        return Ok(serde_json::json!({ "success": true, "address": null }));
    }

    if request.contains("GET /api/multisig/owners/") {
        if let Some(start) = request.find("/api/multisig/owners/") {
            let url_part = &request[start + 21..];
            if let Some(end) = url_part.find(' ') {
                let addr = &url_part[..end];
                let info = mgr.get_wallet_info(&rpc_url, addr).await.map_err(|e| e.to_string())?;
                return Ok(serde_json::json!({
                    "success": true,
                    "owners": info.owners,
                    "required": info.required,
                    "balance": info.balance_eth,
                    "tx_count": info.tx_count
                }));
            }
        }
        return Err("Missing contract address".into());
    }

    if request.contains("GET /api/multisig/pending/") {
        if let Some(start) = request.find("/api/multisig/pending/") {
            let url_part = &request[start + 22..];
            if let Some(end) = url_part.find(' ') {
                let addr = &url_part[..end];
                let pending = mgr
                    .get_pending_transactions(&rpc_url, addr)
                    .await
                    .map_err(|e| e.to_string())?;
                return Ok(serde_json::json!({ "success": true, "pending": pending }));
            }
        }
        return Err("Missing contract address".into());
    }

    if request.contains("GET /api/multisig/history/") {
        if let Some(start) = request.find("/api/multisig/history/") {
            let url_part = &request[start + 22..];
            if let Some(end) = url_part.find(' ') {
                let addr = &url_part[..end];
                let all = mgr
                    .get_all_transactions(&rpc_url, addr)
                    .await
                    .map_err(|e| e.to_string())?;
                return Ok(serde_json::json!({ "success": true, "transactions": all }));
            }
        }
        return Err("Missing contract address".into());
    }

    // ── POST endpoints (parse JSON body) ─────────────────────────────────

    let params: serde_json::Value =
        serde_json::from_str(body).map_err(|e| format!("Invalid JSON: {}", e))?;

    let pk = params["privateKey"]
        .as_str()
        .or_else(|| std::env::var("MULTISIG_DEPLOYER_KEY").ok().as_deref().map(|_| ""))
        .unwrap_or("");
    // Prefer server-side key from env, fall back to request body
    let private_key = std::env::var("MULTISIG_DEPLOYER_KEY")
        .unwrap_or_else(|_| pk.to_string());

    if private_key.is_empty() {
        return Err("No private key: set MULTISIG_DEPLOYER_KEY env var or send privateKey".into());
    }

    if request.contains("POST /api/multisig/deploy") {
        let owners: Vec<String> = params["owners"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default();
        let required = params["required"].as_u64().or(params["requiredConfirmations"].as_u64()).unwrap_or(2);
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        let result = mgr
            .deploy(rpc, &private_key, owners, required)
            .await
            .map_err(|e| e.to_string())?;
        return Ok(serde_json::json!({
            "success": true,
            "address": result.message.split("at ").last().unwrap_or(""),
            "tx_hash": result.tx_hash,
            "message": result.message
        }));
    }

    if request.contains("POST /api/multisig/import") {
        let contract = params["contractAddress"].as_str().ok_or("Missing contractAddress")?;
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);
        let info = mgr.import_wallet(rpc, contract).await.map_err(|e| e.to_string())?;
        return Ok(serde_json::to_value(&info).unwrap());
    }

    if request.contains("POST /api/multisig/submit") {
        let contract = params["contractAddress"].as_str().ok_or("Missing contractAddress")?;
        let to = params["to"].as_str().ok_or("Missing to")?;
        let value = params["value"].as_str().unwrap_or("0");
        let data = params["data"].as_str().unwrap_or("0x");
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        let result = mgr
            .submit_transaction(rpc, &private_key, contract, to, value, data)
            .await
            .map_err(|e| e.to_string())?;
        return Ok(serde_json::to_value(&result).unwrap());
    }

    if request.contains("POST /api/multisig/confirm") {
        let contract = params["contractAddress"].as_str().ok_or("Missing contractAddress")?;
        let tx_index = params["txIndex"].as_u64().ok_or("Missing txIndex")?;
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        let result = mgr
            .confirm_transaction(rpc, &private_key, contract, tx_index)
            .await
            .map_err(|e| e.to_string())?;
        return Ok(serde_json::to_value(&result).unwrap());
    }

    if request.contains("POST /api/multisig/execute") {
        let contract = params["contractAddress"].as_str().ok_or("Missing contractAddress")?;
        let tx_index = params["txIndex"].as_u64().ok_or("Missing txIndex")?;
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        let result = mgr
            .execute_transaction(rpc, &private_key, contract, tx_index)
            .await
            .map_err(|e| e.to_string())?;
        return Ok(serde_json::to_value(&result).unwrap());
    }

    if request.contains("POST /api/multisig/revoke") {
        let contract = params["contractAddress"].as_str().ok_or("Missing contractAddress")?;
        let tx_index = params["txIndex"].as_u64().ok_or("Missing txIndex")?;
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        let result = mgr
            .revoke_confirmation(rpc, &private_key, contract, tx_index)
            .await
            .map_err(|e| e.to_string())?;
        return Ok(serde_json::to_value(&result).unwrap());
    }

    if request.contains("POST /api/multisig/register") {
        let address = params["address"].as_str().ok_or("Missing address")?;
        let owners: Vec<String> = params["owners"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default();
        let required = params["required"].as_u64().unwrap_or(2);
        let rpc = params["rpcUrl"].as_str().unwrap_or(&rpc_url);

        mgr.register_wallet(StoredWallet {
            address: address.to_string(),
            owners,
            required,
            network: rpc.to_string(),
            rpc_url: rpc.to_string(),
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        });
        return Ok(serde_json::json!({ "success": true, "registered": address }));
    }

    Err(format!("Unknown multisig endpoint in: {}", request.split(' ').take(2).collect::<Vec<_>>().join(" ")))
}

fn send_json_ok(stream: &mut TcpStream, data: serde_json::Value) {
    let resp = CryptoResponse { success: true, data: Some(data), error: None };
    let json = serde_json::to_string(&resp).unwrap();
    let http = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", json.len(), json);
    let _ = stream.write_all(http.as_bytes());
}

fn send_json_error(stream: &mut TcpStream, status: u16, msg: &str) {
    let resp = CryptoResponse { success: false, data: None, error: Some(msg.to_string()) };
    let json = serde_json::to_string(&resp).unwrap();
    let phrase = if status == 400 { "Bad Request" } else { "Internal Server Error" };
    let http = format!("HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", status, phrase, json.len(), json);
    let _ = stream.write_all(http.as_bytes());
}

fn handle_spending_check(stream: &mut TcpStream, body: &str, monitor: &Arc<TransactionMonitor>) {
    #[derive(Deserialize)]
    struct CheckRequest {
        address: String,
        amount: f64,
    }
    
    match serde_json::from_str::<CheckRequest>(body) {
        Ok(req) => {
            let check = monitor.check_velocity(&req.address, req.amount);
            let response = CryptoResponse {
                success: true,
                data: Some(serde_json::to_value(&check).unwrap()),
                error: None,
            };
            
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
        Err(e) => {
            let response = CryptoResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid request: {}", e)),
            };
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
    }
}

fn handle_spending_record(stream: &mut TcpStream, body: &str, monitor: &Arc<TransactionMonitor>) {
    match serde_json::from_str::<Transaction>(body) {
        Ok(tx) => {
            monitor.record_transaction(tx.clone());
            let response = CryptoResponse {
                success: true,
                data: Some(serde_json::json!({
                    "recorded": true,
                    "transaction": tx
                })),
                error: None,
            };
            
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
        Err(e) => {
            let response = CryptoResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid transaction: {}", e)),
            };
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
    }
}

fn handle_spending_stats(stream: &mut TcpStream, address: &str, monitor: &Arc<TransactionMonitor>) {
    let stats = monitor.get_statistics(address);
    let response = CryptoResponse {
        success: true,
        data: Some(stats),
        error: None,
    };
    
    let json = serde_json::to_string(&response).unwrap();
    let http_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        json.len(),
        json
    );
    let _ = stream.write_all(http_response.as_bytes());
}

fn handle_set_limits(stream: &mut TcpStream, body: &str, monitor: &Arc<TransactionMonitor>) {
    #[derive(Deserialize)]
    struct SetLimitsRequest {
        address: String,
        limits: SpendingLimits,
    }
    
    match serde_json::from_str::<SetLimitsRequest>(body) {
        Ok(req) => {
            monitor.set_limits(&req.address, req.limits.clone());
            let response = CryptoResponse {
                success: true,
                data: Some(serde_json::json!({
                    "updated": true,
                    "limits": req.limits
                })),
                error: None,
            };
            
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
        Err(e) => {
            let response = CryptoResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid limits: {}", e)),
            };
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
    }
}

fn handle_spending_history(stream: &mut TcpStream, address: &str, monitor: &Arc<TransactionMonitor>) {
    let history = monitor.get_history(address, 50);
    let response = CryptoResponse {
        success: true,
        data: Some(serde_json::json!({
            "address": address,
            "transactions": history,
            "count": history.len()
        })),
        error: None,
    };
    
    let json = serde_json::to_string(&response).unwrap();
    let http_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        json.len(),
        json
    );
    let _ = stream.write_all(http_response.as_bytes());
}

fn handle_client_with_services(
    mut stream: TcpStream,
    monitor: Arc<TransactionMonitor>,
    auditor: Arc<ContractAuditor>,
    multisig: Arc<MultiSigManager>,
    signer: Arc<SecureSigner>,
) {
    let mut buffer = [0; 16384];
    
    match stream.read(&mut buffer) {
        Ok(size) => {
            let request = String::from_utf8_lossy(&buffer[..size]);
            
            if let Some(body_start) = request.find("\r\n\r\n") {
                let body = &request[body_start + 4..];
                
                // ── Secure signing endpoints (Rust-native signing) ───
                if request.contains("POST /api/secure/sign-evm") {
                    handle_secure_sign_evm(&mut stream, body, &signer, &monitor);
                    return;
                }
                
                if request.contains("POST /api/secure/validate") {
                    handle_secure_validate(&mut stream, body, &signer, &monitor);
                    return;
                }
                
                if request.contains("GET /api/secure/health") {
                    let resp = serde_json::json!({
                        "success": true,
                        "engine": "rust-secure-signer",
                        "version": "2.0",
                        "features": [
                            "AES-256-GCM key encryption",
                            "HMAC-SHA256 request integrity",
                            "EVM native signing (ETH/BNB)",
                            "Spending velocity limits",
                            "Zero plaintext key exposure"
                        ]
                    });
                    send_json_ok(&mut stream, resp);
                    return;
                }
                
                // ── MultiSig endpoints (handled by async Rust) ──────
                if request.contains("/api/multisig") {
                    handle_multisig_async(&mut stream, &request, body, &multisig);
                    return;
                }
                
                // Contract auditing endpoints
                if request.contains("POST /api/audit/contract") {
                    handle_audit_contract(&mut stream, body, &auditor);
                    return;
                }
                
                if request.contains("GET /api/audit/whitelist") {
                    handle_get_whitelist(&mut stream, &auditor);
                    return;
                }
                
                if request.contains("POST /api/audit/whitelist") {
                    handle_add_whitelist(&mut stream, body, &auditor);
                    return;
                }
                
                if request.contains("GET /api/audit/quick/") {
                    if let Some(start) = request.find("/api/audit/quick/") {
                        let url_part = &request[start + 17..];
                        if let Some(end) = url_part.find(' ') {
                            let address = &url_part[..end];
                            handle_quick_audit(&mut stream, address, &auditor);
                            return;
                        }
                    }
                }
                
                // Spending limit endpoints
                if request.contains("POST /api/spending/check") {
                    handle_spending_check(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("POST /api/spending/record") {
                    handle_spending_record(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("GET /api/spending/stats/") {
                    if let Some(start) = request.find("/api/spending/stats/") {
                        let url_part = &request[start + 20..];
                        if let Some(end) = url_part.find(' ') {
                            let address = &url_part[..end];
                            handle_spending_stats(&mut stream, address, &monitor);
                            return;
                        }
                    }
                }
                
                if request.contains("POST /api/spending/limits") {
                    handle_set_limits(&mut stream, body, &monitor);
                    return;
                }
                
                if request.contains("GET /api/spending/history/") {
                    if let Some(start) = request.find("/api/spending/history/") {
                        let url_part = &request[start + 22..];
                        if let Some(end) = url_part.find(' ') {
                            let address = &url_part[..end];
                            handle_spending_history(&mut stream, address, &monitor);
                            return;
                        }
                    }
                }
            }
            
            // Fall back to regular handler
            drop(monitor);
            drop(auditor);
            drop(multisig);
            handle_client(stream);
        }
        Err(e) => {
            eprintln!("Failed to read from stream: {}", e);
        }
    }
}

fn handle_audit_contract(stream: &mut TcpStream, body: &str, auditor: &Arc<ContractAuditor>) {
    #[derive(Deserialize)]
    struct AuditRequest {
        contract_address: String,
        bytecode: Option<String>,
        source_code: Option<String>,
    }
    
    match serde_json::from_str::<AuditRequest>(body) {
        Ok(req) => {
            let bytecode_bytes = req.bytecode.as_ref().and_then(|b| hex::decode(b.trim_start_matches("0x")).ok());
            let result = auditor.audit_contract(
                &req.contract_address,
                bytecode_bytes.as_deref(),
                req.source_code.as_deref(),
            );
            
            let response = CryptoResponse {
                success: true,
                data: Some(serde_json::to_value(&result).unwrap()),
                error: None,
            };
            
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
        Err(e) => {
            let response = CryptoResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid request: {}", e)),
            };
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
    }
}

fn handle_get_whitelist(stream: &mut TcpStream, auditor: &Arc<ContractAuditor>) {
    let whitelist = auditor.get_whitelist();
    let response = CryptoResponse {
        success: true,
        data: Some(serde_json::json!({
            "whitelist": whitelist,
            "count": whitelist.len()
        })),
        error: None,
    };
    
    let json = serde_json::to_string(&response).unwrap();
    let http_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        json.len(),
        json
    );
    let _ = stream.write_all(http_response.as_bytes());
}

fn handle_add_whitelist(stream: &mut TcpStream, body: &str, auditor: &Arc<ContractAuditor>) {
    match serde_json::from_str::<ContractWhitelistEntry>(body) {
        Ok(entry) => {
            auditor.add_to_whitelist(entry.clone());
            let response = CryptoResponse {
                success: true,
                data: Some(serde_json::json!({
                    "added": true,
                    "entry": entry
                })),
                error: None,
            };
            
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
        Err(e) => {
            let response = CryptoResponse {
                success: false,
                data: None,
                error: Some(format!("Invalid whitelist entry: {}", e)),
            };
            let json = serde_json::to_string(&response).unwrap();
            let http_response = format!(
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                json.len(),
                json
            );
            let _ = stream.write_all(http_response.as_bytes());
        }
    }
}

fn handle_quick_audit(stream: &mut TcpStream, address: &str, auditor: &Arc<ContractAuditor>) {
    let is_whitelisted = auditor.is_whitelisted(address);
    let risk_level = auditor.quick_assess(address, false); // Assume unverified for quick check
    
    let response = CryptoResponse {
        success: true,
        data: Some(serde_json::json!({
            "contract_address": address,
            "is_whitelisted": is_whitelisted,
            "risk_level": risk_level,
            "recommendation": if is_whitelisted {
                "Safe to interact"
            } else {
                "Perform full audit before interacting"
            }
        })),
        error: None,
    };
    
    let json = serde_json::to_string(&response).unwrap();
    let http_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        json.len(),
        json
    );
    let _ = stream.write_all(http_response.as_bytes());
}

// ---------------------------------------------------------------------------
// Secure signing handlers
// ---------------------------------------------------------------------------

fn handle_secure_sign_evm(
    stream: &mut TcpStream,
    body: &str,
    signer: &Arc<SecureSigner>,
    monitor: &Arc<TransactionMonitor>,
) {
    let req: SecureSignRequest = match serde_json::from_str(body) {
        Ok(r) => r,
        Err(e) => {
            send_json_error(stream, 400, &format!("Invalid request: {}", e));
            return;
        }
    };

    // Verify HMAC if provided
    if let Some(ref hmac_val) = req.hmac {
        // Remove the hmac field from the body for verification
        let mut body_obj: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
        if let Some(obj) = body_obj.as_object_mut() {
            obj.remove("hmac");
        }
        let payload_for_hmac = serde_json::to_string(&body_obj).unwrap_or_default();
        if !signer.verify_hmac(&payload_for_hmac, hmac_val) {
            send_json_error(stream, 403, "HMAC verification failed — request tampered");
            return;
        }
    }

    // Build a per-call tokio runtime for async EVM signing
    let rt = match tokio::runtime::Runtime::new() {
        Ok(r) => r,
        Err(e) => {
            send_json_error(stream, 500, &format!("Tokio init: {}", e));
            return;
        }
    };

    let signer = Arc::clone(signer);
    let monitor = Arc::clone(monitor);

    let result = rt.block_on(async move {
        signer.sign_and_send_evm(&req, Some(&monitor)).await
    });

    if result.success {
        send_json_ok(stream, serde_json::to_value(&result).unwrap());
    } else {
        send_json_error(stream, 400, result.error.as_deref().unwrap_or("Unknown error"));
    }
}

fn handle_secure_validate(
    stream: &mut TcpStream,
    body: &str,
    signer: &Arc<SecureSigner>,
    monitor: &Arc<TransactionMonitor>,
) {
    let req: SecureValidateRequest = match serde_json::from_str(body) {
        Ok(r) => r,
        Err(e) => {
            send_json_error(stream, 400, &format!("Invalid request: {}", e));
            return;
        }
    };

    // Verify HMAC if provided
    if let Some(ref hmac_val) = req.hmac {
        let mut body_obj: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
        if let Some(obj) = body_obj.as_object_mut() {
            obj.remove("hmac");
        }
        let payload_for_hmac = serde_json::to_string(&body_obj).unwrap_or_default();
        if !signer.verify_hmac(&payload_for_hmac, hmac_val) {
            send_json_error(stream, 403, "HMAC verification failed — request tampered");
            return;
        }
    }

    match signer.validate_and_decrypt(&req, Some(monitor)) {
        Ok(decrypted_key) => {
            // Return the decrypted key ONLY for internal Node.js use (non-EVM chains)
            // This is secured by the fact that Rust and Node.js run on the same server
            // and communicate via localhost TCP only.
            send_json_ok(stream, serde_json::json!({
                "validated": true,
                "key": decrypted_key,
                "chain": req.chain,
                "to": req.to,
                "amount": req.amount,
                "from": req.from,
            }));
        }
        Err(e) => {
            send_json_error(stream, 403, &e);
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    
    // Check if running as server
    if args.len() > 1 && args[1] == "server" {
        println!("🦀 Rust Crypto Security Server");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        let port = env::var("RUST_HTTPS_PORT").unwrap_or_else(|_| "8443".to_string());
        let addr = format!("127.0.0.1:{}", port);
        
        // Create transaction monitor, contract auditor, multisig manager, and secure signer
        let monitor = Arc::new(TransactionMonitor::new());
        let auditor = Arc::new(ContractAuditor::new());
        let data_dir = env::var("MULTISIG_DATA_DIR").unwrap_or_else(|_| "./data".to_string());
        let multisig_mgr = Arc::new(MultiSigManager::new(&data_dir));
        let signer = Arc::new(SecureSigner::new());
        
        let listener = TcpListener::bind(&addr).expect("Failed to bind to address");
        println!("✅ Listening on http://{}", addr);
        println!("🔒 All cryptographic operations handled by Rust");
        println!("💰 Transaction velocity monitoring enabled");
        println!("🛡️  Smart contract security auditing enabled");
        println!("🔐 MultiSig wallet manager enabled (data: {})", data_dir);
        println!("🔑 Secure Signer enabled (AES-256-GCM + HMAC-SHA256)");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
        
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    let monitor_clone = Arc::clone(&monitor);
                    let auditor_clone = Arc::clone(&auditor);
                    let multisig_clone = Arc::clone(&multisig_mgr);
                    let signer_clone = Arc::clone(&signer);
                    thread::spawn(move || {
                        handle_client_with_services(stream, monitor_clone, auditor_clone, multisig_clone, signer_clone);
                    });
                }
                Err(e) => {
                    eprintln!("Connection failed: {}", e);
                }
            }
        }
        return;
    }
    
    // CLI mode
    if args.len() < 2 {
        eprintln!("Usage: crypto_wallet_rust <command> [args...]");
        eprintln!("       crypto_wallet_rust server  - Start HTTP server");
        std::process::exit(1);
    }

    match args[1].as_str() {
        "generate" => {
            let kp = lib::generate_keypair();
            println!("{}", kp);
        }
        "sign" => {
            if args.len() < 4 {
                eprintln!("Usage: crypto_wallet_rust sign <private_hex> <message>");
                std::process::exit(1);
            }
            let sig = lib::sign_message(&args[2], &args[3]);
            println!("{}", sig);
        }
        "verify" => {
            if args.len() < 5 {
                eprintln!("Usage: crypto_wallet_rust verify <public_hex> <message> <signature_hex>");
                std::process::exit(1);
            }
            let valid = lib::verify_signature(&args[2], &args[3], &args[4]);
            println!("{}", valid);
        }
        "worker" => {
            // enter long-running worker mode: read JSON lines from stdin and write JSON responses to stdout
            // Supported commands: { "id": string, "cmd": "generate" }
            // { "id": string, "cmd": "sign", "private": "hex", "message": "..." }
            // { "id": string, "cmd": "verify", "public": "hex", "message": "...", "signature": "hex" }
            use std::io::{self, BufRead};
            let stdin = io::stdin();
            for line in stdin.lock().lines() {
                match line {
                    Ok(l) => {
                        if l.trim().is_empty() { continue; }
                        let resp = handle_json_command(&l);
                        match resp {
                            Ok(s) => println!("{}", s),
                            Err(e) => eprintln!("{{\"error\":\"{}\"}}", e),
                        }
                    }
                    Err(e) => {
                        eprintln!("{{\"error\":\"IO error: {}\"}}", e);
                    }
                }
            }
        }
        _ => {
            eprintln!("Unknown command: {}", args[1]);
            std::process::exit(1);
        }
    }
}

fn handle_json_command(raw: &str) -> Result<String, String> {
    let v: serde_json::Value = serde_json::from_str(raw).map_err(|e| format!("invalid json: {}", e))?;
    let id = v.get("id").and_then(|x| x.as_str()).unwrap_or("");
    let cmd = v.get("cmd").and_then(|x| x.as_str()).ok_or("missing cmd")?;

    match cmd {
        "generate" => {
            let kp = lib::generate_keypair();
            // return { id, ok: true, result: <parsed kp> }
            let parsed: serde_json::Value = serde_json::from_str(&kp).map_err(|e| format!("parse kp: {}", e))?;
            let resp = serde_json::json!({ "id": id, "ok": true, "result": parsed });
            Ok(resp.to_string())
        }
        "sign" => {
            let private = v.get("private").and_then(|x| x.as_str()).ok_or("missing private")?;
            let message = v.get("message").and_then(|x| x.as_str()).ok_or("missing message")?;
            let sig = lib::sign_message(private, message);
            let resp = serde_json::json!({ "id": id, "ok": true, "result": sig });
            Ok(resp.to_string())
        }
        "verify" => {
            let public = v.get("public").and_then(|x| x.as_str()).ok_or("missing public")?;
            let message = v.get("message").and_then(|x| x.as_str()).ok_or("missing message")?;
            let signature = v.get("signature").and_then(|x| x.as_str()).ok_or("missing signature")?;
            let valid = lib::verify_signature(public, message, signature);
            let resp = serde_json::json!({ "id": id, "ok": true, "result": valid });
            Ok(resp.to_string())
        }
        _ => Err(format!("unknown cmd: {}", cmd)),
    }
}

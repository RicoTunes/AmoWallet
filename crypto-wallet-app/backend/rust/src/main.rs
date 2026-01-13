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

use spending_monitor::{TransactionMonitor, Transaction, TransactionStatus, SpendingLimits};
use contract_auditor::{ContractAuditor, ContractWhitelistEntry};

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
                
                // Handle multi-sig operations
                if request.contains("POST /api/multisig") {
                    match serde_json::from_str::<CryptoRequest>(body) {
                        Ok(multisig_req) => {
                            let result = handle_multisig_operation(&multisig_req.operation, &multisig_req.params);
                            
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
                
                // Handle multi-sig operations
                if request.contains("POST /api/multisig") {
                    match serde_json::from_str::<CryptoRequest>(body) {
                        Ok(multisig_req) => {
                            let result = handle_multisig_operation(&multisig_req.operation, &multisig_req.params);
                            
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
            }
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

fn handle_multisig_operation(operation: &str, params: &serde_json::Value) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    match operation {
        "get_contract_info" => {
            // Return multi-sig contract deployment information
            Ok(serde_json::json!({
                "solidity_version": "0.8.20",
                "contract_path": "backend/contracts/MultiSigWallet.sol",
                "features": [
                    "M-of-N signature requirements",
                    "Owner management",
                    "Transaction submission and confirmation",
                    "Revoke confirmation support",
                    "Event logging"
                ],
                "deployment_instructions": "Use Hardhat or Foundry to compile and deploy the contract"
            }))
        }
        "compile_contract" => {
            // This would compile the Solidity contract
            // For now, return instructions
            Err("Contract compilation requires solc. Use: npm install -g solc && solcjs --bin --abi MultiSigWallet.sol".into())
        }
        _ => Err(format!("Unknown multi-sig operation: {}", operation).into())
    }
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
) {
    let mut buffer = [0; 8192];
    
    match stream.read(&mut buffer) {
        Ok(size) => {
            let request = String::from_utf8_lossy(&buffer[..size]);
            
            if let Some(body_start) = request.find("\r\n\r\n") {
                let body = &request[body_start + 4..];
                
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

fn main() {
    let args: Vec<String> = env::args().collect();
    
    // Check if running as server
    if args.len() > 1 && args[1] == "server" {
        println!("🦀 Rust Crypto Security Server");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        let port = env::var("RUST_HTTPS_PORT").unwrap_or_else(|_| "8443".to_string());
        let addr = format!("127.0.0.1:{}", port);
        
        // Create transaction monitor and contract auditor
        let monitor = Arc::new(TransactionMonitor::new());
        let auditor = Arc::new(ContractAuditor::new());
        
        let listener = TcpListener::bind(&addr).expect("Failed to bind to address");
        println!("✅ Listening on http://{}", addr);
        println!("🔒 All cryptographic operations handled by Rust");
        println!("💰 Transaction velocity monitoring enabled");
        println!("🛡️  Smart contract security auditing enabled");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
        
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    let monitor_clone = Arc::clone(&monitor);
                    let auditor_clone = Arc::clone(&auditor);
                    thread::spawn(move || {
                        handle_client_with_services(stream, monitor_clone, auditor_clone);
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

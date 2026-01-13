use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use moka::future::Cache;
use serde::{Deserialize, Serialize};
use std::{sync::Arc, time::Duration};
use tower_http::cors::{Any, CorsLayer};

#[derive(Clone)]
struct AppState {
    balance_cache: Cache<String, BalanceResponse>,
    tx_cache: Cache<String, TransactionsResponse>,
    client: reqwest::Client,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BalanceResponse {
    success: bool,
    network: String,
    address: String,
    balance: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransactionsResponse {
    success: bool,
    network: String,
    address: String,
    transactions: Vec<serde_json::Value>,
    count: usize,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    success: bool,
    error: String,
}

#[tokio::main]
async fn main() {
    // Initialize caches with 60 second TTL
    let balance_cache = Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(60))
        .build();

    let tx_cache = Cache::builder()
        .max_capacity(10_000)
        .time_to_live(Duration::from_secs(60))
        .build();

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .unwrap();

    let state = AppState {
        balance_cache,
        tx_cache,
        client,
    };

    // Setup CORS
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/api/blockchain/balance/:network/:address", get(get_balance))
        .route("/api/blockchain/transactions/:network/:address", get(get_transactions))
        .route("/api/blockchain/confirmations/:chain/:txhash", get(get_confirmations))
        .layer(cors)
        .with_state(Arc::new(state));

    println!("🚀 Rust API Server Starting...");
    println!("📡 Server running on http://0.0.0.0:3000");
    println!("🦀 Powered by Rust + Axum + Moka Cache");
    println!("⚡ Cache TTL: 60 seconds");

    // Start server
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .unwrap();
    
    axum::serve(listener, app).await.unwrap();
}

async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "success": true,
        "status": "ok",
        "engine": "rust",
        "cache": "moka"
    }))
}

async fn get_balance(
    State(state): State<Arc<AppState>>,
    Path((network, address)): Path<(String, String)>,
) -> Result<Json<BalanceResponse>, (StatusCode, Json<ErrorResponse>)> {
    let cache_key = format!("balance_{}_{}", network, address);

    // Check cache first
    if let Some(cached) = state.balance_cache.get(&cache_key).await {
        println!("✅ Cache HIT: {}", cache_key);
        return Ok(Json(cached));
    }

    println!("❌ Cache MISS: {}", cache_key);

    // Fetch from blockchain API
    let result = match network.as_str() {
        "BTC" => fetch_bitcoin_balance(&state.client, &address).await,
        _ => Err("Unsupported network".to_string()),
    };

    match result {
        Ok(balance) => {
            let response = BalanceResponse {
                success: true,
                network: network.clone(),
                address: address.clone(),
                balance,
            };

            // Store in cache
            state.balance_cache.insert(cache_key, response.clone()).await;

            Ok(Json(response))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                success: false,
                error: e,
            }),
        )),
    }
}

async fn get_transactions(
    State(state): State<Arc<AppState>>,
    Path((network, address)): Path<(String, String)>,
) -> Result<Json<TransactionsResponse>, (StatusCode, Json<ErrorResponse>)> {
    let cache_key = format!("tx_{}_{}", network, address);

    // Check cache first
    if let Some(cached) = state.tx_cache.get(&cache_key).await {
        println!("✅ Cache HIT: {}", cache_key);
        return Ok(Json(cached));
    }

    println!("❌ Cache MISS: {}", cache_key);

    // Fetch from blockchain API
    let result = match network.as_str() {
        "BTC" => fetch_bitcoin_transactions(&state.client, &address).await,
        _ => Err("Unsupported network".to_string()),
    };

    match result {
        Ok(transactions) => {
            let count = transactions.len();
            let response = TransactionsResponse {
                success: true,
                network: network.clone(),
                address: address.clone(),
                transactions,
                count,
            };

            // Store in cache
            state.tx_cache.insert(cache_key, response.clone()).await;

            Ok(Json(response))
        }
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                success: false,
                error: e,
            }),
        )),
    }
}

async fn get_confirmations(
    State(state): State<Arc<AppState>>,
    Path((chain, txhash)): Path<(String, String)>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorResponse>)> {
    let result = match chain.as_str() {
        "BTC" | "bitcoin" => fetch_bitcoin_confirmations(&state.client, &txhash).await,
        _ => Err("Unsupported chain".to_string()),
    };

    match result {
        Ok(confirmations) => Ok(Json(serde_json::json!({
            "success": true,
            "chain": chain,
            "txHash": txhash,
            "confirmations": confirmations
        }))),
        Err(e) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorResponse {
                success: false,
                error: e,
            }),
        )),
    }
}

// Bitcoin API functions
async fn fetch_bitcoin_balance(client: &reqwest::Client, address: &str) -> Result<String, String> {
    let url = format!("https://blockstream.info/api/address/{}", address);
    
    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch balance: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))?;

    // Calculate balance from chain stats
    let funded = data["chain_stats"]["funded_txo_sum"]
        .as_u64()
        .unwrap_or(0);
    let spent = data["chain_stats"]["spent_txo_sum"]
        .as_u64()
        .unwrap_or(0);
    
    let balance_satoshis = funded.saturating_sub(spent);
    let balance_btc = balance_satoshis as f64 / 100_000_000.0;

    Ok(balance_btc.to_string())
}

async fn fetch_bitcoin_transactions(
    client: &reqwest::Client,
    address: &str,
) -> Result<Vec<serde_json::Value>, String> {
    // Fetch confirmed transactions
    let confirmed_url = format!("https://blockstream.info/api/address/{}/txs", address);
    let confirmed_response = client
        .get(&confirmed_url)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch transactions: {}", e))?;

    let mut confirmed_txs: Vec<serde_json::Value> = if confirmed_response.status().is_success() {
        confirmed_response
            .json()
            .await
            .map_err(|e| format!("Failed to parse transactions: {}", e))?
    } else {
        Vec::new()
    };

    // Fetch mempool (pending) transactions
    let mempool_url = format!("https://blockstream.info/api/address/{}/txs/mempool", address);
    let mempool_response = client
        .get(&mempool_url)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch mempool: {}", e))?;

    if mempool_response.status().is_success() {
        let mut mempool_txs: Vec<serde_json::Value> = mempool_response
            .json()
            .await
            .map_err(|e| format!("Failed to parse mempool: {}", e))?;

        // Mark mempool transactions as pending
        for tx in &mut mempool_txs {
            if let Some(obj) = tx.as_object_mut() {
                obj.insert("isPending".to_string(), serde_json::Value::Bool(true));
                obj.insert("confirmations".to_string(), serde_json::Value::Number(0.into()));
            }
        }

        // Prepend mempool txs to confirmed txs
        mempool_txs.extend(confirmed_txs);
        confirmed_txs = mempool_txs;
    }

    Ok(confirmed_txs)
}

async fn fetch_bitcoin_confirmations(
    client: &reqwest::Client,
    txhash: &str,
) -> Result<u32, String> {
    let url = format!("https://blockstream.info/api/tx/{}/status", txhash);
    
    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch tx status: {}", e))?;

    if !response.status().is_success() {
        return Ok(0);
    }

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse tx status: {}", e))?;

    let confirmed = data["confirmed"].as_bool().unwrap_or(false);
    if !confirmed {
        return Ok(0);
    }

    // Get current block height
    let height_url = "https://blockstream.info/api/blocks/tip/height";
    let height_response = client
        .get(height_url)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch block height: {}", e))?;

    let current_height: u32 = height_response
        .text()
        .await
        .map_err(|e| format!("Failed to parse height: {}", e))?
        .trim()
        .parse()
        .unwrap_or(0);

    let tx_height = data["block_height"].as_u64().unwrap_or(0) as u32;
    let confirmations = if current_height > tx_height {
        current_height - tx_height + 1
    } else {
        0
    };

    Ok(confirmations)
}


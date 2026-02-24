use ethers::{
    abi::{self, Token},
    contract::abigen,
    core::types::{Address, Bytes, TransactionReceipt, U256},
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer},
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

// ── ABI bindings from the contract ──────────────────────────────────────────

abigen!(
    MultiSigWalletContract,
    r#"[
        function submitTransaction(address to, uint256 value, bytes memory data) public
        function confirmTransaction(uint256 txIndex) public
        function executeTransaction(uint256 txIndex) public
        function revokeConfirmation(uint256 txIndex) public
        function getOwners() public view returns (address[] memory)
        function getTransactionCount() public view returns (uint256)
        function getTransaction(uint256 txIndex) public view returns (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations)
        function getBalance() public view returns (uint256)
        function numConfirmationsRequired() public view returns (uint256)
        function isOwner(address) public view returns (bool)
        function isConfirmed(uint256, address) public view returns (bool)
        event Deposit(address indexed sender, uint256 amount, uint256 balance)
        event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data)
        event ConfirmTransaction(address indexed owner, uint256 indexed txIndex)
        event ExecuteTransaction(address indexed owner, uint256 indexed txIndex)
        event RevokeConfirmation(address indexed owner, uint256 indexed txIndex)
    ]"#,
);

// ── Data models ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultiSigWalletInfo {
    pub address: String,
    pub owners: Vec<String>,
    pub required: u64,
    pub balance: String,
    pub balance_eth: String,
    pub tx_count: u64,
    pub network: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingTransaction {
    pub tx_index: u64,
    pub to: String,
    pub value: String,
    pub value_eth: String,
    pub data: String,
    pub executed: bool,
    pub num_confirmations: u64,
    pub required_confirmations: u64,
    pub confirmed_by: Vec<String>,
    pub can_execute: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TxResult {
    pub success: bool,
    pub tx_hash: String,
    pub tx_index: Option<u64>,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredWallet {
    pub address: String,
    pub owners: Vec<String>,
    pub required: u64,
    pub network: String,
    pub rpc_url: String,
    pub created_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WalletStore {
    wallets: HashMap<String, StoredWallet>,
}

// ── MultiSig Manager ───────────────────────────────────────────────────────

pub struct MultiSigManager {
    store_path: PathBuf,
    wallets: Arc<RwLock<WalletStore>>,
}

impl MultiSigManager {
    /// Create manager with persistent JSON storage
    pub fn new(data_dir: &str) -> Self {
        let store_path = PathBuf::from(data_dir).join("multisig_wallets.json");

        let wallets = if store_path.exists() {
            match fs::read_to_string(&store_path) {
                Ok(content) => serde_json::from_str(&content).unwrap_or(WalletStore {
                    wallets: HashMap::new(),
                }),
                Err(_) => WalletStore {
                    wallets: HashMap::new(),
                },
            }
        } else {
            WalletStore {
                wallets: HashMap::new(),
            }
        };

        Self {
            store_path,
            wallets: Arc::new(RwLock::new(wallets)),
        }
    }

    fn save_store(&self) {
        if let Ok(wallets) = self.wallets.read() {
            if let Ok(json) = serde_json::to_string_pretty(&*wallets) {
                let _ = fs::create_dir_all(
                    self.store_path.parent().unwrap_or(&PathBuf::from(".")),
                );
                let _ = fs::write(&self.store_path, json);
            }
        }
    }

    async fn build_client(
        rpc_url: &str,
        private_key: &str,
    ) -> Result<
        Arc<SignerMiddleware<Provider<Http>, LocalWallet>>,
        Box<dyn std::error::Error + Send + Sync>,
    > {
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let chain_id = provider.get_chainid().await?.as_u64();
        let wallet: LocalWallet = private_key
            .trim_start_matches("0x")
            .parse::<LocalWallet>()?
            .with_chain_id(chain_id);

        Ok(Arc::new(SignerMiddleware::new(provider, wallet)))
    }

    // ── Deploy ───────────────────────────────────────────────────────────

    /// Deploy a new MultiSig wallet contract on-chain.
    pub async fn deploy(
        &self,
        rpc_url: &str,
        private_key: &str,
        owners: Vec<String>,
        required_confirmations: u64,
    ) -> Result<TxResult, Box<dyn std::error::Error + Send + Sync>> {
        if owners.len() < 2 {
            return Err("At least 2 owners required".into());
        }
        if required_confirmations < 1 || required_confirmations > owners.len() as u64 {
            return Err(format!(
                "required_confirmations must be 1-{}",
                owners.len()
            )
            .into());
        }

        let owner_addrs: Vec<Address> = owners
            .iter()
            .map(|o| o.parse::<Address>())
            .collect::<Result<Vec<_>, _>>()?;

        let client = Self::build_client(rpc_url, private_key).await?;

        // Embedded compiled bytecode from MultiSigWallet.sol (0.8.20, optimized)
        let bytecode_hex = include_str!("multisig_bytecode.hex");
        let bytecode_bytes = hex::decode(bytecode_hex.trim())?;

        // ABI-encode constructor args: (address[] owners, uint256 required)
        let constructor_args = abi::encode(&[
            Token::Array(owner_addrs.iter().map(|a| Token::Address(*a)).collect()),
            Token::Uint(U256::from(required_confirmations)),
        ]);

        let mut deploy_data = bytecode_bytes;
        deploy_data.extend_from_slice(&constructor_args);

        let tx = ethers::core::types::TransactionRequest::new().data(Bytes::from(deploy_data));
        let pending_tx = client.send_transaction(tx, None).await?;
        let receipt: TransactionReceipt = pending_tx
            .await?
            .ok_or("Deploy transaction receipt not available")?;

        let contract_address = receipt
            .contract_address
            .ok_or("Contract address not in receipt")?;
        let addr_str = format!("{:?}", contract_address);

        // Store the wallet
        {
            let mut store = self
                .wallets
                .write()
                .map_err(|e| format!("Lock: {}", e))?;
            store.wallets.insert(
                addr_str.clone(),
                StoredWallet {
                    address: addr_str.clone(),
                    owners: owners.clone(),
                    required: required_confirmations,
                    network: rpc_url.to_string(),
                    rpc_url: rpc_url.to_string(),
                    created_at: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs(),
                },
            );
        }
        self.save_store();

        Ok(TxResult {
            success: true,
            tx_hash: format!("{:?}", receipt.transaction_hash),
            tx_index: None,
            message: format!("MultiSig deployed at {}", addr_str),
        })
    }

    /// Import an already-deployed multisig contract
    pub async fn import_wallet(
        &self,
        rpc_url: &str,
        contract_address: &str,
    ) -> Result<MultiSigWalletInfo, Box<dyn std::error::Error + Send + Sync>> {
        let addr: Address = contract_address.parse()?;
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let contract = MultiSigWalletContract::new(addr, Arc::new(provider));

        let owners_raw = contract.get_owners().call().await?;
        let owners: Vec<String> = owners_raw.iter().map(|a| format!("{:?}", a)).collect();
        let required = contract.num_confirmations_required().call().await?.as_u64();
        let balance = contract.get_balance().call().await?;
        let tx_count = contract.get_transaction_count().call().await?.as_u64();
        let balance_eth = wei_to_eth(balance);

        // Persist
        {
            let mut store = self
                .wallets
                .write()
                .map_err(|e| format!("Lock: {}", e))?;
            store.wallets.insert(
                contract_address.to_string(),
                StoredWallet {
                    address: contract_address.to_string(),
                    owners: owners.clone(),
                    required,
                    network: rpc_url.to_string(),
                    rpc_url: rpc_url.to_string(),
                    created_at: now_secs(),
                },
            );
        }
        self.save_store();

        Ok(MultiSigWalletInfo {
            address: contract_address.to_string(),
            owners,
            required,
            balance: balance.to_string(),
            balance_eth,
            tx_count,
            network: rpc_url.to_string(),
        })
    }

    // ── Queries ──────────────────────────────────────────────────────────

    /// Get full wallet info from on-chain state
    pub async fn get_wallet_info(
        &self,
        rpc_url: &str,
        contract_address: &str,
    ) -> Result<MultiSigWalletInfo, Box<dyn std::error::Error + Send + Sync>> {
        let addr: Address = contract_address.parse()?;
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let contract = MultiSigWalletContract::new(addr, Arc::new(provider));

        let owners_raw = contract.get_owners().call().await?;
        let owners: Vec<String> = owners_raw.iter().map(|a| format!("{:?}", a)).collect();
        let required = contract.num_confirmations_required().call().await?.as_u64();
        let balance = contract.get_balance().call().await?;
        let tx_count = contract.get_transaction_count().call().await?.as_u64();

        Ok(MultiSigWalletInfo {
            address: contract_address.to_string(),
            owners,
            required,
            balance: balance.to_string(),
            balance_eth: wei_to_eth(balance),
            tx_count,
            network: rpc_url.to_string(),
        })
    }

    /// Get all pending (non-executed) transactions
    pub async fn get_pending_transactions(
        &self,
        rpc_url: &str,
        contract_address: &str,
    ) -> Result<Vec<PendingTransaction>, Box<dyn std::error::Error + Send + Sync>> {
        let addr: Address = contract_address.parse()?;
        let provider = Arc::new(Provider::<Http>::try_from(rpc_url)?);
        let contract = MultiSigWalletContract::new(addr, provider);

        let tx_count = contract.get_transaction_count().call().await?.as_u64();
        let required = contract.num_confirmations_required().call().await?.as_u64();
        let owners_raw = contract.get_owners().call().await?;

        let mut pending = Vec::new();
        for idx in 0..tx_count {
            let (to, value, data, executed, num_conf) = contract
                .get_transaction(U256::from(idx))
                .call()
                .await?;

            if executed {
                continue;
            }

            // Check which owners have confirmed
            let mut confirmed_by = Vec::new();
            for owner in &owners_raw {
                if contract
                    .is_confirmed(U256::from(idx), *owner)
                    .call()
                    .await
                    .unwrap_or(false)
                {
                    confirmed_by.push(format!("{:?}", owner));
                }
            }

            pending.push(PendingTransaction {
                tx_index: idx,
                to: format!("{:?}", to),
                value: value.to_string(),
                value_eth: wei_to_eth(value),
                data: format!("0x{}", hex::encode(&data)),
                executed,
                num_confirmations: num_conf.as_u64(),
                required_confirmations: required,
                confirmed_by,
                can_execute: num_conf.as_u64() >= required,
            });
        }

        Ok(pending)
    }

    /// Get all transactions (including executed, for history)
    pub async fn get_all_transactions(
        &self,
        rpc_url: &str,
        contract_address: &str,
    ) -> Result<Vec<PendingTransaction>, Box<dyn std::error::Error + Send + Sync>> {
        let addr: Address = contract_address.parse()?;
        let provider = Arc::new(Provider::<Http>::try_from(rpc_url)?);
        let contract = MultiSigWalletContract::new(addr, provider);

        let tx_count = contract.get_transaction_count().call().await?.as_u64();
        let required = contract.num_confirmations_required().call().await?.as_u64();

        let mut txs = Vec::new();
        for idx in 0..tx_count {
            let (to, value, data, executed, num_conf) = contract
                .get_transaction(U256::from(idx))
                .call()
                .await?;

            txs.push(PendingTransaction {
                tx_index: idx,
                to: format!("{:?}", to),
                value: value.to_string(),
                value_eth: wei_to_eth(value),
                data: format!("0x{}", hex::encode(&data)),
                executed,
                num_confirmations: num_conf.as_u64(),
                required_confirmations: required,
                confirmed_by: vec![], // skip per-owner check for history
                can_execute: num_conf.as_u64() >= required && !executed,
            });
        }

        Ok(txs)
    }

    // ── Write operations (all require signer) ────────────────────────────

    /// Submit a new transaction to the multisig
    pub async fn submit_transaction(
        &self,
        rpc_url: &str,
        private_key: &str,
        contract_address: &str,
        to: &str,
        value_wei: &str,
        data: &str,
    ) -> Result<TxResult, Box<dyn std::error::Error + Send + Sync>> {
        let client = Self::build_client(rpc_url, private_key).await?;
        let addr: Address = contract_address.parse()?;
        let contract = MultiSigWalletContract::new(addr, client);

        let to_addr: Address = to.parse()?;
        let value = U256::from_dec_str(value_wei)?;
        let tx_data = parse_data(data)?;

        let tx = contract
            .submit_transaction(to_addr, value, tx_data)
            .send()
            .await?
            .await?;

        let receipt = tx.ok_or("No receipt for submit_transaction")?;

        // Get the new tx index = count - 1
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let read_contract = MultiSigWalletContract::new(addr, Arc::new(provider));
        let count = read_contract
            .get_transaction_count()
            .call()
            .await?
            .as_u64();

        Ok(TxResult {
            success: true,
            tx_hash: format!("{:?}", receipt.transaction_hash),
            tx_index: Some(count.saturating_sub(1)),
            message: format!("Transaction #{} submitted", count.saturating_sub(1)),
        })
    }

    /// Confirm (approve) a pending transaction
    pub async fn confirm_transaction(
        &self,
        rpc_url: &str,
        private_key: &str,
        contract_address: &str,
        tx_index: u64,
    ) -> Result<TxResult, Box<dyn std::error::Error + Send + Sync>> {
        let client = Self::build_client(rpc_url, private_key).await?;
        let addr: Address = contract_address.parse()?;
        let contract = MultiSigWalletContract::new(addr, client);

        let tx = contract
            .confirm_transaction(U256::from(tx_index))
            .send()
            .await?
            .await?;
        let receipt = tx.ok_or("No receipt for confirm_transaction")?;

        Ok(TxResult {
            success: true,
            tx_hash: format!("{:?}", receipt.transaction_hash),
            tx_index: Some(tx_index),
            message: format!("Transaction #{} confirmed", tx_index),
        })
    }

    /// Execute a fully-confirmed transaction
    pub async fn execute_transaction(
        &self,
        rpc_url: &str,
        private_key: &str,
        contract_address: &str,
        tx_index: u64,
    ) -> Result<TxResult, Box<dyn std::error::Error + Send + Sync>> {
        let client = Self::build_client(rpc_url, private_key).await?;
        let addr: Address = contract_address.parse()?;
        let contract = MultiSigWalletContract::new(addr, client);

        let tx = contract
            .execute_transaction(U256::from(tx_index))
            .send()
            .await?
            .await?;
        let receipt = tx.ok_or("No receipt for execute_transaction")?;

        Ok(TxResult {
            success: true,
            tx_hash: format!("{:?}", receipt.transaction_hash),
            tx_index: Some(tx_index),
            message: format!("Transaction #{} executed", tx_index),
        })
    }

    /// Revoke a previous confirmation
    pub async fn revoke_confirmation(
        &self,
        rpc_url: &str,
        private_key: &str,
        contract_address: &str,
        tx_index: u64,
    ) -> Result<TxResult, Box<dyn std::error::Error + Send + Sync>> {
        let client = Self::build_client(rpc_url, private_key).await?;
        let addr: Address = contract_address.parse()?;
        let contract = MultiSigWalletContract::new(addr, client);

        let tx = contract
            .revoke_confirmation(U256::from(tx_index))
            .send()
            .await?
            .await?;
        let receipt = tx.ok_or("No receipt for revoke_confirmation")?;

        Ok(TxResult {
            success: true,
            tx_hash: format!("{:?}", receipt.transaction_hash),
            tx_index: Some(tx_index),
            message: format!("Confirmation for #{} revoked", tx_index),
        })
    }

    // ── Wallet storage ───────────────────────────────────────────────────

    /// Get all stored wallets
    pub fn get_stored_wallets(&self) -> Vec<StoredWallet> {
        self.wallets
            .read()
            .map(|s| s.wallets.values().cloned().collect())
            .unwrap_or_default()
    }

    /// Find stored wallet where given address is an owner
    pub fn get_wallet_for_owner(&self, owner_address: &str) -> Option<StoredWallet> {
        let lower = owner_address.to_lowercase();
        self.wallets.read().ok().and_then(|s| {
            s.wallets
                .values()
                .find(|w| w.owners.iter().any(|o| o.to_lowercase() == lower))
                .cloned()
        })
    }

    /// Register a wallet manually
    pub fn register_wallet(&self, wallet: StoredWallet) {
        if let Ok(mut store) = self.wallets.write() {
            store.wallets.insert(wallet.address.clone(), wallet);
        }
        self.save_store();
    }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

fn wei_to_eth(wei: U256) -> String {
    let whole = wei / U256::exp10(18);
    let frac = wei % U256::exp10(18);
    format!("{}.{:0>18}", whole, frac)
}

fn parse_data(data: &str) -> Result<Bytes, Box<dyn std::error::Error + Send + Sync>> {
    if data.is_empty() || data == "0x" {
        Ok(Bytes::new())
    } else {
        Ok(Bytes::from(hex::decode(data.trim_start_matches("0x"))?))
    }
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wallet_store_roundtrip() {
        let dir = std::env::temp_dir().join("multisig_test_rt");
        let _ = fs::create_dir_all(&dir);

        let mgr = MultiSigManager::new(dir.to_str().unwrap());
        mgr.register_wallet(StoredWallet {
            address: "0x1234567890abcdef1234567890abcdef12345678".into(),
            owners: vec![
                "0xaaa0000000000000000000000000000000000001".into(),
                "0xbbb0000000000000000000000000000000000002".into(),
            ],
            required: 2,
            network: "sepolia".into(),
            rpc_url: "https://sepolia.infura.io/v3/key".into(),
            created_at: 1700000000,
        });

        assert_eq!(mgr.get_stored_wallets().len(), 1);

        // Reload from disk
        let mgr2 = MultiSigManager::new(dir.to_str().unwrap());
        assert_eq!(mgr2.get_stored_wallets().len(), 1);
        assert_eq!(mgr2.get_stored_wallets()[0].required, 2);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_owner_lookup() {
        let dir = std::env::temp_dir().join("multisig_test_ol");
        let _ = fs::create_dir_all(&dir);
        let mgr = MultiSigManager::new(dir.to_str().unwrap());

        mgr.register_wallet(StoredWallet {
            address: "0xABCD".into(),
            owners: vec!["0xOwnerA".into(), "0xOwnerB".into()],
            required: 2,
            network: "sepolia".into(),
            rpc_url: "rpc".into(),
            created_at: 0,
        });

        assert!(mgr.get_wallet_for_owner("0xownera").is_some());
        assert!(mgr.get_wallet_for_owner("0xOwnerB").is_some());
        assert!(mgr.get_wallet_for_owner("0xNobody").is_none());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_wei_to_eth() {
        let one_eth = U256::exp10(18);
        assert_eq!(wei_to_eth(one_eth), "1.000000000000000000");

        let half = U256::exp10(17) * 5;
        assert_eq!(wei_to_eth(half), "0.500000000000000000");
    }
}

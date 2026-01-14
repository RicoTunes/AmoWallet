use ethers::{
    contract::abigen,
    core::types::{Address, U256, Bytes},
    providers::{Provider, Http, Middleware},
    signers::{LocalWallet, Signer},
    middleware::SignerMiddleware,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

// Generate Rust bindings from ABI
abigen!(
    MultiSigWallet,
    r#"[
        function submitTransaction(address to, uint256 value, bytes memory data) public
        function confirmTransaction(uint256 txIndex) public
        function executeTransaction(uint256 txIndex) public
        function revokeConfirmation(uint256 txIndex) public
        function getOwners() public view returns (address[] memory)
        function getTransactionCount() public view returns (uint256)
        function getTransaction(uint256 txIndex) public view returns (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations)
        function getBalance() public view returns (uint256)
        event SubmitTransaction(address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data)
        event ConfirmTransaction(address indexed owner, uint256 indexed txIndex)
        event ExecuteTransaction(address indexed owner, uint256 indexed txIndex)
    ]"#,
);

#[derive(Debug, Serialize, Deserialize)]
pub struct MultiSigConfig {
    pub contract_address: String,
    pub owners: Vec<String>,
    pub required_confirmations: u64,
    pub network: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PendingTransaction {
    pub tx_index: u64,
    pub to: String,
    pub value: String,
    pub data: String,
    pub executed: bool,
    pub num_confirmations: u64,
    pub confirmations: Vec<String>,
}

pub struct MultiSigManager {
    provider: Arc<Provider<Http>>,
    wallet: LocalWallet,
}

impl MultiSigManager {
    /// Create new MultiSig manager
    pub fn new(rpc_url: &str, private_key: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let wallet: LocalWallet = private_key.parse()?;
        
        Ok(Self {
            provider: Arc::new(provider),
            wallet,
        })
    }

    /// Deploy new multi-sig wallet
    pub async fn deploy_multisig(
        &self,
        owners: Vec<Address>,
        required_confirmations: U256,
    ) -> Result<Address, Box<dyn std::error::Error>> {
        let client = Arc::new(SignerMiddleware::new(
            self.provider.clone(),
            self.wallet.clone().with_chain_id(self.provider.get_chainid().await?.as_u64()),
        ));

        // Deploy contract (bytecode would come from compiled Solidity)
        // This is a placeholder - actual deployment requires compiled bytecode
        
        // For now, return error indicating manual deployment needed
        Err("Contract deployment requires compiled bytecode. Deploy via Hardhat/Foundry".into())
    }

    /// Submit transaction to multi-sig wallet
    pub async fn submit_transaction(
        &self,
        contract_address: Address,
        to: Address,
        value: U256,
        data: Bytes,
    ) -> Result<u64, Box<dyn std::error::Error>> {
        let client = Arc::new(SignerMiddleware::new(
            self.provider.clone(),
            self.wallet.clone().with_chain_id(self.provider.get_chainid().await?.as_u64()),
        ));

        let contract = MultiSigWallet::new(contract_address, client);
        
        let tx = contract
            .submit_transaction(to, value, data)
            .send()
            .await?
            .await?;

        // Extract transaction index from event
        let tx_index = self.get_transaction_count(contract_address).await? - 1;

        Ok(tx_index)
    }

    /// Confirm pending transaction
    pub async fn confirm_transaction(
        &self,
        contract_address: Address,
        tx_index: u64,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let client = Arc::new(SignerMiddleware::new(
            self.provider.clone(),
            self.wallet.clone().with_chain_id(self.provider.get_chainid().await?.as_u64()),
        ));

        let contract = MultiSigWallet::new(contract_address, client);
        
        let tx = contract
            .confirm_transaction(U256::from(tx_index))
            .send()
            .await?
            .await?;

        match tx {
            Some(receipt) => Ok(format!("{:?}", receipt.transaction_hash)),
            None => Err("Transaction receipt not available".into())
        }
    }

    /// Execute confirmed transaction
    pub async fn execute_transaction(
        &self,
        contract_address: Address,
        tx_index: u64,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let client = Arc::new(SignerMiddleware::new(
            self.provider.clone(),
            self.wallet.clone().with_chain_id(self.provider.get_chainid().await?.as_u64()),
        ));

        let contract = MultiSigWallet::new(contract_address, client);
        
        let tx = contract
            .execute_transaction(U256::from(tx_index))
            .send()
            .await?
            .await?;

        match tx {
            Some(receipt) => Ok(format!("{:?}", receipt.transaction_hash)),
            None => Err("Transaction receipt not available".into())
        }
    }

    /// Revoke confirmation
    pub async fn revoke_confirmation(
        &self,
        contract_address: Address,
        tx_index: u64,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let client = Arc::new(SignerMiddleware::new(
            self.provider.clone(),
            self.wallet.clone().with_chain_id(self.provider.get_chainid().await?.as_u64()),
        ));

        let contract = MultiSigWallet::new(contract_address, client);
        
        let tx = contract
            .revoke_confirmation(U256::from(tx_index))
            .send()
            .await?
            .await?;

        match tx {
            Some(receipt) => Ok(format!("{:?}", receipt.transaction_hash)),
            None => Err("Transaction receipt not available".into())
        }
    }

    /// Get transaction details
    pub async fn get_transaction(
        &self,
        contract_address: Address,
        tx_index: u64,
    ) -> Result<PendingTransaction, Box<dyn std::error::Error>> {
        let contract = MultiSigWallet::new(contract_address, self.provider.clone());
        
        let (to, value, data, executed, num_confirmations) = contract
            .get_transaction(U256::from(tx_index))
            .call()
            .await?;

        Ok(PendingTransaction {
            tx_index,
            to: format!("{:?}", to),
            value: value.to_string(),
            data: hex::encode(&data),
            executed,
            num_confirmations: num_confirmations.as_u64(),
            confirmations: vec![], // Would need to query events for this
        })
    }

    /// Get transaction count
    pub async fn get_transaction_count(
        &self,
        contract_address: Address,
    ) -> Result<u64, Box<dyn std::error::Error>> {
        let contract = MultiSigWallet::new(contract_address, self.provider.clone());
        let count = contract.get_transaction_count().call().await?;
        Ok(count.as_u64())
    }

    /// Get wallet owners
    pub async fn get_owners(
        &self,
        contract_address: Address,
    ) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let contract = MultiSigWallet::new(contract_address, self.provider.clone());
        let owners = contract.get_owners().call().await?;
        
        Ok(owners.iter().map(|addr| format!("{:?}", addr)).collect())
    }

    /// Get wallet balance
    pub async fn get_balance(
        &self,
        contract_address: Address,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let contract = MultiSigWallet::new(contract_address, self.provider.clone());
        let balance = contract.get_balance().call().await?;
        
        Ok(balance.to_string())
    }

    /// Check if transaction needs more confirmations
    pub async fn needs_more_confirmations(
        &self,
        contract_address: Address,
        tx_index: u64,
        required: u64,
    ) -> Result<bool, Box<dyn std::error::Error>> {
        let tx = self.get_transaction(contract_address, tx_index).await?;
        Ok(tx.num_confirmations < required)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_multisig_creation() {
        // Test multi-sig wallet creation
        // This would require a test network
    }

    #[tokio::test]
    async fn test_transaction_submission() {
        // Test transaction submission flow
    }

    #[tokio::test]
    async fn test_confirmation_flow() {
        // Test multi-party confirmation
    }
}

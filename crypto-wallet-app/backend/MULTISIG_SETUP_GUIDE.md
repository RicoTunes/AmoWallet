# Multi-Signature Wallet Setup Guide

## Overview

The multi-signature wallet requires M-of-N signatures to execute transactions, providing enhanced security for large transactions and institutional use.

## Features

- **M-of-N Signatures**: Configure 2-of-3, 3-of-5, or custom signature requirements
- **Owner Management**: Add/remove owners, change signature requirements
- **Transaction Lifecycle**: Submit → Confirm → Execute
- **Revoke Confirmations**: Co-signers can revoke confirmations before execution
- **Event Logging**: Full audit trail of all operations
- **Gas Optimized**: Efficient storage patterns for minimal transaction costs

## Quick Start

### 1. Install Dependencies

```bash
cd backend/contracts
npm install
```

### 2. Configure Environment

Create `.env` file in `backend/contracts/`:

```env
# Deployment wallet (has funds for deployment)
PRIVATE_KEY=your_private_key_here

# Multi-sig owners (comma-separated addresses)
MULTISIG_OWNERS=0x123...,0x456...,0x789...

# Required confirmations (2 for 2-of-3, 3 for 3-of-5, etc.)
REQUIRED_CONFIRMATIONS=2

# Sepolia testnet RPC
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY

# Etherscan API key (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### 3. Compile Contract

```bash
npm run compile
```

Output: `artifacts/MultiSigWallet.sol/MultiSigWallet.json`

### 4. Deploy to Testnet (Sepolia)

```bash
npm run deploy:sepolia
```

**Example Output:**
```
🚀 Deploying Multi-Signature Wallet...

📋 Deployment Configuration:
   Owners: 3
     1. 0x123...
     2. 0x456...
     3. 0x789...
   Required Confirmations: 2

✅ Multi-Signature Wallet deployed!
📍 Contract Address: 0xABC123...
```

**Save the contract address!** You'll need it for all API calls.

### 5. Verify Contract on Etherscan

```bash
npx hardhat verify --network sepolia 0xABC123... "0x123...","0x456...","0x789..." 2
```

## API Usage

### Get Contract Information

```bash
curl http://localhost:3000/api/multisig/info
```

Response:
```json
{
  "success": true,
  "contract": {
    "solidity_version": "0.8.20",
    "features": [
      "M-of-N signature requirements",
      "Owner management",
      "Transaction submission and confirmation"
    ]
  }
}
```

### Submit Transaction

```bash
curl -X POST http://localhost:3000/api/multisig/submit \
  -H "Content-Type: application/json" \
  -d '{
    "contractAddress": "0xABC123...",
    "to": "0xRecipient...",
    "value": "1000000000000000000",
    "data": "0x",
    "rpcUrl": "https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY",
    "privateKey": "owner1_private_key"
  }'
```

Response:
```json
{
  "success": true,
  "txIndex": 0,
  "status": "pending",
  "confirmationsNeeded": 2
}
```

### Confirm Transaction (Owner 2)

```bash
curl -X POST http://localhost:3000/api/multisig/confirm \
  -H "Content-Type: application/json" \
  -d '{
    "contractAddress": "0xABC123...",
    "txIndex": 0,
    "rpcUrl": "https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY",
    "privateKey": "owner2_private_key"
  }'
```

### Execute Transaction (After Required Confirmations)

```bash
curl -X POST http://localhost:3000/api/multisig/execute \
  -H "Content-Type: application/json" \
  -d '{
    "contractAddress": "0xABC123...",
    "txIndex": 0,
    "rpcUrl": "https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY",
    "privateKey": "any_owner_private_key"
  }'
```

### Get Pending Transactions

```bash
curl http://localhost:3000/api/multisig/pending/0xABC123...
```

### Get Wallet Owners

```bash
curl http://localhost:3000/api/multisig/owners/0xABC123...
```

## Flutter Integration (Coming Next)

### Multi-Sig Wallet Creation UI

```dart
// lib/presentation/pages/multisig/create_multisig_page.dart
class CreateMultiSigPage extends StatefulWidget {
  // - Select owners (add addresses)
  // - Set required confirmations (2-of-3, 3-of-5, etc.)
  // - Deploy contract button
  // - Display contract address on success
}
```

### Transaction Proposal UI

```dart
// lib/presentation/pages/multisig/propose_transaction_page.dart
class ProposeTransactionPage extends StatefulWidget {
  // - Enter recipient address
  // - Enter amount
  // - Submit to multi-sig wallet
  // - Show pending status
}
```

### Pending Transactions UI

```dart
// lib/presentation/pages/multisig/pending_transactions_page.dart
class PendingTransactionsPage extends StatefulWidget {
  // - List all pending transactions
  // - Show confirmation count
  // - Confirm button (for co-signers)
  // - Execute button (when threshold met)
  // - Revoke confirmation option
}
```

## Security Best Practices

### Owner Key Management

1. **Distribute Private Keys Securely**
   - Never store all owner keys in one location
   - Use hardware wallets for owner keys
   - Consider geographic distribution

2. **Use Different Devices**
   - Owner 1: Desktop with hardware wallet
   - Owner 2: Mobile with biometric authentication
   - Owner 3: Cold storage backup

3. **Regular Key Rotation**
   - Add new owner
   - Remove old owner
   - Update signature requirements if needed

### Transaction Workflow

1. **Small Transactions** (< $10k)
   - Use 2-of-3 multi-sig
   - Faster execution

2. **Large Transactions** (> $10k)
   - Use 3-of-5 multi-sig
   - More security layers
   - Longer confirmation time

3. **Critical Operations**
   - Owner management changes
   - Require ALL owners to confirm
   - Add time delays

## Testing

### Local Hardhat Network

```bash
# Terminal 1: Start Hardhat node
npx hardhat node

# Terminal 2: Deploy to local network
npm run deploy:localhost
```

### Test Transaction Flow

```javascript
const { ethers } = require("hardhat");

async function testMultiSig() {
  const [owner1, owner2, owner3] = await ethers.getSigners();
  
  // Deploy
  const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");
  const wallet = await MultiSigWallet.deploy(
    [owner1.address, owner2.address, owner3.address],
    2 // 2-of-3
  );
  
  // Fund wallet
  await owner1.sendTransaction({
    to: await wallet.getAddress(),
    value: ethers.parseEther("1.0")
  });
  
  // Submit transaction
  await wallet.connect(owner1).submitTransaction(
    owner2.address,
    ethers.parseEther("0.5"),
    "0x"
  );
  
  // Confirm with owner2
  await wallet.connect(owner2).confirmTransaction(0);
  
  // Execute (threshold met)
  await wallet.connect(owner1).executeTransaction(0);
  
  console.log("✅ Transaction executed successfully!");
}
```

## Troubleshooting

### "At least 2 owners required"
Set `MULTISIG_OWNERS` environment variable with comma-separated addresses.

### "Invalid requiredConfirmations"
Ensure `REQUIRED_CONFIRMATIONS` is between 1 and the number of owners.

### "Insufficient funds for deployment"
Fund your deployment wallet with testnet ETH:
- Sepolia Faucet: https://sepoliafaucet.com/
- Goerli Faucet: https://goerlifaucet.com/

### "Transaction already confirmed"
Each owner can only confirm once. Use different owner accounts.

### "Cannot execute transaction"
Check:
- Has the transaction been confirmed by required number of owners?
- Has it already been executed?
- Is the wallet funded?

## Gas Costs

| Operation | Estimated Gas | Cost (30 gwei) |
|-----------|--------------|----------------|
| Deploy (3 owners) | ~500,000 | $15 |
| Submit Transaction | ~80,000 | $2.40 |
| Confirm Transaction | ~50,000 | $1.50 |
| Execute Transaction | ~70,000 | $2.10 |
| Add Owner | ~60,000 | $1.80 |
| Remove Owner | ~40,000 | $1.20 |

## Production Deployment

### 1. Audit Contract
- Use Slither, Mythril for static analysis
- Consider professional audit (CertiK, OpenZeppelin)

### 2. Test Extensively
- Deploy to testnets (Sepolia, Goerli)
- Test all operations multiple times
- Simulate edge cases

### 3. Deploy to Mainnet
```bash
# Update .env with mainnet RPC
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR-API-KEY

# Deploy
npx hardhat run scripts/deploy.js --network mainnet
```

### 4. Verify on Etherscan
```bash
npx hardhat verify --network mainnet <ADDRESS> "<OWNERS>" <CONFIRMATIONS>
```

### 5. Fund Wallet
Send ETH to the deployed contract address.

## Support

- Contract Issues: Check `backend/contracts/MultiSigWallet.sol`
- API Issues: Check `backend/src/routes/multisigRoutes.js`
- Rust Integration: Check `backend/rust/src/multisig.rs`

## Resources

- Hardhat Documentation: https://hardhat.org/docs
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts
- Etherscan API: https://docs.etherscan.io/
- Alchemy RPC: https://docs.alchemy.com/

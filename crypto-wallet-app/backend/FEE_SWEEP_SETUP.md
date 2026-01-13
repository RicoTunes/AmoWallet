# Fee Sweep & Telegram Alerts - Complete Setup Guide

## 🎯 Overview

This document guides you through setting up automatic fee sweeping with Telegram real-time alerts for your crypto wallet application.

**What You Get:**
- ✅ Automatic fee collection from all transactions (BTC, ETH, BSC, POLYGON)
- ✅ Daily aggregation of fees across all chains
- ✅ Automatic conversion of all fees to USDT-BEP20
- ✅ Scheduled transfer to your admin wallet on BSC
- ✅ Real-time Telegram notifications of all operations
- ✅ Admin dashboard endpoints for manual control

---

## 📋 Quick Start (5 minutes)

### Step 1: Create a Telegram Bot

1. **Open Telegram** and search for `@BotFather`
2. **Create new bot**:
   - Send: `/newbot`
   - Choose a name: e.g., "Crypto Wallet Admin Bot"
   - Choose a username: e.g., `crypto_wallet_admin_bot`
   - **Copy your Bot Token** (you'll need this)

   Example: `123456789:ABCDEFGHIJKLMNOPQRSTUVWxyz-1234567890`

3. **Get your Chat ID**:
   - Forward any message to `@userinfobot`
   - Look for "Your user ID: **123456789**"
   - This is your Chat ID

### Step 2: Update `.env` File

```bash
# backend/.env

# Telegram Configuration
TELEGRAM_BOT_TOKEN=123456789:ABCDEFGHIJKLMNOPQRSTUVWxyz-1234567890
TELEGRAM_ADMIN_CHAT_ID=123456789

# Admin Wallet Private Key (for USDT transfers)
ADMIN_WALLET_PRIVATE_KEY=your_admin_wallet_private_key_here

# Fee Sweep Configuration
FEE_SWEEP_ENABLED=true
FEE_SWEEP_INTERVAL_HOURS=24
AUTO_CONVERT_TO_USDT=true
MIN_FEE_USDT_THRESHOLD=0.50
```

### Step 3: Restart Backend

```bash
cd backend
node server.js
```

**Expected Output:**
```
✅ Telegram service initialized
🔄 Starting Fee Sweep Service...
✅ Fee sweep service running (24h interval)
🚀 Starting notification sent to Telegram
```

✨ **Done!** Your app is now collecting fees and sending alerts to Telegram.

---

## 📊 Fee Collection Flow

```
Transaction Sent (BTC/ETH/BSC)
    ↓
[Fee Calculated] (0.5% transaction fee)
    ↓
[Fee Logged to MongoDB]
    ↓
[Telegram Alert Sent] 💰 "Fee collected: 0.00456 BTC"
    ↓
[24-Hour Accumulation]
    ↓
[Automatic Daily Sweep at Midnight]
    ↓
[All Fees → USDT Conversion]
    ↓
[Transfer to Admin Wallet] (0x726dac...)
    ↓
[Telegram Summary Report] 📈 "Sweep complete: $1,234.56 transferred"
```

---

## 🔔 Telegram Alerts

### Alert Types You'll Receive

1. **💰 Fee Collection Alert** (on each transaction)
   ```
   Network: Bitcoin
   Amount: 1.5 BTC
   Fee: 0.00456 BTC
   Transaction: 3a8f7d...
   ```

2. **🎯 Fee Sweep Summary** (daily at midnight)
   ```
   Fees Collected: 347
   Total Value: $8,234.56 USDT
   Duration: 12.34s
   Status: ✅ COMPLETED
   ```

3. **❌ Error Alerts** (if something fails)
   ```
   Fee Sweep Error
   Connection timeout to BSC RPC
   ```

4. **🚀 Startup Notification** (when server starts)
   ```
   Crypto Wallet App Started
   Features: Fee Collection, Sweep Service, Telegram Alerts
   Status: ✅ ONLINE
   ```

---

## 🔧 Admin API Endpoints

### Manual Trigger Fee Sweep

```bash
# Manually trigger fee sweep (for testing or urgent sweeps)
curl -X POST http://localhost:3000/api/admin/fees/sweep \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"
```

**Response:**
```json
{
  "success": true,
  "message": "Fee sweep initiated",
  "status": "processing"
}
```

### Get Pending Fees

```bash
# See how many fees are ready to sweep
curl http://localhost:3000/api/admin/fees/pending \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"
```

**Response:**
```json
{
  "success": true,
  "count": 347,
  "totalValue": "2.34567890",
  "byNetwork": {
    "BTC": 1.5,
    "ETH": 0.25,
    "BSC": 0.58
  }
}
```

### Get Fee Statistics

```bash
# Get 7-day fee statistics
curl http://localhost:3000/api/admin/fees/stats \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"
```

**Response:**
```json
{
  "success": true,
  "data": {
    "period": "7 days",
    "lastSweep": "2024-12-09T00:00:00.000Z",
    "stats": [
      {
        "_id": "BTC",
        "totalFees": 5.23,
        "feeCount": 145,
        "avgFee": 0.036
      },
      {
        "_id": "ETH",
        "totalFees": 0.85,
        "feeCount": 89,
        "avgFee": 0.0095
      }
    ]
  }
}
```

### Test Telegram Connection

```bash
# Verify Telegram is working
curl -X POST http://localhost:3000/api/admin/telegram/test \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"
```

### Send Custom Alert

```bash
# Send custom alert to your Telegram
curl -X POST http://localhost:3000/api/admin/telegram/alert \
  -H "x-admin-key: YOUR_ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Manual Alert",
    "message": "Maintenance starting in 5 minutes",
    "severity": "warning"
  }'
```

---

## 💼 Fee Collection Configuration

### Transaction Fee Calculation

**Default Settings:**
```
Transaction Fee Percentage: 0.5%
Minimum Fee (USD): $0.50
Swap Fee Percentage: 1.0%
```

**Example:**
- User sends 1 BTC ($42,000)
- Fee = 1 BTC × 0.5% = 0.005 BTC ≈ $210

- User sends $100 USDT
- Fee = $100 × 0.5% = $0.50 (minimum met)

- User swaps 1 ETH to USDT
- Swap Fee = $2,200 × 1.0% = $22

### Customize Fee Percentages

Edit `backend/.env`:
```
TRANSACTION_FEE_PERCENTAGE=0.5      # Change this
MIN_TRANSACTION_FEE_USD=0.50        # Or this
SWAP_FEE_PERCENTAGE=1.0             # Or this
```

Then restart: `node server.js`

---

## 🔐 Security Considerations

### Private Key Management

**⚠️ CRITICAL:** Never commit your admin wallet private key to Git!

**Recommended Setup:**
1. Use environment variable (local development only)
2. Use AWS Secrets Manager (production)
3. Use HashiCorp Vault (enterprise)
4. Use managed wallet service (e.g., Coinbase Cloud)

**Example (AWS Secrets Manager):**
```javascript
const AWS = require('aws-sdk');
const client = new AWS.SecretsManager();

const getAdminPrivateKey = async () => {
  const secret = await client.getSecretValue({ 
    SecretId: 'crypto-wallet/admin-key' 
  }).promise();
  return secret.SecretString;
};
```

### Admin API Key Protection

Set a strong admin key:
```bash
# backend/.env
ADMIN_API_KEY=super_secret_key_change_this_in_production
```

In production, use:
- API Key + signature verification
- OAuth 2.0
- JWT with expiration
- IP whitelisting

---

## 🚀 Production Deployment Checklist

- [ ] Telegram bot created and configured
- [ ] Admin wallet private key secured (not in .env)
- [ ] All fees collected and tracked in MongoDB
- [ ] Fee sweep tested manually with `/api/admin/fees/sweep`
- [ ] Telegram alerts verified (receive test message)
- [ ] Admin API endpoints protected with strong key
- [ ] All 4 treasury addresses configured for each chain:
  - [ ] TREASURY_BTC_ADDRESS
  - [ ] TREASURY_ETH_ADDRESS
  - [ ] TREASURY_BSC_ADDRESS
  - [ ] TREASURY_POLYGON_ADDRESS
  - [ ] TREASURY_USDT_ADDRESS
- [ ] FEE_SWEEP_ENABLED=true in production
- [ ] BSC RPC URL verified (for USDT transfers)
- [ ] Database backups enabled

---

## 🐛 Troubleshooting

### Problem: Telegram alerts not sending

**Solution 1:** Verify bot token
```bash
curl -X GET https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getMe
```

**Solution 2:** Verify chat ID
```bash
# Start bot and send a message, check logs
curl -X GET https://api.telegram.org/bot{YOUR_BOT_TOKEN}/getUpdates
```

### Problem: Fee sweep not running

**Check logs:**
```bash
# Look for "Fee Sweep Service started"
grep "Fee Sweep" backend.log

# Check for errors
grep "❌" backend.log
```

**Restart service:**
```bash
node server.js
```

### Problem: USDT transfer failing

**Common causes:**
1. Admin wallet doesn't have BSC private key set
2. Not enough BNB for gas fees on BSC
3. USDT-BEP20 contract address incorrect
4. RPC endpoint rate limited

**Solution:**
1. Fund admin wallet with 0.1 BNB on BSC
2. Verify USDT_BEP20_ADDRESS: `0x55d398326f99059fF775485246999027B3197955`
3. Use different BSC RPC endpoint

---

## 📈 Monitoring & Analytics

### Daily Report Example

```
Date: 2024-12-09
Transactions: 1,245
Total Volume: $456,789.00
Fees Collected: $2,283.95
Top Asset: Ethereum
Status: ✅ ALL SYSTEMS OPERATIONAL
```

### Fee Summary (7 Days)

| Network  | Fees Collected | Count | Avg Fee |
|----------|---|-------|---------|
| Bitcoin  | 5.23 BTC | 145 | 0.036 BTC |
| Ethereum | 0.85 ETH | 89 | 0.0095 ETH |
| BSC      | 12.4 BNB | 234 | 0.053 BNB |
| Polygon  | 450 MATIC | 567 | 0.79 MATIC |

---

## 🆘 Support

### Key Files
- Fee Sweep Service: `backend/src/services/feeSweepService.js`
- Telegram Service: `backend/src/services/telegramService.js`
- Admin Endpoints: `backend/src/routes/adminRoutes.js`
- Configuration: `backend/.env`

### Server Logs
```bash
# Check real-time logs
tail -f backend.log

# Filter for fee sweep logs
grep "💰\|🎯\|❌" backend.log
```

---

## 🎉 You're All Set!

Your crypto wallet app now has:
- ✅ Automatic fee collection on every transaction
- ✅ Real-time Telegram alerts
- ✅ Daily fee sweep to USDT on BSC
- ✅ Admin dashboard for monitoring
- ✅ Production-ready security

**Next Steps:**
1. Test with a small transaction
2. Verify Telegram alert arrives
3. Check `/api/admin/fees/pending` after a few transactions
4. Monitor daily sweep reports

**Questions?** Check logs: `backend.log`

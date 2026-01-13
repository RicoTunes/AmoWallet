# Get API Keys - Step by Step Guide

## 🔴 CRITICAL (Do These First - 10 minutes)

### 1. Etherscan API Key
**Purpose:** Ethereum transaction history, balances, gas prices

1. Go to: https://etherscan.io/apis
2. Click "Sign Up" (top right)
3. Fill in:
   - Username
   - Email
   - Password
4. Verify your email (check inbox/spam)
5. Login → Click your username → "API Keys"
6. Click "+ Add" button
7. Enter app name: "CryptoWalletPro"
8. Copy the API key

**Update .env:**
```properties
ETHERSCAN_API_KEY=ABC123...
```

---

### 2. BSCScan API Key
**Purpose:** BSC transaction history and balances

1. Go to: https://bscscan.com/apis
2. Same process as Etherscan:
   - Sign up
   - Verify email
   - Go to API Keys section
   - Create new key
   - Copy it

**Update .env:**
```properties
BSCSCAN_API_KEY=XYZ789...
```

---

## 🟡 RECOMMENDED (15 minutes - Better Performance)

### 3. CoinGecko API Key (Optional but Recommended)
**Purpose:** Real-time crypto prices - your app already works without this on free tier!

**Current Status:** Working on free tier (10-50 calls/min)  
**With Key:** 10,000 calls/month free tier

1. Go to: https://www.coingecko.com/en/api
2. Click "Get Your Free API Key"
3. Sign up for account
4. Choose "Demo" plan (FREE)
5. Verify email
6. Dashboard → Copy API key

**Update .env:**
```properties
COINGECKO_API_KEY=CG-abc123...
```

**Note:** If you skip this, your app still works! Just has lower rate limits.

---

### 4. CoinMarketCap API Key
**Purpose:** Backup price feed (fallback when CoinGecko has issues)

**Free Tier:** 333 calls/day (10,000/month)

1. Go to: https://coinmarketcap.com/api/
2. Click "Get Your Free API Key Now"
3. Sign up
4. Choose "Basic" plan (FREE)
5. Verify email
6. Dashboard → Copy API Key

**Update .env:**
```properties
COINMARKETCAP_API_KEY=abc-123-def...
```

---

## 🟢 OPTIONAL (Only if You Use These Networks)

### 5. Polygonscan (Polygon Network)
- URL: https://polygonscan.com/apis
- Process: Same as Etherscan
- Free: Yes

### 6. Arbiscan (Arbitrum Network)
- URL: https://arbiscan.io/apis
- Process: Same as Etherscan
- Free: Yes

### 7. Snowtrace (Avalanche Network)
- URL: https://snowtrace.io/apis
- Process: Same as Etherscan
- Free: Yes

### 8. Optimistic Etherscan (Optimism Network)
- URL: https://optimistic.etherscan.io/apis
- Process: Same as Etherscan
- Free: Yes

### 9. OneInch (DEX Aggregation)
- URL: https://portal.1inch.dev/
- Purpose: Better swap rates across DEXes
- Free: Yes

### 10. Moralis (Web3 APIs)
- URL: https://moralis.io/
- Purpose: NFTs, advanced indexing
- Free: Yes

### 11. Chainlink (Oracle Data)
- URL: https://chain.link/
- Purpose: Price feeds, oracle data
- Free: Yes (for basic use)

---

## 📝 After Getting Keys

### Update Your .env File
Open: `c:\Users\RICO\ricoamos\crypto-wallet-app\backend\.env`

Replace each placeholder:
```properties
# Before
ETHERSCAN_API_KEY=YourEtherscanAPIKey

# After
ETHERSCAN_API_KEY=ABC123XYZ789...
```

### Test Everything
```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
node test-env.js
```

You should see:
- ✓ for working keys
- ✗ for failed/missing keys
- ⚠ for optional keys

---

## 🚀 Quick Start (Minimum Working Setup)

**If you're in a hurry, just get these 2:**

1. **Etherscan** (5 min) - For Ethereum functionality
2. **BSCScan** (5 min) - For BSC functionality

Your app will work with just these! Everything else is optional enhancements.

---

## ⏱️ Time Estimates

- **Minimum (Etherscan + BSC):** 10 minutes
- **Recommended (+ CoinGecko + CMC):** 25 minutes  
- **Full Setup (all 11 keys):** 60 minutes

---

## 🔒 Security Notes

1. **Never commit .env to Git** - Already in .gitignore ✓
2. **Keep keys private** - Don't share or screenshot
3. **Use environment variables in production** - Not .env files
4. **Rotate keys if compromised** - Free to regenerate

---

## 💡 Pro Tips

- **All services offer free tiers** - You don't need to pay
- **Instant approval** - Most keys work immediately
- **No credit card** - Free tiers don't require payment info
- **Rate limits** - Free tiers are usually sufficient for development

---

## 🆘 Having Trouble?

Run the interactive setup assistant:
```powershell
node setup-api-keys.js
```

This will:
- Open each website automatically
- Guide you step-by-step
- Update your .env file automatically
- Test each key after setup

---

## ✅ Success Checklist

After setup, you should have:
- [ ] ETHERSCAN_API_KEY (working)
- [ ] BSCSCAN_API_KEY (working)
- [ ] COINGECKO_API_KEY (optional)
- [ ] COINMARKETCAP_API_KEY (optional)
- [ ] Other keys (as needed)

Run `node test-env.js` - aim for 7/7 tests passing!

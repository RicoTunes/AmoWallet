# Environment Variables Checklist

## ✅ Already Configured (Working Values)
- `INFURA_PROJECT_ID` = `9aa3d95b3bc440fa88ea12eaa4456161` ✓
- `BLOCKCYPHER_API_KEY` = `34199103161a43b883f353934d966c53` ✓
- `ETHEREUM_RPC_URL`, `BSC_RPC_URL`, `POLYGON_RPC_URL`, etc. ✓
- `DATABASE_URL`, `REDIS_URL` ✓
- `JWT_SECRET`, `SESSION_SECRET` ✓
- DEX Router addresses ✓

## ⚠️ Need Real API Keys (Currently Placeholders)

### High Priority (Required for Core Features)
1. **ETHERSCAN_API_KEY** = `YourEtherscanAPIKey` ❌
   - Purpose: Transaction history, balance fallback, gas price data
   - Get it: https://etherscan.io/apis (free tier available)
   - Impact: Ethereum transaction lookups and history won't work

2. **BSCSCAN_API_KEY** = `YourBSCScanAPIKey` ❌
   - Purpose: BSC transaction history and balance queries
   - Get it: https://bscscan.com/apis
   - Impact: BSC transaction lookups won't work

3. **COINGECKO_API_KEY** = `YourCoinGeckoAPIKey` ❌
   - Purpose: **Real-time cryptocurrency price feeds for swap quotes**
   - Get it: https://www.coingecko.com/en/api (free tier: 10-50 calls/min, paid: higher limits)
   - Impact: Without key = free tier rate limits (may fail during high usage)
   - **Why you need it:** Your swap routes use CoinGecko as the PRIMARY price source

### Medium Priority (Recommended)
4. **POLYGONSCAN_API_KEY** = `YourPolygonscanAPIKey` ⚠️
   - Purpose: Polygon transaction history
   - Get it: https://polygonscan.com/apis

5. **COINMARKETCAP_API_KEY** = `YourCoinMarketCapAPIKey` ⚠️
   - Purpose: **Fallback price feed** when CoinGecko fails
   - Get it: https://coinmarketcap.com/api/ (free tier: 333 calls/day)
   - Impact: No fallback if CoinGecko rate-limits or goes down

### Low Priority (Optional Features)
6. **ARBISCAN_API_KEY** = `YourArbiscanAPIKey` (optional)
7. **SNOWTRACE_API_KEY** = `YourAvalancheAPIKey` (optional)
8. **OPTIMISTIC_ETHERSCAN_API_KEY** = `YourOptimismAPIKey` (optional)
9. **ONEINCH_API_KEY** = `YourOneInchAPIKey` (optional - for DEX aggregation)
10. **MORALIS_API_KEY** = `YourMoralisAPIKey` (optional - for advanced features)
11. **CHAINLINK_API_KEY** = `YourChainlinkAPIKey` (optional - for oracle data)

## 📋 Quick Action Plan

### Step 1: Get Critical Keys (30 minutes)
1. Sign up at https://etherscan.io/apis → Get `ETHERSCAN_API_KEY`
2. Sign up at https://bscscan.com/apis → Get `BSCSCAN_API_KEY`
3. Sign up at https://www.coingecko.com/en/api → Get `COINGECKO_API_KEY` (optional but recommended)

### Step 2: Update `.env` File
Open `c:\Users\RICO\ricoamos\crypto-wallet-app\backend\.env` and replace:
```properties
ETHERSCAN_API_KEY=YourEtherscanAPIKey          # Replace with real key
BSCSCAN_API_KEY=YourBSCScanAPIKey              # Replace with real key
COINGECKO_API_KEY=YourCoinGeckoAPIKey          # Replace with real key (optional)
COINMARKETCAP_API_KEY=YourCoinMarketCapAPIKey  # Replace with real key (optional)
```

### Step 3: Test Configuration
Run the test script:
```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
node test-env.js
```

This will:
- ✓ Check which keys are still placeholders
- ✓ Test each API endpoint
- ✓ Verify database connectivity
- ✓ Show detailed results with pass/fail status

## 🔑 CoinGecko API - What It Does & Why You Need It

### What It Does
Your swap routes (`swapRoutes.js`) call `getRealTimePrices()` which:
1. **Fetches live cryptocurrency prices** from CoinGecko API
2. Converts symbols (BTC, ETH, etc.) to CoinGecko IDs (bitcoin, ethereum, etc.)
3. Gets USD prices + 24hr price change for: BTC, ETH, BNB, USDT, USDC, DAI, LTC, DOGE, XRP, SOL
4. Returns price data used for:
   - **Swap quotes** - calculating exchange rates
   - **Token prices** - showing user how much they'll receive
   - **Market data** - displaying 24hr price changes

### Example API Call
```
GET https://api.coingecko.com/api/v3/simple/price
  ?ids=bitcoin,ethereum,binancecoin
  &vs_currencies=usd
  &include_24hr_change=true
  &x_cg_pro_api_key=YOUR_KEY_HERE   ← optional but recommended
```

Response:
```json
{
  "bitcoin": { "usd": 37245.12, "usd_24h_change": 2.34 },
  "ethereum": { "usd": 2043.56, "usd_24h_change": -0.87 }
}
```

### Free Tier vs Pro API Key

**Without API Key (Free Tier):**
- ✓ Works immediately
- ✓ No signup required
- ✗ Rate limited: 10-50 calls/minute
- ✗ May get blocked during high traffic
- ✗ No commercial use guarantee

**With Pro API Key:**
- ✓ Higher rate limits (500-10,000+ calls/min depending on plan)
- ✓ Better reliability
- ✓ Priority support
- ✓ Commercial use allowed
- Free tier: Up to 10,000 calls/month

### Fallback Chain
Your code has a 3-tier fallback:
1. **CoinGecko** (primary) → If fails...
2. **CoinMarketCap** (secondary, requires key) → If fails...
3. **Mock prices** (hardcoded fallback for dev)

### When You MUST Have It
- Production deployment
- Expected high user volume (>10 concurrent users)
- Commercial use
- Need reliable swap quotes

### When Free Tier Is OK
- Development/testing
- Low traffic (<10 requests/minute)
- Personal use

## 🧪 Verification Commands

### Test Infura (Ethereum RPC)
```powershell
$body = @{
  jsonrpc = "2.0"
  method = "eth_blockNumber"
  params = @()
  id = 1
} | ConvertTo-Json

Invoke-RestMethod -Method Post -Uri "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161" -Body $body -ContentType "application/json"
```

### Test CoinGecko
```powershell
# Without API key (free tier)
Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd"

# With API key (replace YOUR_KEY)
Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&x_cg_pro_api_key=YOUR_KEY"
```

### Test Etherscan (replace YOUR_KEY)
```powershell
Invoke-RestMethod -Uri "https://api.etherscan.io/api?module=stats&action=ethprice&apikey=YOUR_KEY"
```

### Test BlockCypher
```powershell
Invoke-RestMethod -Uri "https://api.blockcypher.com/v1/btc/main?token=34199103161a43b883f353934d966c53"
```

## 📊 Summary

**Minimum to Run:**
- INFURA_PROJECT_ID ✓ (already set)
- ETHERSCAN_API_KEY ❌ (need real key)
- DATABASE_URL ✓ (already set)

**Recommended for Production:**
- All of the above +
- BSCSCAN_API_KEY ❌
- COINGECKO_API_KEY ❌
- COINMARKETCAP_API_KEY ❌
- POLYGONSCAN_API_KEY ❌

**Total Time to Configure:** ~30 minutes to sign up and get free tier keys
**Total Cost:** $0 (all have free tiers)

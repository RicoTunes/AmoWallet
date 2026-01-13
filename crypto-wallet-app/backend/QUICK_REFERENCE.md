# Quick Reference: API Keys Priority List

## 🔴 CRITICAL (Must Have)
```properties
INFURA_PROJECT_ID=9aa3d95b3bc440fa88ea12eaa4456161  # ⚠️ Returns 401 - needs refresh
ETHERSCAN_API_KEY=YourEtherscanAPIKey               # ❌ Placeholder - GET THIS
DATABASE_URL=mongodb://localhost:27017/...          # ✓ Set but MongoDB not running
```

## 🟡 IMPORTANT (Recommended)
```properties
BSCSCAN_API_KEY=YourBSCScanAPIKey                   # ❌ Placeholder - GET THIS
COINGECKO_API_KEY=YourCoinGeckoAPIKey              # ⚠️ Optional but recommended
COINMARKETCAP_API_KEY=YourCoinMarketCapAPIKey      # ⚠️ Fallback for CoinGecko
```

## 🟢 OPTIONAL (Nice to Have)
```properties
POLYGONSCAN_API_KEY=YourPolygonscanAPIKey          # If using Polygon
BLOCKCYPHER_API_KEY=34199103161a43b883f353934d966c53  # ✓ Working
REDIS_URL=redis://localhost:6379                    # For caching
```

---

## CoinGecko Explained in 3 Points

1. **What:** Real-time cryptocurrency price API
2. **Used For:** Swap quotes, exchange rates, token prices (10 coins)
3. **Need Key?** 
   - Dev/Testing: No (free tier working ✓)
   - Production: Yes (reliability + ToS)

---

## Run This to Test Everything
```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
node test-env.js
```

Current Score: **4/7 passing** (57%)

---

## 5-Minute Fix List

1. **Infura** → https://infura.io/ → Create project → Copy ID
2. **Etherscan** → https://etherscan.io/apis → Sign up → Copy key
3. **MongoDB** → Start local: `mongod` OR use Atlas (cloud)
4. **Test** → `node test-env.js`

Goal: **7/7 passing** ✓

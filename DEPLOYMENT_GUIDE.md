# Production Deployment Guide

## 🚀 Getting Started with Real APIs

This guide walks through configuring and deploying the CryptoWallet Pro backend with real blockchain and API integrations.

---

## Step 1: Create Production `.env` File

Copy `.env.example` to `.env` and configure with real values:

```bash
# Copy template
cp backend/.env.example backend/.env

# Edit with your credentials
nano backend/.env
```

### Configuration Template

```env
# ============================================================
# BLOCKCHAIN RPC ENDPOINTS (Required)
# ============================================================

# Ethereum Mainnet - Get from Infura
INFURA_PROJECT_ID=your_infura_project_id_here
ETHEREUM_RPC_URL=https://mainnet.infura.io/v3/

# Binance Smart Chain - Public RPC
BSC_RPC_URL=https://bsc-dataseed1.binance.org/

# Polygon - Infura based
POLYGON_RPC_URL=https://polygon-mainnet.infura.io/v3/

# Arbitrum - Infura based  
ARBITRUM_RPC_URL=https://arbitrum-mainnet.infura.io/v3/

# Optimism - Infura based
OPTIMISM_RPC_URL=https://optimism-mainnet.infura.io/v3/

# Avalanche - Public RPC
AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc

# ============================================================
# BLOCKCHAIN EXPLORER APIs (Recommended)
# ============================================================

# Etherscan - For Ethereum transaction data
ETHERSCAN_API_KEY=your_etherscan_api_key_here

# BSCScan - For Binance Chain explorer
BSCSCAN_API_KEY=your_bscscan_api_key_here

# Polygonscan - For Polygon explorer
POLYGONSCAN_API_KEY=your_polygonscan_api_key_here

# Arbiscan - For Arbitrum explorer
ARBISCAN_API_KEY=your_arbiscan_api_key_here

# Snowtrace - For Avalanche explorer
SNOWTRACE_API_KEY=your_snowtrace_api_key_here

# ============================================================
# PRICE FEED APIs
# ============================================================

# CoinGecko - Free, no auth needed but can add API key
COINGECKO_API_KEY=optional_coingecko_api_key

# CoinMarketCap - Professional API (Required for fallback)
COINMARKETCAP_API_KEY=your_coinmarketcap_api_key_here

# ============================================================
# DEX ROUTER ADDRESSES
# ============================================================

# Uniswap V3 Router (Ethereum & Arbitrum)
UNISWAP_V3_ROUTER=0xE592427A0AEce92De3Edee1F18E0157C05861564

# Uniswap V2 Router (Ethereum)
UNISWAP_V2_ROUTER=0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D

# PancakeSwap V3 Router (BSC)
PANCAKESWAP_V3_ROUTER=0x13f4EA83D0bd40E75C8222255bc855a974568Dd4

# PancakeSwap V2 Router (BSC)
PANCAKESWAP_V2_ROUTER=0x10ED43C718714eb63d5aA57B78B54704E256024E

# ============================================================
# TRANSACTION FEE CONFIGURATION
# ============================================================

# Transaction fee in basis points (50 = 0.50%)
TRANSACTION_FEE_BPS=50

# Swap fee in basis points (30 = 0.30%)
SWAP_FEE_BPS=30

# Minimum transaction fee in USD
MIN_TX_FEE_USD=0.10

# Maximum transaction fee in USD (safety limit)
MAX_TX_FEE_USD=1000

# ============================================================
# SECURITY CONFIGURATION
# ============================================================

# Rate limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=30

# CORS - Frontend URLs that can access this API
CORS_ORIGINS=http://localhost:3000,https://cryptowallet.example.com

# Session configuration
SESSION_SECRET=your_super_secret_session_key_here_min_32_chars

# ============================================================
# DATABASE CONFIGURATION
# ============================================================

# MongoDB connection string
MONGODB_URI=mongodb+srv://user:password@cluster.mongodb.net/cryptowallet

# ============================================================
# SERVICE CONFIGURATION
# ============================================================

# Python crypto service URL
PYTHON_SERVICE_URL=http://localhost:5000

# Rust worker pool size
RUST_WORKER_POOL_SIZE=4

# Node environment
NODE_ENV=production
PORT=3000

# ============================================================
# OPTIONAL: LOGGING & MONITORING
# ============================================================

# Sentry error tracking (optional)
SENTRY_DSN=your_sentry_dsn_here

# DataDog APM (optional)
DD_API_KEY=your_datadog_api_key

# Custom logging service (optional)
LOG_SERVICE_URL=https://logging-service.example.com
LOG_SERVICE_KEY=your_logging_api_key
```

---

## Step 2: Get API Keys

### Priority 1 (Essential)
1. **Infura** → https://infura.io
   - Sign up → Create Ethereum project → Copy Project ID
   - Includes: Ethereum, Polygon, Arbitrum, Optimism

2. **CoinMarketCap** → https://coinmarketcap.com/api
   - Get free tier API key
   - Fallback for CoinGecko price feed

### Priority 2 (Recommended)
3. **Etherscan** → https://etherscan.io/apis
   - Create account → Generate API key
   - For transaction history and gas prices

4. **BSCScan** → https://bscscan.com/apis
   - Create account → Generate API key
   - For BSC transaction queries

5. **Polygonscan** → https://polygonscan.com/apis
   - Create account → Generate API key

6. **Arbiscan** → https://arbiscan.io/apis
   - Create account → Generate API key

7. **Snowtrace** → https://snowtrace.io/apis
   - Create account → Generate API key

### Priority 3 (Optional but Useful)
8. **CoinGecko Pro** → https://www.coingecko.com/api/pricing
   - Optional: Get pro API key for higher rate limits
   - Free tier works fine: 50 calls/minute

9. **TronGrid** → https://trongrid.io
   - For TRON blockchain support
   - Free API key available

10. **BlockCypher** → https://www.blockcypher.com
    - For Bitcoin/Litecoin/Dogecoin support
    - Free tier available

---

## Step 3: Install Dependencies

```bash
cd backend

# Install Node.js dependencies
npm install

# Install Python dependencies
cd python-service
pip install -r requirements.txt
cd ..

# Install Rust dependencies (if using crypto service)
cd rust
cargo build --release
cd ..
```

---

## Step 4: Start Services

### Development Mode

```bash
# Terminal 1: Start Node.js backend
npm run dev

# Terminal 2: Start Python service (optional)
cd python-service
python app.py

# Terminal 3: Start Rust service (optional)
cd rust
./target/release/crypto-wallet-worker
```

### Production Mode

```bash
# Using PM2 process manager
npm install -g pm2

# Start with ecosystem file
pm2 start ecosystem.config.js

# Or direct command
node src/server.js

# View logs
pm2 logs
```

---

## Step 5: Verify Installation

### Test Blockchain Connection

```bash
# Check Ethereum connection
curl -X GET "http://localhost:3000/api/blockchain/balance/ethereum/0x742d35Cc6634C0532925a3b844Bc9e7595f42E58" | jq

# Expected response:
{
  "success": true,
  "network": "ethereum",
  "address": "0x742d35Cc6634C0532925a3b844Bc9e7595f42E58",
  "balance": "1.5234",
  "unit": "ETH"
}
```

### Test Price Feed

```bash
# Get current prices
curl -X GET "http://localhost:3000/api/swap/coins" | jq

# Expected response:
{
  "success": true,
  "coins": [
    {
      "symbol": "BTC",
      "price": 60250.75,
      "change24h": 2.34,
      "network": "bitcoin"
    }
  ],
  "priceSource": "coingecko"
}
```

### Test Swap Quote

```bash
# Get swap quote
curl -X POST "http://localhost:3000/api/swap/quote" \
  -H "Content-Type: application/json" \
  -d '{
    "fromCoin": "ETH",
    "toCoin": "USDT",
    "amount": 1.0,
    "slippage": 1.0
  }' | jq

# Expected response:
{
  "success": true,
  "fromCoin": "ETH",
  "toCoin": "USDT",
  "fromAmount": 1,
  "toAmount": 3450.75,
  "fee": 10.35,
  "feePercentage": "0.3000",
  "exchangeRate": 3461.10,
  "dex": "Uniswap V3",
  "priceSource": "coingecko"
}
```

---

## Step 6: Database Setup (MongoDB)

### Local Development

```bash
# Using Docker
docker run -d -p 27017:27017 --name mongodb mongo

# Connection string for .env
MONGODB_URI=mongodb://localhost:27017/cryptowallet
```

### Production (MongoDB Atlas)

1. Go to https://www.mongodb.com/cloud/atlas
2. Create account → Create cluster
3. Configure security → Create database user
4. Get connection string
5. Add to `.env`:
   ```
   MONGODB_URI=mongodb+srv://user:password@cluster.mongodb.net/cryptowallet
   ```

---

## Step 7: Security Checklist

Before going to production:

- [ ] All API keys are configured in `.env` (not in code)
- [ ] `.env` file is in `.gitignore`
- [ ] HTTPS is enabled on all endpoints
- [ ] CORS is restricted to your frontend domain
- [ ] Rate limiting is enabled
- [ ] Database backups are configured
- [ ] Error logging is enabled (Sentry, etc.)
- [ ] Monitoring/alerts are set up
- [ ] API keys have minimal permissions (not admin)
- [ ] Rate limits are tuned for expected traffic

---

## Step 8: Monitoring & Maintenance

### Daily Checks

```bash
# Check service health
curl http://localhost:3000/health

# Check error logs
pm2 logs backend

# Monitor system resources
pm2 plus  # Requires PM2+ account
```

### Regular Maintenance

- [ ] Rotate API keys every 90 days
- [ ] Review rate limit statistics weekly
- [ ] Check blockchain RPC reliability monthly
- [ ] Monitor database performance
- [ ] Update Node.js dependencies quarterly
- [ ] Review error logs for patterns

---

## Troubleshooting

### Issue: "Cannot connect to Ethereum RPC"

**Solution:**
```bash
# Verify INFURA_PROJECT_ID is correct
echo $INFURA_PROJECT_ID

# Test RPC endpoint directly
curl "https://mainnet.infura.io/v3/${INFURA_PROJECT_ID}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Issue: "Price feed not returning data"

**Solution:**
```bash
# Check CoinGecko API
curl "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd"

# Verify CoinMarketCap key if using fallback
echo $COINMARKETCAP_API_KEY
```

### Issue: "Database connection failed"

**Solution:**
```bash
# Verify MongoDB is running
# For local: mongodb is listening on 27017
# For Atlas: Check connection string and IP whitelist

# Test connection
node -e "require('mongodb').MongoClient.connect('$MONGODB_URI', (err, client) => { console.log(err ? 'Failed: ' + err : 'Connected!'); client.close(); })"
```

### Issue: "Rate limit being triggered too quickly"

**Solution:**
```bash
# Adjust rate limiting in .env
RATE_LIMIT_WINDOW_MS=120000    # 2 minutes instead of 1
RATE_LIMIT_MAX_REQUESTS=60     # Increase from 30
```

---

## Performance Optimization

### Caching Layer (Redis)

```bash
# Install Redis
docker run -d -p 6379:6379 --name redis redis

# Add to .env
REDIS_URL=redis://localhost:6379

# Now prices are cached for 30 seconds
```

### Database Indexes

```bash
# Indexes are automatically created by Mongoose schemas
# Verify they exist:
db.transactions.getIndexes()
db.wallets.getIndexes()
```

### Load Balancing (Production)

```bash
# Use Nginx for load balancing
upstream backend {
  server localhost:3000;
  server localhost:3001;
  server localhost:3002;
}

server {
  listen 443 ssl;
  server_name api.cryptowallet.com;
  
  location / {
    proxy_pass http://backend;
  }
}
```

---

## Monitoring with PM2

```bash
# Install PM2 Plus for advanced monitoring
npm install -g pm2-plus

# Configure ecosystem
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'crypto-wallet-api',
    script: './src/server.js',
    instances: 4,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    },
    error_file: './logs/error.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
EOF

pm2 start ecosystem.config.js
```

---

## Next: Continuous Deployment

### GitHub Actions Setup

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: npm ci
      - name: Run tests
        run: npm test
      - name: Deploy
        run: npm run deploy
        env:
          INFURA_PROJECT_ID: ${{ secrets.INFURA_PROJECT_ID }}
          COINMARKETCAP_API_KEY: ${{ secrets.COINMARKETCAP_API_KEY }}
```

---

## Support & Resources

- **Documentation:** See IMPLEMENTATION_SUMMARY.md
- **API Docs:** Swagger/OpenAPI at `/api/docs`
- **Status:** Health check at `/health`
- **Issues:** Check error logs in `./logs/`

---

## Summary

You now have a production-ready CryptoWallet Pro backend configured with real blockchain APIs, live price feeds, and DEX integrations. Start with testnet, monitor the logs, and gradually migrate to mainnet as you gain confidence in the system.

**Happy crypto building! 🚀**

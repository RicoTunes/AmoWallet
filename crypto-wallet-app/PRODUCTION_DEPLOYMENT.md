# Production Deployment Guide

## 🚀 Cloud Deployment Options

### Option 1: Railway (Recommended - Easy)

1. **Sign up** at [railway.app](https://railway.app)

2. **Deploy Backend:**
   ```bash
   cd crypto-wallet-app/backend
   railway login
   railway init
   railway up
   ```

3. **Set Environment Variables in Railway Dashboard:**
   ```
   NODE_ENV=production
   ENABLE_HTTPS=false  # Railway handles SSL
   ETHERSCAN_API_KEY=your_key
   INFURA_PROJECT_ID=your_key
   QUICKNODE_BTC_URL=your_url
   TREASURY_ETH_ADDRESS=your_address
   TREASURY_BTC_ADDRESS=your_address
   ```

4. **Get your URL:** `https://your-app.railway.app`

---

### Option 2: Render (Free Tier Available)

1. **Sign up** at [render.com](https://render.com)

2. **Create New Web Service:**
   - Connect your GitHub repo
   - Build Command: `npm install`
   - Start Command: `node server.js`

3. **Environment Variables:**
   - Same as Railway above
   - Render provides free SSL

---

### Option 3: Heroku

1. **Install Heroku CLI:**
   ```bash
   npm install -g heroku
   heroku login
   ```

2. **Deploy:**
   ```bash
   cd crypto-wallet-app/backend
   heroku create your-crypto-wallet-api
   git push heroku main
   ```

3. **Set Config:**
   ```bash
   heroku config:set NODE_ENV=production
   heroku config:set ETHERSCAN_API_KEY=your_key
   # ... other vars
   ```

---

### Option 4: VPS (DigitalOcean, Linode, AWS EC2)

1. **Set up Ubuntu server**

2. **Install dependencies:**
   ```bash
   sudo apt update
   sudo apt install -y nodejs npm nginx certbot python3-certbot-nginx
   ```

3. **Clone and setup:**
   ```bash
   git clone your-repo
   cd crypto-wallet-app/backend
   npm install
   cp .env.example .env
   # Edit .env with production values
   ```

4. **Get SSL Certificate (Let's Encrypt):**
   ```bash
   sudo certbot certonly --standalone -d api.yourdomain.com
   ```

5. **Update .env:**
   ```
   NODE_ENV=production
   ENABLE_HTTPS=true
   DOMAIN=api.yourdomain.com
   SSL_CERT_PATH=/etc/letsencrypt/live
   HTTPS_PORT=443
   ```

6. **Run with PM2:**
   ```bash
   npm install -g pm2
   pm2 start server.js --name crypto-wallet-api
   pm2 startup
   pm2 save
   ```

---

## 📱 Flutter App Configuration for Production

### Update `environment.dart`:

```dart
case Environment.production:
  return 'https://api.yourdomain.com';  // Your production URL
```

### Build Release APK:

```bash
cd crypto-wallet-app/frontend
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Build for iOS:

```bash
flutter build ios --release
```

---

## 🔑 Required API Keys for Production

| Service | Get Key At | Purpose |
|---------|------------|---------|
| Etherscan | [etherscan.io/apis](https://etherscan.io/apis) | ETH transactions |
| Infura | [infura.io](https://infura.io) | Ethereum RPC |
| QuickNode | [quicknode.com](https://quicknode.com) | Bitcoin RPC |
| CoinGecko | [coingecko.com/api](https://coingecko.com/api) | Price data |
| CoinMarketCap | [coinmarketcap.com/api](https://coinmarketcap.com/api) | Price fallback |

---

## 🔒 Security Checklist

- [ ] All API keys are in environment variables (not in code)
- [ ] HTTPS enabled
- [ ] Rate limiting configured
- [ ] CORS properly restricted
- [ ] MongoDB secured (if using)
- [ ] Admin endpoints protected
- [ ] Telegram alerts configured
- [ ] Backup wallet recovery tested

---

## 📊 Monitoring

### Health Check Endpoint:
```
GET https://api.yourdomain.com/health
```

### Telegram Alerts:
Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` for:
- Server startup notifications
- Error alerts
- Transaction alerts
- Fee collection summaries

---

## 💰 Revenue Setup

1. Set treasury addresses in `.env`:
   ```
   TREASURY_ETH_ADDRESS=0x...
   TREASURY_BTC_ADDRESS=bc1...
   ```

2. Fee sweep runs automatically every 24 hours

3. Monitor via admin dashboard or Telegram


# 🗄️ DATABASE SETUP GUIDE

## Current Status: Docker Not Installed

You need databases to track your revenue history. Here are your options:

---

## ✅ OPTION 1: Docker (RECOMMENDED - Easiest)

### Why Docker?
- ✅ One-click setup
- ✅ No complex configuration
- ✅ Easy to start/stop
- ✅ No conflicts with other software
- ✅ Can remove cleanly

### Installation Steps:

1. **Download Docker Desktop**
   - Visit: https://www.docker.com/products/docker-desktop/
   - Download "Docker Desktop for Windows"
   - File size: ~500MB

2. **Install Docker**
   - Run the installer
   - Accept default settings
   - **Important:** Computer will restart

3. **After Restart**
   - Docker Desktop will start automatically
   - Wait for "Docker Desktop is running" message
   - Open PowerShell in backend folder

4. **Run Setup Script**
   ```powershell
   cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
   .\setup-database-simple.ps1
   ```

5. **Done!**
   - PostgreSQL running on port 5432
   - Redis running on port 6379
   - Migrations applied automatically
   - `.env.production` updated

---

## ⚙️ OPTION 2: Windows Native Installation

### PostgreSQL

1. **Download**
   - Visit: https://www.postgresql.org/download/windows/
   - Download PostgreSQL 15 (latest stable)

2. **Install**
   - Run installer
   - Password: `CryptoWallet2025`
   - Port: `5432`
   - Install as Windows Service: YES

3. **Create Database**
   - Open "SQL Shell (psql)" from Start menu
   - Press Enter for defaults (Server, Database, Port, Username)
   - Enter your password
   - Run these commands:
   ```sql
   CREATE DATABASE crypto_wallet;
   CREATE USER crypto_admin WITH PASSWORD 'CryptoWallet2025';
   GRANT ALL PRIVILEGES ON DATABASE crypto_wallet TO crypto_admin;
   \q
   ```

### Redis

**Method A: As Windows Service (Recommended)**

1. **Download**
   - Visit: https://github.com/tporadowski/redis/releases
   - Download: `Redis-x64-5.0.14.1.zip`

2. **Install**
   - Extract to `C:\Redis`
   - Open PowerShell **as Administrator**
   - Run:
   ```powershell
   cd C:\Redis
   .\redis-server.exe --service-install redis.windows.conf
   .\redis-server.exe --service-start
   ```

**Method B: Run Manually (Simple)**

1. Extract Redis to `C:\Redis`
2. Open PowerShell:
   ```powershell
   cd C:\Redis
   Start-Process -NoNewWindow .\redis-server.exe
   ```
3. Keep this window open

### Finalize Setup

After installing both, run:
```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
.\finalize-database-setup.ps1
```

---

## 🚀 OPTION 3: Skip Database (Temporary)

If you want to start earning NOW without databases:

### What Works Without Database:
- ✅ Fee calculation (tiered pricing)
- ✅ USDT conversion
- ✅ Fee collection to your wallet
- ✅ Telegram alerts

### What You'll Miss:
- ❌ Revenue history tracking
- ❌ User activity logs
- ❌ Security event logs
- ❌ Admin dashboard analytics
- ❌ Daily/monthly revenue reports

### To Skip Database:
Your app will work without database! Just:
1. Make sure `.env.production` has your treasury address ✅
2. Start server: `node server.js`
3. Fees will collect directly to your wallet
4. Telegram alerts will still work

**You can add database later without losing any functionality!**

---

## 📊 What Database Gives You

### Revenue Tracking Table
```sql
CREATE TABLE revenue_transactions (
    transaction_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    transaction_type VARCHAR(50) NOT NULL,
    original_amount DECIMAL(36, 18) NOT NULL,
    original_amount_usd DECIMAL(20, 2) NOT NULL,
    fee_amount DECIMAL(36, 18) NOT NULL,
    fee_amount_usd DECIMAL(20, 2) NOT NULL,
    fee_percentage DECIMAL(5, 2) NOT NULL,
    treasury_address VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Daily Summary Table
```sql
CREATE TABLE daily_revenue_summary (
    date DATE NOT NULL,
    chain VARCHAR(50) NOT NULL,
    transaction_count INTEGER NOT NULL,
    total_volume_usd DECIMAL(20, 2) NOT NULL,
    total_fees_usd DECIMAL(20, 2) NOT NULL,
    average_fee_percentage DECIMAL(5, 2) NOT NULL,
    PRIMARY KEY (date, chain)
);
```

### Admin Dashboard API
With database, you get:
```powershell
# Today's revenue
GET /api/admin/revenue/stats?period=today

# Top users
GET /api/admin/revenue/top-users

# Revenue by chain
GET /api/admin/revenue/by-chain

# Security events
GET /api/admin/security/events
```

---

## ⚡ Quick Comparison

| Feature | Docker | Native | No Database |
|---------|--------|--------|-------------|
| **Setup Time** | 10 min | 30 min | 0 min |
| **Difficulty** | Easy | Medium | None |
| **Revenue Collection** | ✅ | ✅ | ✅ |
| **Telegram Alerts** | ✅ | ✅ | ✅ |
| **History Tracking** | ✅ | ✅ | ❌ |
| **Admin Dashboard** | ✅ | ✅ | ❌ |
| **Analytics** | ✅ | ✅ | ❌ |
| **Can Remove Easily** | ✅ | ❌ | N/A |

---

## 🎯 My Recommendation

**For you:** I recommend starting WITHOUT database first!

### Why?
1. ✅ You can start earning **immediately**
2. ✅ Fees still go to your wallet (0x726dac06826a2e48be08cc02835a2083644076b2)
3. ✅ Telegram alerts still work (@AmoWalletBot)
4. ✅ No complex setup needed right now
5. ✅ Can add database later anytime

### Current Configuration is Ready:
```bash
✅ Fee Structure: Tiered (1% → 0.25%)
✅ USDT Conversion: Enabled
✅ Treasury Address: 0x726dac06826a2e48be08cc02835a2083644076b2
✅ Telegram Bot: Active (1626345111)
✅ Admin API Key: Configured
```

### Start Earning Now:
```powershell
# 1. Start your server
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend
node server.js

# 2. Test it
# Make a transaction and watch the fee go to your wallet!
```

### Add Database Later:
When you want analytics and history:
1. Install Docker (10 minutes)
2. Run `.\setup-database-simple.ps1`
3. Restart server
4. Done! History starts tracking

---

## 💡 What Do You Want To Do?

**Option A:** Start earning now, add database later
- You already have everything configured!
- Just start the server: `node server.js`
- Fees collect to your wallet automatically

**Option B:** Install Docker and set up databases now
- Download Docker: https://www.docker.com/products/docker-desktop/
- Restart computer
- Run: `.\setup-database-simple.ps1`

**Option C:** Install databases natively
- Follow PostgreSQL + Redis steps above
- Run: `.\finalize-database-setup.ps1`

---

## 📞 Need Help?

### Database Not Connecting?
```powershell
# Test PostgreSQL
psql -U crypto_admin -d crypto_wallet -c "SELECT version();"

# Test Redis
redis-cli ping
```

### Want to Remove Database?
```powershell
# Docker
docker stop crypto-postgres crypto-redis
docker rm crypto-postgres crypto-redis
docker volume rm crypto-postgres-data crypto-redis-data

# Native - Uninstall via Control Panel
```

### Check Current Status
```powershell
# Docker containers
docker ps --filter "name=crypto-"

# Windows services
Get-Service -Name *postgres*
Get-Service -Name *redis*
```

---

**Bottom line:** Your monetization system works with OR without database. Database just adds tracking and analytics!

🚀 **You're ready to start earning NOW!**

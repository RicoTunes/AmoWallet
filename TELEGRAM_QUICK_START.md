# 🎉 QUICK START - Enable Telegram Alerts (2 Minutes)

## ⚡ Quick Setup (Do This Now!)

### 1️⃣ Create Telegram Bot (2 minutes)

**Open Telegram:**
- Search: `@BotFather`
- Send: `/newbot`
- Name: `Crypto Wallet Admin Bot`
- Username: `crypto_wallet_admin_bot`
- **Copy the token you get** ✓

**Get Your Chat ID:**
- Search: `@userinfobot`  
- Send any message
- Note your **User ID** ✓

### 2️⃣ Update `.env` File

Edit `backend/.env` and add:
```bash
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE
TELEGRAM_ADMIN_CHAT_ID=YOUR_CHAT_ID_HERE
```

### 3️⃣ Restart Backend

```bash
cd backend
node server.js
```

### 4️⃣ Check Telegram ✓

You should immediately receive:
```
🚀 Crypto Wallet App Started
Features: Fee Collection ✅, Sweep Service ✅, Telegram Alerts ✅
Status: ✅ ONLINE
```

---

## 🚀 That's It!

Your app now:
- ✅ Collects fees on every transaction (0.5% + min $0.50)
- ✅ Sends Telegram alerts on every fee (💰 "Fee collected: 0.005 BTC")
- ✅ Automatically sweeps fees daily at midnight (UTC)
- ✅ Converts all fees to USDT-BEP20 on BSC
- ✅ Sends sweep reports to Telegram (🎯 "Sweep Complete: $8,234.56")

---

## 💡 What Happens When Users Send Transactions

```
User sends 1 BTC
    ↓ (within 5 seconds)
Telegram Alert arrives:
💰 Fee Collected
Network: Bitcoin
Amount: 1 BTC
Fee: 0.005 BTC
Transaction: 3a8f7d...
```

Every transaction = Fee collected + Telegram notification

---

## 📊 Every 24 Hours

Midnight (UTC):
1. System aggregates all fees from 24h
2. Converts everything to USDT (via price oracle)
3. Transfers total to your admin wallet on BSC
4. Sends you detailed report:

```
🎯 Fee Sweep Complete!
Fees Collected: 347
Total Value: $8,234.56 USDT
TX Hash: 0x5a8f...
Duration: 12.34s
Status: ✅ COMPLETED
```

---

## 🔧 Admin Control (Optional)

Test endpoints:
```bash
# Check pending fees ready to sweep
curl http://localhost:3000/api/admin/fees/pending \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"

# Manual trigger sweep (don't wait 24h)
curl -X POST http://localhost:3000/api/admin/fees/sweep \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"

# Get 7-day statistics
curl http://localhost:3000/api/admin/fees/stats \
  -H "x-admin-key: YOUR_ADMIN_API_KEY"
```

---

## 📋 Files That Were Updated

- ✅ Created: `backend/src/services/feeSweepService.js` (Auto-sweep)
- ✅ Created: `backend/src/services/telegramService.js` (Alerts)
- ✅ Updated: `backend/server.js` (Initialize services)
- ✅ Updated: `backend/.env` (Telegram config)
- ✅ Updated: `backend/src/routes/blockchainRoutes.js` (Fee alerts)
- ✅ Updated: `backend/src/routes/adminRoutes.js` (Admin endpoints)

---

## ❓ Common Questions

**Q: What if I don't add Telegram?**
A: Fees are still collected and tracked in MongoDB. Telegram is optional.

**Q: How much is the fee?**
A: 0.5% per transaction (minimum $0.50 USD), 1% for swaps.

**Q: When are fees transferred?**
A: Automatically every day at midnight UTC (or manually via admin endpoint).

**Q: Where do fees go?**
A: To your admin wallet: `0x726dac06826a2e48be08cc02835a2083644076b2` on BSC as USDT.

**Q: Can I change the fee percentage?**
A: Yes, edit `.env`: `TRANSACTION_FEE_PERCENTAGE=0.5`

---

## 🎯 The System is Live!

✅ Backend running on port 3000  
✅ Fees being collected automatically  
✅ All transactions logged to MongoDB  
✅ Ready for Telegram alerts  
✅ Daily sweep scheduled  

**Just add your Telegram bot token to `.env` and restart!**

---

## 📞 Need Help?

Check logs:
```bash
tail -f backend.log | grep -E "💰|🎯|❌"
```

Full docs:
- Setup: `backend/FEE_SWEEP_SETUP.md`
- Architecture: `backend/FEE_SWEEP_ARCHITECTURE.md`
- Implementation: `IMPLEMENTATION_COMPLETE.md`

---

**You're all set!** 🚀

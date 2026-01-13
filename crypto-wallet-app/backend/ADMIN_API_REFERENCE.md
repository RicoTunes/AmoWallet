.\setup-database-simple.ps1.\setup-database-simple.ps1.\setup-database-simple.ps1# Admin API Reference

Complete guide for monitoring your crypto wallet revenue and security.

## 🔐 Authentication

All admin endpoints require the admin API key in the request header:

```bash
X-Admin-Key: your_admin_key_here
```

The admin key is generated during setup and saved in `.env.production`.

## 📊 Revenue Endpoints

### Get Revenue Statistics

Get aggregated revenue stats for a period.

**Endpoint:** `GET /api/admin/revenue/stats`

**Query Parameters:**
- `period` (optional): `today`, `month`, `all` (default: `today`)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/revenue/stats?period=today
```

**Response:**
```json
{
  "success": true,
  "period": "today",
  "stats": {
    "totalRevenue": 1250.50,
    "totalTransactions": 145,
    "averageFee": 8.63,
    "currency": "USD"
  },
  "byChain": {
    "ethereum": 850.25,
    "polygon": 250.15,
    "bsc": 150.10
  }
}
```

---

### Get Top Revenue Users

Get the highest revenue-generating users.

**Endpoint:** `GET /api/admin/revenue/top-users`

**Query Parameters:**
- `limit` (optional): Number of users to return (default: 10)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/revenue/top-users?limit=5
```

**Response:**
```json
{
  "success": true,
  "topUsers": [
    {
      "userId": "user123",
      "totalRevenue": 450.25,
      "transactionCount": 28
    }
  ]
}
```

---

### Get Daily Revenue

Get daily revenue breakdown over a period.

**Endpoint:** `GET /api/admin/revenue/daily`

**Query Parameters:**
- `days` (optional): Number of days to fetch (default: 30)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/revenue/daily?days=7
```

**Response:**
```json
{
  "success": true,
  "days": 7,
  "dailyStats": [
    {
      "date": "2024-01-15",
      "totalTransactions": 145,
      "totalRevenue": 1250.50,
      "avgFee": 8.63
    }
  ],
  "totals": {
    "totalTransactions": 980,
    "totalRevenue": 8500.25
  }
}
```

---

### Get Recent Transactions

Get recent transactions with fee details.

**Endpoint:** `GET /api/admin/transactions/recent`

**Query Parameters:**
- `limit` (optional): Number of transactions (default: 20)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/transactions/recent?limit=10
```

**Response:**
```json
{
  "success": true,
  "transactions": [
    {
      "id": 1,
      "userId": "user123",
      "chain": "ethereum",
      "transactionType": "send",
      "originalAmount": "1.0",
      "originalAmountUsd": "2000.00",
      "feeAmount": "0.005",
      "feeAmountUsd": "10.00",
      "feePercentage": "0.50",
      "status": "completed",
      "createdAt": "2024-01-15T10:30:00Z"
    }
  ]
}
```

---

## 👥 User Endpoints

### Get User Statistics

Get overall user statistics.

**Endpoint:** `GET /api/admin/users/stats`

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/users/stats
```

**Response:**
```json
{
  "success": true,
  "stats": {
    "totalUsers": 1250,
    "dailyActiveUsers": 145,
    "monthlyActiveUsers": 890
  }
}
```

---

### Get User Activity

Get recent user activity log.

**Endpoint:** `GET /api/admin/users/activity`

**Query Parameters:**
- `limit` (optional): Number of activities (default: 50)
- `suspicious` (optional): Only show suspicious activities (`true`/`false`)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  "http://localhost:3000/api/admin/users/activity?suspicious=true&limit=20"
```

**Response:**
```json
{
  "success": true,
  "activities": [
    {
      "id": 1,
      "userId": "user123",
      "activityType": "transaction",
      "ipAddress": "192.168.1.1",
      "endpoint": "/api/blockchain/send",
      "method": "POST",
      "responseStatus": 200,
      "isSuspicious": true,
      "riskScore": 75,
      "createdAt": "2024-01-15T10:30:00Z"
    }
  ],
  "count": 20
}
```

---

## 🔒 Security Endpoints

### Get Security Events

Get recent security events and attack attempts.

**Endpoint:** `GET /api/admin/security/events`

**Query Parameters:**
- `limit` (optional): Number of events (default: 50)
- `severity` (optional): Filter by severity (`low`, `medium`, `high`, `critical`)

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  "http://localhost:3000/api/admin/security/events?severity=high&limit=10"
```

**Response:**
```json
{
  "success": true,
  "events": [
    {
      "id": 1,
      "eventType": "failed_auth",
      "severity": "high",
      "ipAddress": "192.168.1.100",
      "description": "Multiple failed authentication attempts",
      "actionTaken": "IP temporarily banned",
      "createdAt": "2024-01-15T10:30:00Z"
    }
  ],
  "count": 10
}
```

**Event Types:**
- `failed_auth` - Failed authentication attempts
- `rate_limit` - Rate limit violations
- `invalid_signature` - Invalid transaction signatures
- `sql_injection` - SQL injection attempts
- `xss_attempt` - XSS attack attempts
- `brute_force` - Brute force attacks
- `unusual_pattern` - Unusual activity patterns

**Severity Levels:**
- `low` - Minor issues, logged for reference
- `medium` - Concerning activity, monitored
- `high` - Serious security events, immediate attention
- `critical` - Active attacks, automated blocking

---

## 📈 Dashboard Endpoint

### Get Complete Dashboard

Get all dashboard data in one request.

**Endpoint:** `GET /api/admin/dashboard`

**Example:**
```bash
curl -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/dashboard
```

**Response:**
```json
{
  "success": true,
  "dashboard": {
    "revenue": {
      "today": {
        "totalRevenue": 1250.50,
        "totalTransactions": 145
      },
      "byChain": {
        "ethereum": 850.25,
        "polygon": 250.15
      },
      "topUsers": [...]
    },
    "security": {
      "eventsByLevel": [
        {"severity": "high", "count": 5},
        {"severity": "medium", "count": 12}
      ]
    },
    "users": {
      "dailyActive": 145
    }
  }
}
```

---

## 🔔 Alert Endpoints

### Test Alert System

Send a test alert to verify configuration.

**Endpoint:** `POST /api/admin/alerts/test`

**Example:**
```bash
curl -X POST \
  -H "X-Admin-Key: YOUR_KEY" \
  http://localhost:3000/api/admin/alerts/test
```

**Response:**
```json
{
  "success": true,
  "message": "Test alert sent"
}
```

---

## 💡 Usage Examples

### Monitor Daily Revenue (PowerShell)

```powershell
$adminKey = "your_admin_key_here"
$headers = @{ "X-Admin-Key" = $adminKey }

# Get today's stats
$response = Invoke-RestMethod -Uri "http://localhost:3000/api/admin/revenue/stats?period=today" -Headers $headers
Write-Host "Today's Revenue: $($response.stats.totalRevenue) USD"
Write-Host "Transactions: $($response.stats.totalTransactions)"
```

### Check Security Events (PowerShell)

```powershell
$adminKey = "your_admin_key_here"
$headers = @{ "X-Admin-Key" = $adminKey }

# Get critical security events
$response = Invoke-RestMethod -Uri "http://localhost:3000/api/admin/security/events?severity=critical" -Headers $headers

foreach ($event in $response.events) {
    Write-Host "⚠️ CRITICAL: $($event.description) from $($event.ipAddress)"
}
```

### Get Revenue Report (Bash)

```bash
#!/bin/bash

ADMIN_KEY="your_admin_key_here"
API_URL="http://localhost:3000/api/admin"

# Get monthly revenue
curl -s -H "X-Admin-Key: $ADMIN_KEY" \
  "$API_URL/revenue/stats?period=month" | jq '.stats'

# Get top users
curl -s -H "X-Admin-Key: $ADMIN_KEY" \
  "$API_URL/revenue/top-users?limit=5" | jq '.topUsers'
```

---

## 🔌 Integration Examples

### Python Dashboard Script

```python
import requests
import json
from datetime import datetime

ADMIN_KEY = "your_admin_key_here"
API_URL = "http://localhost:3000/api/admin"
HEADERS = {"X-Admin-Key": ADMIN_KEY}

def get_dashboard():
    response = requests.get(f"{API_URL}/dashboard", headers=HEADERS)
    return response.json()

def print_report():
    data = get_dashboard()
    
    print("=" * 50)
    print(f"CRYPTO WALLET DASHBOARD - {datetime.now()}")
    print("=" * 50)
    
    revenue = data['dashboard']['revenue']['today']
    print(f"\n💰 Today's Revenue: ${revenue['totalRevenue']}")
    print(f"📊 Transactions: {revenue['totalTransactions']}")
    
    security = data['dashboard']['security']['eventsByLevel']
    print(f"\n🔒 Security Events:")
    for event in security:
        print(f"  {event['severity'].upper()}: {event['count']}")
    
    users = data['dashboard']['users']
    print(f"\n👥 Daily Active Users: {users['dailyActive']}")

if __name__ == "__main__":
    print_report()
```

### Node.js Monitoring Script

```javascript
const axios = require('axios');

const ADMIN_KEY = 'your_admin_key_here';
const API_URL = 'http://localhost:3000/api/admin';

async function monitorRevenue() {
  try {
    const response = await axios.get(`${API_URL}/revenue/stats?period=today`, {
      headers: { 'X-Admin-Key': ADMIN_KEY }
    });
    
    const { stats } = response.data;
    console.log(`💰 Revenue: $${stats.totalRevenue}`);
    console.log(`📊 Transactions: ${stats.totalTransactions}`);
    
    // Alert if revenue is high
    if (stats.totalRevenue > 1000) {
      console.log('🎉 Daily target reached!');
    }
  } catch (error) {
    console.error('Error:', error.message);
  }
}

// Run every hour
setInterval(monitorRevenue, 60 * 60 * 1000);
monitorRevenue(); // Run immediately
```

---

## 🔐 Security Best Practices

1. **Protect Your Admin Key**
   - Never commit to version control
   - Store in environment variables only
   - Rotate regularly (monthly recommended)

2. **IP Whitelisting** (Add to middleware)
   ```javascript
   const allowedIPs = process.env.ADMIN_ALLOWED_IPS.split(',');
   if (!allowedIPs.includes(req.ip)) {
     return res.status(403).json({ error: 'Access denied' });
   }
   ```

3. **Rate Limiting**
   - Limit admin API calls to prevent abuse
   - Use `express-rate-limit` package

4. **HTTPS Only**
   - Always use HTTPS in production
   - Admin key transmitted over HTTP is insecure

5. **Audit Logging**
   - Log all admin API access
   - Monitor for unusual patterns

---

## 📱 Telegram Bot Integration

To receive instant alerts on your phone:

1. Create a Telegram bot via @BotFather
2. Get your bot token
3. Start a chat with your bot
4. Get your chat ID from @userinfobot
5. Configure in `.env.production`:
   ```bash
   TELEGRAM_BOT_TOKEN=your_bot_token
   TELEGRAM_CHAT_ID=your_chat_id
   ENABLE_TELEGRAM_ALERTS=true
   ```

---

## 🐛 Troubleshooting

### 401 Unauthorized
- Check your admin API key
- Verify `X-Admin-Key` header is set
- Ensure `.env.production` is loaded

### 500 Internal Server Error
- Check database connection
- Verify tables exist (run migrations)
- Check server logs

### Empty Data
- Ensure revenue tracking is enabled
- Verify transactions are being processed
- Check database for records

---

## 📞 Support

For issues or questions:
- Check `MONETIZATION_GUIDE.md` for setup help
- Review server logs: `logs/combined.log`
- Test database connection: `npm run test:db`

---

**Created:** January 2024  
**Version:** 1.0  
**Last Updated:** {{ timestamp }}

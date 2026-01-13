# Production Server Setup Guide
Complete guide for setting up Crypto Wallet Pro in production

## Prerequisites
- Ubuntu 20.04+ or Debian 11+ server
- Sudo access
- Domain name pointed to server IP
- Minimum 2GB RAM, 2 CPU cores

## Step 1: Initial Server Setup

### 1.1 Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Install Node.js (v18+)
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
node --version  # Verify installation
```

### 1.3 Install PostgreSQL
```bash
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### 1.4 Install Redis
```bash
sudo apt install -y redis-server
sudo systemctl start redis
sudo systemctl enable redis
```

### 1.5 Install Git (if deploying from repository)
```bash
sudo apt install -y git
```

## Step 2: Database Setup

### 2.1 Create PostgreSQL Database and User
```bash
sudo -u postgres psql
```

In PostgreSQL console:
```sql
CREATE DATABASE crypto_wallet;
CREATE USER crypto_wallet_user WITH ENCRYPTED PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE crypto_wallet TO crypto_wallet_user;
\q
```

### 2.2 Configure Redis
```bash
sudo nano /etc/redis/redis.conf
```

Update settings:
```
maxmemory 256mb
maxmemory-policy allkeys-lru
```

Restart Redis:
```bash
sudo systemctl restart redis
```

## Step 3: Application Setup

### 3.1 Copy Application Files
```bash
# If from repository
cd /home/RICO/ricoamos
git clone <your-repo-url> crypto-wallet-app

# Or upload files via scp/sftp
```

### 3.2 Install Dependencies
```bash
cd /home/RICO/ricoamos/crypto-wallet-app/backend
npm ci --production
```

### 3.3 Configure Environment
```bash
cp .env.production.example .env.production
nano .env.production
```

**Required Configuration:**
```env
# Server
NODE_ENV=production
PORT=3000

# HTTPS
ENABLE_HTTPS=true
HTTPS_PORT=443
HTTP_REDIRECT_PORT=80
DOMAIN=yourdomain.com
SSL_CERT_PATH=/etc/letsencrypt/live/yourdomain.com

# Database
DATABASE_URL=postgresql://crypto_wallet_user:your_secure_password@localhost:5432/crypto_wallet
REDIS_URL=redis://localhost:6379

# Session Secret (generate with: openssl rand -base64 32)
SESSION_SECRET=your_generated_session_secret

# Rate Limiting
REDIS_RATE_LIMIT_ENABLED=true
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# Monitoring
LOG_LEVEL=info
SENTRY_DSN=https://your-sentry-dsn  # Optional

# Blockchain APIs (get from providers)
INFURA_PROJECT_ID=your_infura_project_id
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
BSCSCAN_API_KEY=your_bscscan_api_key
# ... add other API keys
```

### 3.4 Run Database Migrations
```bash
cd /home/RICO/ricoamos/crypto-wallet-app/backend
bash scripts/run-migrations.sh
```

Verify migrations:
```bash
# Should show applied migrations
psql $DATABASE_URL -c "SELECT * FROM schema_migrations;"
```

## Step 4: SSL Certificate Setup

### 4.1 Run SSL Setup Script
```bash
cd /home/RICO/ricoamos/crypto-wallet-app/backend
sudo bash scripts/setup-ssl.sh yourdomain.com admin@yourdomain.com
```

### 4.2 Verify Certificate
```bash
sudo certbot certificates
```

Certificate should be at:
- `/etc/letsencrypt/live/yourdomain.com/fullchain.pem`
- `/etc/letsencrypt/live/yourdomain.com/privkey.pem`

## Step 5: Systemd Service Setup

### 5.1 Copy Service File
```bash
sudo cp systemd/crypto-wallet-backend.service /etc/systemd/system/
```

### 5.2 Update Service File (if needed)
```bash
sudo nano /etc/systemd/system/crypto-wallet-backend.service
```

Verify paths match your setup:
- `User=RICO`
- `WorkingDirectory=/home/RICO/ricoamos/crypto-wallet-app/backend`
- `EnvironmentFile=/home/RICO/ricoamos/crypto-wallet-app/backend/.env.production`

### 5.3 Enable and Start Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable crypto-wallet-backend
sudo systemctl start crypto-wallet-backend
```

### 5.4 Check Service Status
```bash
sudo systemctl status crypto-wallet-backend
```

Should show: `active (running)`

## Step 6: Firewall Configuration

### 6.1 Install UFW (if not installed)
```bash
sudo apt install -y ufw
```

### 6.2 Configure Firewall Rules
```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP (for Let's Encrypt validation)
sudo ufw allow 80/tcp

# Allow HTTPS
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
```

### 6.3 Verify Rules
```bash
sudo ufw status
```

## Step 7: Monitoring Setup

### 7.1 Install Sentry SDK (Optional)
```bash
cd /home/RICO/ricoamos/crypto-wallet-app/backend
npm install @sentry/node
```

### 7.2 Create Log Directory
```bash
mkdir -p /home/RICO/ricoamos/crypto-wallet-app/backend/logs
chmod 755 /home/RICO/ricoamos/crypto-wallet-app/backend/logs
```

### 7.3 Setup Log Rotation
```bash
sudo nano /etc/logrotate.d/crypto-wallet
```

Add:
```
/home/RICO/ricoamos/crypto-wallet-app/backend/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    missingok
    sharedscripts
    postrotate
        systemctl reload crypto-wallet-backend > /dev/null 2>&1 || true
    endscript
}
```

## Step 8: Verification

### 8.1 Health Checks
```bash
# Basic health
curl https://yourdomain.com/health

# Detailed health
curl https://yourdomain.com/health/detailed

# Database health
curl https://yourdomain.com/health/db

# Redis health
curl https://yourdomain.com/health/redis
```

All should return `status: "healthy"`

### 8.2 Test API Endpoints
```bash
# Test API key generation
curl -X POST https://yourdomain.com/api/auth/keys \
  -H "Content-Type: application/json" \
  -d '{"name": "test-key"}'
```

### 8.3 Test HTTPS Redirect
```bash
# HTTP should redirect to HTTPS
curl -I http://yourdomain.com/health
# Should show: Location: https://yourdomain.com/health
```

### 8.4 View Logs
```bash
# Real-time logs
sudo journalctl -u crypto-wallet-backend -f

# Recent logs
sudo journalctl -u crypto-wallet-backend -n 100

# Application logs
tail -f /home/RICO/ricoamos/crypto-wallet-app/backend/logs/combined-*.log
```

## Step 9: Performance Tuning

### 9.1 PostgreSQL Tuning
```bash
sudo nano /etc/postgresql/*/main/postgresql.conf
```

Recommended settings (adjust for your server):
```
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
max_connections = 100
```

Restart PostgreSQL:
```bash
sudo systemctl restart postgresql
```

### 9.2 Node.js Memory Settings
Update systemd service file:
```bash
sudo nano /etc/systemd/system/crypto-wallet-backend.service
```

Add to `[Service]` section:
```
Environment="NODE_OPTIONS=--max-old-space-size=1024"
```

Reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart crypto-wallet-backend
```

## Step 10: Backup Setup

### 10.1 Create Backup Script
```bash
nano /home/RICO/backup-crypto-wallet.sh
```

Content:
```bash
#!/bin/bash
BACKUP_DIR="/home/RICO/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup database
pg_dump $DATABASE_URL > "$BACKUP_DIR/database.sql"

# Backup .env file
cp /home/RICO/ricoamos/crypto-wallet-app/backend/.env.production "$BACKUP_DIR/"

# Compress
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"

# Keep only last 7 days
find /home/RICO/backups -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR.tar.gz"
```

Make executable:
```bash
chmod +x /home/RICO/backup-crypto-wallet.sh
```

### 10.2 Schedule Daily Backups
```bash
crontab -e
```

Add:
```
0 2 * * * /home/RICO/backup-crypto-wallet.sh >> /home/RICO/backup.log 2>&1
```

## Useful Commands

### Service Management
```bash
# Start service
sudo systemctl start crypto-wallet-backend

# Stop service
sudo systemctl stop crypto-wallet-backend

# Restart service
sudo systemctl restart crypto-wallet-backend

# View status
sudo systemctl status crypto-wallet-backend

# View logs
sudo journalctl -u crypto-wallet-backend -f
```

### Database Management
```bash
# Connect to database
psql $DATABASE_URL

# Backup database
pg_dump $DATABASE_URL > backup.sql

# Restore database
psql $DATABASE_URL < backup.sql
```

### SSL Certificate Management
```bash
# Renew certificates
sudo certbot renew

# Test renewal (dry run)
sudo certbot renew --dry-run

# List certificates
sudo certbot certificates
```

## Troubleshooting

### Service Won't Start
```bash
# Check logs
sudo journalctl -u crypto-wallet-backend -n 100

# Check permissions
ls -la /home/RICO/ricoamos/crypto-wallet-app/backend

# Test manually
cd /home/RICO/ricoamos/crypto-wallet-app/backend
node server.js
```

### Database Connection Issues
```bash
# Test PostgreSQL connection
psql $DATABASE_URL -c "SELECT 1;"

# Check PostgreSQL status
sudo systemctl status postgresql

# Check Redis
redis-cli ping
```

### SSL Certificate Issues
```bash
# Check certificate validity
sudo certbot certificates

# Test HTTPS
curl -v https://yourdomain.com/health

# Check certificate expiry
openssl x509 -in /etc/letsencrypt/live/yourdomain.com/fullchain.pem -noout -dates
```

## Security Checklist

- [ ] Strong database passwords set
- [ ] SESSION_SECRET generated and configured
- [ ] Firewall enabled with only necessary ports open
- [ ] SSL certificates installed and auto-renewal configured
- [ ] Rate limiting enabled
- [ ] API authentication configured
- [ ] Regular backups scheduled
- [ ] Logs being rotated
- [ ] Monitoring/alerting configured
- [ ] All API keys from providers obtained
- [ ] .env.production has proper permissions (600)
- [ ] Database user has minimal necessary privileges

## Maintenance Schedule

### Daily
- Automated backups (2:00 AM)
- SSL certificate renewal check (twice daily)
- Log rotation

### Weekly
- Review error logs
- Check disk space
- Review performance metrics

### Monthly
- Review and update dependencies
- Security audit
- Test backup restoration
- Review access logs

## Next Steps

1. ✅ Configure DNS records to point to server
2. ✅ Obtain and configure all blockchain API keys
3. ✅ Set up monitoring/alerting (Sentry, etc.)
4. ✅ Test all API endpoints
5. ✅ Load test application
6. ✅ Configure CDN (optional, for static assets)
7. ✅ Set up staging environment
8. ✅ Document API for frontend integration

## Support

For issues or questions:
- Check logs: `sudo journalctl -u crypto-wallet-backend -f`
- Review health endpoints: `curl https://yourdomain.com/health/detailed`
- Consult documentation in `/docs` folder

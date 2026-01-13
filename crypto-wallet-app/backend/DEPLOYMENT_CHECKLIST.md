# Production Deployment Checklist
Complete pre-deployment verification checklist for Crypto Wallet Pro

## Pre-Deployment Checklist

### 1. Server Requirements ✅
- [ ] Ubuntu 20.04+ or Debian 11+ installed
- [ ] Minimum 2GB RAM, 2 CPU cores
- [ ] At least 20GB free disk space
- [ ] Root/sudo access available
- [ ] Server accessible via SSH
- [ ] Firewall configured (ports 22, 80, 443)

### 2. DNS Configuration ✅
- [ ] Domain name purchased
- [ ] A record points to server IP address
- [ ] DNS propagation completed (check with `nslookup yourdomain.com`)
- [ ] WWW subdomain configured (optional)

### 3. Dependencies Installed ✅
- [ ] Node.js v18+ installed (`node --version`)
- [ ] npm installed (`npm --version`)
- [ ] PostgreSQL 13+ installed and running (`systemctl status postgresql`)
- [ ] Redis installed and running (`systemctl status redis`)
- [ ] Git installed (if deploying from repo)
- [ ] Certbot installed for SSL certificates

### 4. Database Setup ✅
- [ ] PostgreSQL database created (`crypto_wallet`)
- [ ] Database user created with strong password
- [ ] User has proper permissions on database
- [ ] Can connect: `psql postgresql://user:pass@localhost:5432/crypto_wallet`
- [ ] Redis running and accessible: `redis-cli ping` returns PONG

### 5. SSL Certificates ✅
- [ ] Certbot installed
- [ ] SSL certificates obtained for domain
- [ ] Certificates located in `/etc/letsencrypt/live/yourdomain.com/`
- [ ] Auto-renewal configured (cron job exists)
- [ ] Certificates valid: `sudo certbot certificates`
- [ ] Test renewal: `sudo certbot renew --dry-run`

### 6. Application Files ✅
- [ ] All application files uploaded/cloned to server
- [ ] Files in `/home/RICO/ricoamos/crypto-wallet-app/backend/`
- [ ] Correct file permissions set
- [ ] Dependencies installed: `npm ci --production`
- [ ] No errors during `npm install`

### 7. Environment Configuration ✅
- [ ] `.env.production` file created from `.env.production.example`
- [ ] `NODE_ENV=production` set
- [ ] `DATABASE_URL` configured with correct credentials
- [ ] `REDIS_URL` configured
- [ ] `SESSION_SECRET` generated (32+ random bytes)
- [ ] `DOMAIN` set to your domain
- [ ] `SSL_CERT_PATH` points to Let's Encrypt certificates
- [ ] `ENABLE_HTTPS=true` set
- [ ] All blockchain API keys obtained and configured:
  - [ ] INFURA_PROJECT_ID
  - [ ] ETHERSCAN_API_KEY
  - [ ] POLYGONSCAN_API_KEY
  - [ ] BSCSCAN_API_KEY
  - [ ] OPTIMISM_API_KEY
  - [ ] ARBITRUM_API_KEY
  - [ ] AVALANCHE_API_KEY
  - [ ] FANTOM_API_KEY
- [ ] `SENTRY_DSN` configured (if using Sentry)
- [ ] `CORS_ORIGIN` set to production domain
- [ ] File permissions set: `chmod 600 .env.production`

### 8. Database Migrations ✅
- [ ] Migration scripts exist in `migrations/` folder
- [ ] Run migrations: `bash scripts/run-migrations.sh`
- [ ] No migration errors
- [ ] Verify tables created: `psql $DATABASE_URL -c "\dt"`
- [ ] Expected tables present:
  - [ ] api_keys
  - [ ] transactions
  - [ ] spending_history
  - [ ] sessions
  - [ ] wallet_addresses
  - [ ] confirmation_tracking
  - [ ] audit_log
  - [ ] schema_migrations

### 9. Systemd Service ✅
- [ ] Service file copied to `/etc/systemd/system/crypto-wallet-backend.service`
- [ ] Service file updated with correct user and paths
- [ ] Daemon reloaded: `sudo systemctl daemon-reload`
- [ ] Service enabled: `sudo systemctl enable crypto-wallet-backend`
- [ ] Service started: `sudo systemctl start crypto-wallet-backend`
- [ ] Service status: `sudo systemctl status crypto-wallet-backend` shows active
- [ ] No errors in service logs: `sudo journalctl -u crypto-wallet-backend -n 50`

### 10. Monitoring & Logging ✅
- [ ] Winston logger configured
- [ ] Log directory exists and writable: `/home/RICO/ricoamos/crypto-wallet-app/backend/logs/`
- [ ] Log rotation configured in `/etc/logrotate.d/crypto-wallet`
- [ ] Sentry configured (if using)
- [ ] Test Sentry: trigger test error and check Sentry dashboard
- [ ] Metrics endpoint accessible: `curl https://yourdomain.com/health/metrics`

### 11. Security Configuration ✅
- [ ] Firewall enabled: `sudo ufw status`
- [ ] Only necessary ports open (22, 80, 443)
- [ ] SSH configured with key-based auth (password auth disabled)
- [ ] Strong passwords for database user
- [ ] `.env.production` not committed to git
- [ ] `.env.production` has restricted permissions (600)
- [ ] Rate limiting enabled in `.env.production`
- [ ] HTTPS enforced (HTTP redirects to HTTPS)
- [ ] Security headers enabled: `SECURITY_HEADERS_ENABLED=true`
- [ ] CORS configured for production domain only

### 12. API Testing ✅
Test all endpoints to verify functionality:

#### Health Checks
```bash
# Basic health
curl https://yourdomain.com/health

# Detailed health (should show database and Redis connected)
curl https://yourdomain.com/health/detailed

# Database health
curl https://yourdomain.com/health/db

# Redis health
curl https://yourdomain.com/health/redis

# Readiness probe
curl https://yourdomain.com/health/ready

# Metrics
curl https://yourdomain.com/health/metrics
```

- [ ] All health endpoints return 200 OK
- [ ] Database health shows "connected"
- [ ] Redis health shows "connected"

#### Authentication
```bash
# Generate API key
curl -X POST https://yourdomain.com/api/auth/keys/generate \
  -H "Content-Type: application/json" \
  -d '{"name": "production-test-key"}'

# Save the returned API key and secret for next tests
```

- [ ] API key generation works
- [ ] Returns valid API key and secret

#### Wallet Operations
```bash
# Generate wallet (replace with your API key and signature)
curl -X POST https://yourdomain.com/api/wallet/generate \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "X-Signature: YOUR_SIGNATURE" \
  -H "X-Timestamp: $(date +%s)000" \
  -d '{}'
```

- [ ] Wallet generation works with authentication

#### Blockchain Operations
```bash
# Get balance (with valid auth headers)
curl https://yourdomain.com/api/blockchain/balance/ethereum/0xYourAddress \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "X-Signature: YOUR_SIGNATURE" \
  -H "X-Timestamp: $(date +%s)000"
```

- [ ] Balance check works
- [ ] Returns valid response

### 13. Performance Testing ✅
- [ ] Load test with 100 concurrent requests succeeds
- [ ] Average response time < 500ms
- [ ] No memory leaks after 1 hour of operation
- [ ] Database connection pool working correctly
- [ ] Redis caching functional

### 14. Backup Configuration ✅
- [ ] Backup script created: `/home/RICO/backup-crypto-wallet.sh`
- [ ] Backup script executable: `chmod +x backup-crypto-wallet.sh`
- [ ] Cron job scheduled for daily backups
- [ ] Backup directory exists: `/home/RICO/backups/`
- [ ] Test backup: `./backup-crypto-wallet.sh`
- [ ] Backup file created successfully
- [ ] Test restore from backup

### 15. Documentation ✅
- [ ] Production setup guide reviewed
- [ ] API documentation available
- [ ] Deployment procedures documented
- [ ] Troubleshooting guide created
- [ ] Emergency contacts list prepared

### 16. Monitoring Alerts ✅
- [ ] Sentry error alerts configured
- [ ] Server monitoring configured (optional: Datadog, New Relic)
- [ ] Disk space monitoring
- [ ] SSL certificate expiry alerts (certbot handles this)
- [ ] Uptime monitoring configured (optional: UptimeRobot, Pingdom)

### 17. Final Verification ✅

#### Server Health
```bash
# Check all services running
systemctl status postgresql
systemctl status redis
systemctl status crypto-wallet-backend

# Check disk space
df -h

# Check memory
free -h

# Check logs for errors
sudo journalctl -u crypto-wallet-backend -n 100 --no-pager | grep -i error
```

- [ ] All services active
- [ ] Sufficient disk space (>20% free)
- [ ] Sufficient memory available
- [ ] No critical errors in logs

#### Application Health
```bash
# Run all health checks
curl https://yourdomain.com/health/detailed
```

- [ ] Status: "healthy"
- [ ] Database: "healthy"
- [ ] Redis: "healthy"
- [ ] Uptime > 5 minutes (stable)

#### HTTPS Configuration
```bash
# Test HTTPS
curl -I https://yourdomain.com/health

# Test HTTP redirect
curl -I http://yourdomain.com/health

# Test SSL certificate
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com < /dev/null
```

- [ ] HTTPS responds with 200
- [ ] HTTP redirects to HTTPS (301)
- [ ] SSL certificate valid and not expired
- [ ] SSL labs grade A or higher: https://www.ssllabs.com/ssltest/

### 18. Rollback Plan ✅
- [ ] Previous version backed up
- [ ] Rollback procedure documented
- [ ] Database restore procedure tested
- [ ] Able to restore from backup in <10 minutes

### 19. Post-Deployment Monitoring ✅
First 24 hours after deployment:

- [ ] Monitor error rates (should be <1%)
- [ ] Monitor response times (should be <500ms avg)
- [ ] Monitor CPU usage (should be <70%)
- [ ] Monitor memory usage (should be <80%)
- [ ] Check for memory leaks
- [ ] Review Sentry errors
- [ ] Check logs every 4 hours

### 20. Production Readiness Sign-off ✅
- [ ] All critical features tested
- [ ] Performance acceptable
- [ ] Security measures in place
- [ ] Monitoring active
- [ ] Backups configured
- [ ] Team trained on deployment procedures
- [ ] Emergency procedures documented
- [ ] Stakeholders notified of deployment

---

## Quick Commands Reference

### Service Management
```bash
# Start
sudo systemctl start crypto-wallet-backend

# Stop
sudo systemctl stop crypto-wallet-backend

# Restart
sudo systemctl restart crypto-wallet-backend

# Status
sudo systemctl status crypto-wallet-backend

# Logs
sudo journalctl -u crypto-wallet-backend -f
```

### Health Checks
```bash
# Basic health
curl https://yourdomain.com/health

# Detailed with DB status
curl https://yourdomain.com/health/detailed

# Database only
curl https://yourdomain.com/health/db

# Redis only
curl https://yourdomain.com/health/redis
```

### Database
```bash
# Connect
psql $DATABASE_URL

# Backup
pg_dump $DATABASE_URL > backup.sql

# Restore
psql $DATABASE_URL < backup.sql
```

### SSL
```bash
# Check certificates
sudo certbot certificates

# Renew (manual test)
sudo certbot renew --dry-run
```

---

## Deployment Complete! 🎉

Once all items are checked off:
1. System is production-ready
2. All security measures in place
3. Monitoring active
4. Backups configured
5. Ready to serve traffic

**Next Steps:**
- Monitor application for first 24-48 hours
- Review error logs daily for first week
- Gradually increase traffic
- Optimize based on real usage patterns

**Emergency Contacts:**
- System Admin: [Your contact]
- Database Admin: [Your contact]
- On-call Engineer: [Your contact]

---

## Troubleshooting Quick Links

If issues arise:
1. Check service status: `sudo systemctl status crypto-wallet-backend`
2. Review logs: `sudo journalctl -u crypto-wallet-backend -n 100`
3. Test database: `psql $DATABASE_URL -c "SELECT 1;"`
4. Test Redis: `redis-cli ping`
5. Check health endpoint: `curl https://yourdomain.com/health/detailed`
6. Review PRODUCTION_SETUP_GUIDE.md troubleshooting section

**Last Updated:** $(date +"%Y-%m-%d")

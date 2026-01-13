#!/bin/bash

# SSL Certificate Setup Script for Crypto Wallet Pro
# This script sets up Let's Encrypt SSL certificates for production deployment

set -e  # Exit on error

echo "🔐 SSL Certificate Setup for Crypto Wallet Pro"
echo "=============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

# Variables (customize these)
DOMAIN="${1:-yourdomain.com}"
EMAIL="${2:-admin@yourdomain.com}"
WEBROOT="/var/www/html"

echo ""
echo "📝 Configuration:"
echo "   Domain: $DOMAIN"
echo "   Email: $EMAIL"
echo "   Webroot: $WEBROOT"
echo ""

# Confirm setup
read -p "Continue with these settings? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled"
    exit 1
fi

# Step 1: Update system packages
echo ""
echo "📦 Step 1: Updating system packages..."
apt-get update -qq

# Step 2: Install Certbot
echo ""
echo "📥 Step 2: Installing Certbot..."
if ! command -v certbot &> /dev/null; then
    apt-get install -y certbot
    echo "✅ Certbot installed"
else
    echo "✅ Certbot already installed"
fi

# Step 3: Stop services using port 80
echo ""
echo "🛑 Step 3: Stopping services on port 80..."
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
pkill -f "node.*server.js" 2>/dev/null || true

# Step 4: Obtain SSL certificate
echo ""
echo "🔐 Step 4: Obtaining SSL certificate from Let's Encrypt..."
certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    --preferred-challenges http

if [ $? -eq 0 ]; then
    echo "✅ SSL certificate obtained successfully"
else
    echo "❌ Failed to obtain SSL certificate"
    exit 1
fi

# Step 5: Certificate paths
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
echo ""
echo "📂 Certificate files:"
echo "   Certificate: $CERT_PATH/fullchain.pem"
echo "   Private Key: $CERT_PATH/privkey.pem"

# Step 6: Set up auto-renewal
echo ""
echo "🔄 Step 5: Setting up automatic renewal..."

# Create renewal script
cat > /usr/local/bin/renew-crypto-wallet-cert.sh << 'EOF'
#!/bin/bash
certbot renew --quiet --deploy-hook "systemctl restart crypto-wallet-backend"
EOF

chmod +x /usr/local/bin/renew-crypto-wallet-cert.sh

# Add to crontab (run twice daily)
if ! crontab -l 2>/dev/null | grep -q "renew-crypto-wallet-cert"; then
    (crontab -l 2>/dev/null; echo "0 0,12 * * * /usr/local/bin/renew-crypto-wallet-cert.sh") | crontab -
    echo "✅ Cron job added for automatic renewal"
else
    echo "✅ Cron job already exists"
fi

# Step 7: Update .env.production file
echo ""
echo "📝 Step 6: Updating .env.production..."
ENV_FILE="/home/$(logname)/ricoamos/crypto-wallet-app/backend/.env.production"

if [ -f "$ENV_FILE" ]; then
    # Update existing .env.production
    sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN|g" "$ENV_FILE"
    sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=$CERT_PATH|g" "$ENV_FILE"
    sed -i "s|^ENABLE_HTTPS=.*|ENABLE_HTTPS=true|g" "$ENV_FILE"
    echo "✅ .env.production updated"
else
    echo "⚠️  .env.production not found at $ENV_FILE"
    echo "   Please manually update your environment file with:"
    echo "   DOMAIN=$DOMAIN"
    echo "   SSL_CERT_PATH=$CERT_PATH"
    echo "   ENABLE_HTTPS=true"
fi

# Step 8: Set permissions
echo ""
echo "🔒 Step 7: Setting certificate permissions..."
chmod 755 /etc/letsencrypt/live
chmod 755 /etc/letsencrypt/archive
echo "✅ Permissions set"

# Step 9: Test certificate
echo ""
echo "🧪 Step 8: Testing certificate..."
certbot certificates

# Summary
echo ""
echo "=============================================="
echo "✅ SSL Certificate Setup Complete!"
echo "=============================================="
echo ""
echo "📋 Next Steps:"
echo "   1. Update your .env.production with:"
echo "      DOMAIN=$DOMAIN"
echo "      SSL_CERT_PATH=$CERT_PATH"
echo "      ENABLE_HTTPS=true"
echo ""
echo "   2. Point your domain DNS to this server's IP"
echo ""
echo "   3. Start your backend server with:"
echo "      cd /home/$(logname)/ricoamos/crypto-wallet-app/backend"
echo "      npm run start:production"
echo ""
echo "   4. Verify HTTPS is working:"
echo "      curl https://$DOMAIN/health"
echo ""
echo "   5. Certificate will auto-renew every 60 days"
echo ""
echo "📂 Certificate Location:"
echo "   $CERT_PATH"
echo ""
echo "🔄 Manual Renewal Command:"
echo "   certbot renew"
echo ""

# Create verification checklist
cat > /root/ssl-setup-verification.txt << EOF
SSL Setup Verification Checklist
=================================

✅ Certbot installed
✅ Certificate obtained for $DOMAIN
✅ Auto-renewal configured
✅ Permissions set

Next Steps:
[ ] Update .env.production
[ ] Configure DNS records
[ ] Start backend server
[ ] Test HTTPS connection
[ ] Verify auto-renewal: certbot renew --dry-run

Certificate expires on: $(date -d "+90 days" +%Y-%m-%d)
Auto-renewal scheduled: Twice daily at 00:00 and 12:00
EOF

echo "📄 Verification checklist saved to: /root/ssl-setup-verification.txt"

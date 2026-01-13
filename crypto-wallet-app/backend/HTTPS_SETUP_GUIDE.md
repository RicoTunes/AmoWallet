# SSL/HTTPS Configuration Guide

## Overview
This backend supports both development (self-signed certificates) and production (Let's Encrypt) HTTPS configurations.

## Environment Variables

Add these to your `.env` file:

```env
# Enable/Disable HTTPS
ENABLE_HTTPS=true

# Environment (development or production)
NODE_ENV=development

# Domain name (required for production Let's Encrypt)
DOMAIN=yourdomain.com

# SSL certificate path (production only)
SSL_CERT_PATH=/etc/letsencrypt/live

# Server ports
PORT=3000
HTTPS_PORT=443
HTTP_REDIRECT_PORT=80
```

## Development Setup (Self-Signed Certificates)

### Automatic Generation
The system automatically generates self-signed certificates on first run:

```bash
cd crypto-wallet-app/backend
npm start
```

Certificates are stored in: `backend/certs/`

### Manual Generation (Optional)
If you need to manually create certificates:

```bash
# Navigate to backend directory
cd crypto-wallet-app/backend

# Create certs directory
mkdir -p certs

# Generate self-signed certificate (valid for 365 days)
openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Development/CN=localhost"
```

### Trust Self-Signed Certificate (Optional)
To avoid browser warnings during development:

**Windows:**
1. Double-click `certs/cert.pem`
2. Click "Install Certificate"
3. Select "Local Machine"
4. Choose "Place all certificates in the following store"
5. Browse to "Trusted Root Certification Authorities"
6. Complete the wizard

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/cert.pem
```

**Linux:**
```bash
sudo cp certs/cert.pem /usr/local/share/ca-certificates/dev-cert.crt
sudo update-ca-certificates
```

## Production Setup (Let's Encrypt)

### Prerequisites
- A registered domain name pointing to your server
- Ports 80 and 443 accessible from the internet
- Root/sudo access to install Certbot

### Install Certbot

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install certbot
```

**CentOS/RHEL:**
```bash
sudo yum install certbot
```

**Windows:**
Download from: https://certbot.eff.org/

### Obtain Let's Encrypt Certificate

#### Method 1: Standalone (Recommended for initial setup)
```bash
# Stop your backend server if running
sudo systemctl stop your-backend-service

# Obtain certificate
sudo certbot certonly --standalone -d yourdomain.com -d www.yourdomain.com

# Certificates will be stored in:
# /etc/letsencrypt/live/yourdomain.com/
```

#### Method 2: Webroot (If server is running)
```bash
sudo certbot certonly --webroot -w /var/www/html -d yourdomain.com -d www.yourdomain.com
```

### Certificate Renewal

Let's Encrypt certificates expire every 90 days. Setup automatic renewal:

**Create renewal script:**
```bash
sudo nano /etc/cron.d/certbot-renew
```

**Add this content:**
```cron
0 0 * * * root certbot renew --quiet --post-hook "systemctl reload your-backend-service"
```

**Test renewal:**
```bash
sudo certbot renew --dry-run
```

### Backend Configuration

Update your `.env` file:

```env
ENABLE_HTTPS=true
NODE_ENV=production
DOMAIN=yourdomain.com
SSL_CERT_PATH=/etc/letsencrypt/live
PORT=3000
HTTPS_PORT=443
HTTP_REDIRECT_PORT=80
```

### Run Backend with HTTPS

```bash
# Make sure certificates exist
ls /etc/letsencrypt/live/yourdomain.com/

# Start backend (requires sudo for ports 80/443)
sudo npm start
```

## Frontend Configuration

### Update API Endpoint

**lib/core/config/api_config.dart:**
```dart
class ApiConfig {
  // Development
  static const String devBaseUrl = 'https://localhost:3000';
  
  // Production
  static const String prodBaseUrl = 'https://yourdomain.com';
  
  static String get baseUrl {
    return kDebugMode ? devBaseUrl : prodBaseUrl;
  }
}
```

### Update Certificate Pinning

Get your SSL certificate fingerprint:

```bash
# Production certificate
openssl x509 -in /etc/letsencrypt/live/yourdomain.com/cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64

# Development certificate
openssl x509 -in backend/certs/cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
```

**Update lib/services/secure_http_client.dart:**
```dart
final Map<String, List<String>> certificateFingerprints = {
  'localhost:3000': ['YOUR_DEV_FINGERPRINT_HERE'],
  'yourdomain.com': ['YOUR_PROD_FINGERPRINT_HERE'],
};
```

## Firewall Configuration

### Allow HTTPS traffic:

**Ubuntu/Debian (ufw):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

**CentOS/RHEL (firewalld):**
```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

**Windows Firewall:**
```powershell
New-NetFirewallRule -DisplayName "HTTP" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "HTTPS" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
```

## Testing HTTPS Connection

### Test Backend
```bash
# Check HTTPS endpoint
curl -k https://localhost:3000/health

# Check HTTP redirect (production)
curl -I http://yourdomain.com
```

### Test from Flutter App
```dart
// Add to main.dart for testing
void testHTTPSConnection() async {
  final dio = Dio();
  try {
    final response = await dio.get('https://yourdomain.com/health');
    print('✅ HTTPS connection successful: ${response.statusCode}');
  } catch (e) {
    print('❌ HTTPS connection failed: $e');
  }
}
```

## Troubleshooting

### Error: "EACCES: permission denied"
Ports 80 and 443 require root privileges:
```bash
sudo npm start
```

### Error: "Certificate not found"
Verify certificate paths:
```bash
ls -la /etc/letsencrypt/live/yourdomain.com/
```

### Error: "Certificate has expired"
Renew certificates:
```bash
sudo certbot renew
sudo systemctl restart your-backend-service
```

### Browser shows "Not Secure" warning
- Development: Expected with self-signed certificates (trust manually)
- Production: Check certificate installation and domain configuration

### Flutter app can't connect to HTTPS
1. Verify API endpoint URL (https://)
2. Check certificate fingerprint matches
3. Test with certificate pinning temporarily disabled
4. Verify network connectivity

## Security Best Practices

1. **Never commit certificates to Git:**
   - Add `backend/certs/` to `.gitignore`
   - Store production certificates securely

2. **Use strong key sizes:**
   - Minimum 2048-bit RSA (4096-bit recommended)

3. **Keep certificates updated:**
   - Monitor expiration dates
   - Setup automatic renewal

4. **Restrict certificate file permissions:**
```bash
sudo chmod 600 /etc/letsencrypt/live/yourdomain.com/privkey.pem
sudo chown root:root /etc/letsencrypt/live/yourdomain.com/privkey.pem
```

5. **Use HTTP Strict Transport Security (HSTS):**
   - Already configured via helmet middleware

6. **Monitor certificate status:**
```bash
sudo certbot certificates
```

## Production Deployment Checklist

- [ ] Domain name configured and DNS pointing to server
- [ ] Certbot installed
- [ ] Let's Encrypt certificate obtained
- [ ] Certificate auto-renewal configured
- [ ] Firewall rules allow ports 80/443
- [ ] `.env` file updated with production settings
- [ ] Backend tested with HTTPS
- [ ] Frontend API endpoint updated to HTTPS
- [ ] Certificate fingerprint configured in Flutter app
- [ ] HTTP to HTTPS redirect working
- [ ] Certificate expiration monitoring setup

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot User Guide](https://eff-certbot.readthedocs.io/)
- [SSL Server Test](https://www.ssllabs.com/ssltest/)
- [Certificate Transparency Log](https://crt.sh/)

# 🔐 Android HTTPS Setup Guide

## Overview
This guide helps you set up HTTPS for your Crypto Wallet Android app with secure API communication.

---

## 📱 Part 1: Android App Configuration (Already Done ✅)

### What's configured:
1. **Network Security Config** - `android/app/src/main/res/xml/network_security_config.xml`
   - HTTPS enforced for production
   - Localhost allowed for development
   - Certificate pinning ready

2. **Environment Config** - `lib/core/config/environment.dart`
   - Development: `http://10.0.2.2:3000` (Android emulator)
   - Production: `https://api.yourdomain.com`

3. **API Config** - `lib/core/config/api_config.dart`
   - Auto-selects URL based on build mode
   - Certificate pinning support

---

## 🔑 Part 2: Generate Release Keystore

Before building a release APK, you need a signing key.

### Step 1: Generate Keystore
```powershell
# Navigate to frontend directory
cd c:\Users\RICO\ricoamos\crypto-wallet-app\frontend

# Create keystore directory
mkdir android\keystore -Force

# Generate keystore (replace with your details)
keytool -genkey -v -keystore android/keystore/release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias crypto_wallet_key
```

You'll be prompted for:
- Keystore password (save this!)
- Your name, organization, city, country
- Key password (can be same as keystore password)

### Step 2: Create key.properties
```powershell
# Copy template
Copy-Item android/key.properties.example android/key.properties

# Edit with your passwords
notepad android/key.properties
```

Update the file with your actual passwords:
```properties
storeFile=../keystore/release-keystore.jks
storePassword=YOUR_ACTUAL_PASSWORD
keyAlias=crypto_wallet_key
keyPassword=YOUR_ACTUAL_PASSWORD
```

⚠️ **IMPORTANT**: 
- Never commit `key.properties` to git!
- Back up your keystore file securely!
- Losing the keystore = can't update your app on Play Store!

---

## 🌐 Part 3: Backend HTTPS Setup

### Option A: Self-Signed Certificate (Development/Testing)

```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\backend

# Create certs directory
mkdir src/certs -Force

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout src/certs/key.pem -out src/certs/cert.pem
```

Set environment variables:
```powershell
$env:ENABLE_HTTPS = "true"
$env:NODE_ENV = "development"
```

### Option B: Let's Encrypt (Production)

On your Linux production server:
```bash
# Install Certbot
sudo apt install certbot

# Get certificate
sudo certbot certonly --standalone -d api.yourdomain.com

# Certificate will be at:
# /etc/letsencrypt/live/api.yourdomain.com/
```

Set production environment:
```bash
export ENABLE_HTTPS=true
export NODE_ENV=production
export DOMAIN=api.yourdomain.com
```

---

## 📦 Part 4: Build Your APK

### Option 1: Using Build Script
```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\frontend
.\build-android.ps1
```

### Option 2: Manual Build

```powershell
cd c:\Users\RICO\ricoamos\crypto-wallet-app\frontend

# Clean
flutter clean

# Get dependencies
flutter pub get

# Build Debug APK (for testing)
flutter build apk --debug

# Build Release APK (for distribution)
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

Output locations:
- Debug APK: `build/app/outputs/flutter-apk/app-debug.apk`
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`
- App Bundle: `build/app/outputs/bundle/release/app-release.aab`

---

## 🔧 Part 5: Update Your Production Domain

Before deploying, update these files with your actual domain:

### 1. Environment Config
Edit `lib/core/config/environment.dart`:
```dart
case Environment.production:
  return 'https://api.YOUR-ACTUAL-DOMAIN.com';
```

### 2. API Config
Edit `lib/core/config/api_config.dart`:
```dart
static const String prodBaseUrl = 'https://api.YOUR-ACTUAL-DOMAIN.com';
```

### 3. Network Security Config
Edit `android/app/src/main/res/xml/network_security_config.xml`:
```xml
<domain includeSubdomains="true">api.YOUR-ACTUAL-DOMAIN.com</domain>
```

---

## 📋 Part 6: Certificate Pinning (Optional but Recommended)

Certificate pinning prevents man-in-the-middle attacks.

### Get Certificate Pin
```bash
# Get your server's certificate pin
openssl s_client -connect api.yourdomain.com:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
```

### Add to Network Security Config
```xml
<domain-config cleartextTrafficPermitted="false">
    <domain includeSubdomains="true">api.yourdomain.com</domain>
    <pin-set expiration="2026-12-31">
        <pin digest="SHA-256">YOUR_PIN_HERE=</pin>
    </pin-set>
</domain-config>
```

---

## ✅ Checklist

- [ ] Generated keystore file
- [ ] Created key.properties with passwords
- [ ] Set up HTTPS on backend server
- [ ] Updated production domain in configs
- [ ] Built release APK
- [ ] Tested APK on real device
- [ ] (Optional) Added certificate pinning

---

## 🚨 Security Reminders

1. **Never commit secrets** - Add to `.gitignore`:
   ```
   android/key.properties
   android/keystore/
   *.jks
   *.keystore
   ```

2. **Backup your keystore** - Store copies in:
   - Encrypted cloud storage
   - Secure USB drive
   - Password manager

3. **Use strong passwords** - At least 16 characters with mixed case, numbers, symbols

4. **Enable Play App Signing** - Let Google manage your upload key for Play Store

---

## 📱 Quick Test

After building, install on your device:
```powershell
# Install debug APK
adb install build/app/outputs/flutter-apk/app-debug.apk

# Or install release APK
adb install build/app/outputs/flutter-apk/app-release.apk
```

Good luck with your release! 🚀

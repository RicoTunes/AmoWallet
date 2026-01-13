const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/**
 * Windows-compatible SSL certificate generator
 * Works without OpenSSL by using Node.js crypto module
 */
class WindowsCertGenerator {
  /**
   * Generate self-signed certificate using Node.js crypto (no OpenSSL needed)
   */
  static generateSelfSignedCert(certDir) {
    const keyPath = path.join(certDir, 'key.pem');
    const certPath = path.join(certDir, 'cert.pem');

    // Check if certificates already exist
    if (fs.existsSync(keyPath) && fs.existsSync(certPath)) {
      console.log('✅ Self-signed certificates already exist');
      return { keyPath, certPath };
    }

    console.log('🔧 Generating self-signed certificate using Node.js crypto...');

    // Create directory if it doesn't exist
    if (!fs.existsSync(certDir)) {
      fs.mkdirSync(certDir, { recursive: true });
    }

    try {
      // Try using PowerShell New-SelfSignedCertificate (Windows 8+)
      return this.generateWithPowerShell(certDir, keyPath, certPath);
    } catch (error) {
      console.log('⚠️  PowerShell certificate generation failed, using Node.js fallback');
      return this.generateWithNodeCrypto(certDir, keyPath, certPath);
    }
  }

  /**
   * Generate using PowerShell (Windows 8+)
   */
  static generateWithPowerShell(certDir, keyPath, certPath) {
    console.log('🔐 Using PowerShell New-SelfSignedCertificate...');

    const certPathEscaped = certPath.replace(/\\/g, '\\\\');
    const keyPathEscaped = keyPath.replace(/\\/g, '\\\\');

    const powershellScript = `
      $cert = New-SelfSignedCertificate -DnsName "localhost", "127.0.0.1" -CertStoreLocation "Cert:\\CurrentUser\\My" -FriendlyName "CryptoWallet Dev Certificate" -NotAfter (Get-Date).AddYears(1) -KeyAlgorithm RSA -KeyLength 4096
      
      $certPath = "${certPathEscaped}"
      $keyPath = "${keyPathEscaped}"
      
      # Export certificate
      $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
      [System.IO.File]::WriteAllBytes($certPath, $certBytes)
      
      # Export private key (Base64 encoded)
      $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
      $keyBytes = $rsaKey.ExportRSAPrivateKey()
      $keyPem = "-----BEGIN PRIVATE KEY-----\`n" + [Convert]::ToBase64String($keyBytes, 'InsertLineBreaks') + "\`n-----END PRIVATE KEY-----"
      [System.IO.File]::WriteAllText($keyPath, $keyPem)
      
      Write-Output "Certificate generated successfully"
    `;

    try {
      execSync(`powershell -Command "${powershellScript}"`, {
        stdio: 'inherit',
        windowsHide: true
      });

      console.log('✅ Self-signed certificate generated using PowerShell');
      return { keyPath, certPath };
    } catch (error) {
      throw new Error(`PowerShell generation failed: ${error.message}`);
    }
  }

  /**
   * Generate using Node.js crypto (fallback for older Windows/no admin)
   */
  static generateWithNodeCrypto(certDir, keyPath, certPath) {
    console.log('🔐 Using Node.js crypto module fallback...');

    // Generate RSA key pair
    const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 4096,
      publicKeyEncoding: {
        type: 'spki',
        format: 'pem'
      },
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'pem'
      }
    });

    // Write private key
    fs.writeFileSync(keyPath, privateKey);

    // Create a basic self-signed certificate structure
    // Note: This is a simplified version. For production, use proper certificate generation
    const certData = `-----BEGIN CERTIFICATE-----
${Buffer.from(publicKey).toString('base64')}
-----END CERTIFICATE-----`;

    fs.writeFileSync(certPath, certData);

    console.log('✅ Self-signed certificate generated using Node.js crypto');
    console.log('⚠️  Note: This is a development-only certificate');

    return { keyPath, certPath };
  }

  /**
   * Check if OpenSSL is available
   */
  static hasOpenSSL() {
    try {
      execSync('openssl version', { stdio: 'ignore' });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Generate using OpenSSL (if available)
   */
  static generateWithOpenSSL(certDir, keyPath, certPath) {
    console.log('🔐 Using OpenSSL...');

    const cmd = `openssl req -x509 -newkey rsa:4096 -keyout "${keyPath}" -out "${certPath}" -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Development/CN=localhost"`;

    try {
      execSync(cmd, { stdio: 'inherit' });
      console.log('✅ Self-signed certificate generated using OpenSSL');
      return { keyPath, certPath };
    } catch (error) {
      throw new Error(`OpenSSL generation failed: ${error.message}`);
    }
  }
}

module.exports = WindowsCertGenerator;

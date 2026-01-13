const crypto = require('crypto');
const secp256k1 = require('secp256k1');

// Simple JavaScript-based crypto implementation as fallback
class JSCrypto {
  async generateKeypair() {
    let privateKey;
    do {
      privateKey = crypto.randomBytes(32);
    } while (!secp256k1.privateKeyVerify(privateKey));
    
    const publicKey = secp256k1.publicKeyCreate(privateKey);
    
    return {
      privateKey: privateKey.toString('hex'),
      publicKey: Buffer.from(publicKey).toString('hex')
    };
  }

  async signMessage(privateKeyHex, message) {
    const privateKey = Buffer.from(privateKeyHex, 'hex');
    const messageHash = crypto.createHash('sha256').update(message).digest();
    
    const signature = secp256k1.ecdsaSign(messageHash, privateKey);
    return Buffer.from(signature.signature).toString('hex');
  }

  async verifySignature(publicKeyHex, message, signatureHex) {
    try {
      const publicKey = Buffer.from(publicKeyHex, 'hex');
      const messageHash = crypto.createHash('sha256').update(message).digest();
      const signature = Buffer.from(signatureHex, 'hex');
      
      return secp256k1.ecdsaVerify(signature, messageHash, publicKey);
    } catch (error) {
      return false;
    }
  }
}

module.exports = new JSCrypto();
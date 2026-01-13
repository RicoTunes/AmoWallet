# Rust Integration Guide

The crypto wallet app now includes Rust modules for high-performance cryptographic operations. This integration provides:

- Secure key pair generation using secp256k1
- Fast message signing and signature verification
- Native performance through FFI (Foreign Function Interface)

## Prerequisites

- Rust (install from https://rustup.rs)
- Node.js and npm (install from https://nodejs.org)
- Build tools for your platform (for Windows: Visual Studio Build Tools)

## Building the Rust Library

```bash
# Navigate to the Rust project
cd backend/rust

# Build the release version
cargo build --release
```

## Node.js Integration

The Rust functions are exposed through the `rust-crypto.js` module using `ffi-napi`. To use them:

```javascript
const RustCrypto = require('./lib/rust-crypto');

// Generate a new keypair
const keypair = RustCrypto.generateKeypair();
console.log('Private Key:', keypair.privateKey);
console.log('Public Key:', keypair.publicKey);

// Sign a message
const signature = RustCrypto.signMessage(keypair.privateKey, "Hello, World!");
console.log('Signature:', signature);

// Verify the signature
const isValid = RustCrypto.verifySignature(keypair.publicKey, "Hello, World!", signature);
console.log('Signature valid:', isValid);
```

## API Endpoints

### POST /api/wallet/generate
Generates a new secp256k1 keypair using Rust.

### POST /api/wallet/sign
Signs a message using a private key.

Request body:
```json
{
  "privateKey": "hex_encoded_private_key",
  "message": "message_to_sign"
}
```

### POST /api/wallet/verify
Verifies a signature using a public key.

Request body:
```json
{
  "publicKey": "hex_encoded_public_key",
  "message": "original_message",
  "signature": "hex_encoded_signature"
}
```
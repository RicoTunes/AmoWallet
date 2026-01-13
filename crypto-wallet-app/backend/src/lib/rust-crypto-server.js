const { spawn } = require('child_process');
const path = require('path');
const axios = require('axios');

/**
 * Rust Crypto Server Manager
 * Starts and manages the Rust-based crypto security server
 */
class RustCryptoServer {
  constructor() {
    this.process = null;
    this.port = process.env.RUST_HTTPS_PORT || '8443';
    this.url = `http://127.0.0.1:${this.port}`;
    this.binaryPath = path.join(__dirname, '../rust/target/release/crypto_wallet_cli.exe');
  }

  /**
   * Start the Rust server process
   */
  async start() {
    return new Promise((resolve, reject) => {
      console.log('🦀 Starting Rust Crypto Security Server...');
      
      // Start Rust server as a subprocess
      this.process = spawn(this.binaryPath, ['server'], {
        env: { ...process.env, RUST_HTTPS_PORT: this.port },
        stdio: 'inherit'
      });

      this.process.on('error', (err) => {
        console.error('❌ Failed to start Rust server:', err.message);
        reject(err);
      });

      this.process.on('exit', (code) => {
        if (code !== 0) {
          console.log(`⚠️  Rust server exited with code ${code}`);
        }
      });

      // Wait for server to be ready
      this.waitForReady()
        .then(() => {
          console.log('✅ Rust Crypto Server is ready');
          resolve();
        })
        .catch(reject);
    });
  }

  /**
   * Wait for Rust server to be ready
   */
  async waitForReady(maxAttempts = 30) {
    for (let i = 0; i < maxAttempts; i++) {
      try {
        const response = await axios.get(`${this.url}/health`, { timeout: 1000 });
        if (response.data && response.data.success) {
          return true;
        }
      } catch (error) {
        // Server not ready yet, wait and retry
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }
    throw new Error('Rust server failed to start within timeout period');
  }

  /**
   * Stop the Rust server
   */
  stop() {
    if (this.process) {
      console.log('🛑 Stopping Rust Crypto Server...');
      this.process.kill('SIGTERM');
      this.process = null;
    }
  }

  /**
   * Forward crypto operation to Rust server
   */
  async executeCryptoOperation(operation, params, endpoint = '/api/crypto') {
    try {
      const response = await axios.post(`${this.url}${endpoint}`, {
        operation,
        params
      }, {
        timeout: 5000,
        headers: { 'Content-Type': 'application/json' }
      });

      if (response.data && response.data.success) {
        return response.data;
      } else {
        throw new Error(response.data.error || 'Crypto operation failed');
      }
    } catch (error) {
      if (error.response) {
        throw new Error(`Rust server error: ${error.response.data.error || error.message}`);
      } else if (error.request) {
        throw new Error('Rust server not responding');
      } else {
        throw error;
      }
    }
  }

  /**
   * Generate keypair using Rust
   */
  async generateKeypair() {
    return this.executeCryptoOperation('generate_keypair', {});
  }

  /**
   * Sign message using Rust
   */
  async signMessage(privateKey, message) {
    return this.executeCryptoOperation('sign_message', { privateKey, message });
  }

  /**
   * Verify signature using Rust
   */
  async verifySignature(publicKey, message, signature) {
    return this.executeCryptoOperation('verify_signature', { publicKey, message, signature });
  }
}

// Singleton instance
let instance = null;

module.exports = {
  /**
   * Get or create RustCryptoServer instance
   */
  getInstance: () => {
    if (!instance) {
      instance = new RustCryptoServer();
    }
    return instance;
  },

  /**
   * Initialize and start Rust server
   */
  initialize: async () => {
    const server = module.exports.getInstance();
    await server.start();
    return server;
  }
};

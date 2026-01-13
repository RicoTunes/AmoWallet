const RustWorkerPool = require('./rustWorkerPool');

let pool = null;
function getPool() {
  if (!pool) pool = new RustWorkerPool();
  return pool;
}

module.exports = {
  async generateKeypair() {
    const p = getPool();
    return await p.generateKeypair();
  },

  async signMessage(privateKeyHex, message) {
    const p = getPool();
    return await p.signMessage(privateKeyHex, message);
  },

  async verifySignature(publicKeyHex, message, signatureHex) {
    const p = getPool();
    const res = await p.verifySignature(publicKeyHex, message, signatureHex);
    return res === true || res === 'true';
  }
};
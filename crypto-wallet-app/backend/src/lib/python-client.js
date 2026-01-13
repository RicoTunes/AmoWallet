const fetch = require('node-fetch');

const BASE = process.env.PYTHON_SERVICE_URL || 'http://localhost:8000';

module.exports = {
  async generateKeypair() {
    const res = await fetch(`${BASE}/generate`, { method: 'POST' });
    if (!res.ok) throw new Error(`Python service error: ${res.status}`);
    return await res.json();
  },

  async signMessage(privateHex, message) {
    const res = await fetch(`${BASE}/sign`, { method: 'POST', body: JSON.stringify({ privateKey: privateHex, message }), headers: { 'Content-Type': 'application/json' } });
    if (!res.ok) throw new Error(`Python service error: ${res.status}`);
    const body = await res.json();
    return body.signature;
  },

  async verifySignature(publicHex, message, signatureHex) {
    const res = await fetch(`${BASE}/verify`, { method: 'POST', body: JSON.stringify({ publicKey: publicHex, message, signature: signatureHex }), headers: { 'Content-Type': 'application/json' } });
    if (!res.ok) throw new Error(`Python service error: ${res.status}`);
    const body = await res.json();
    return !!body.valid;
  }
};

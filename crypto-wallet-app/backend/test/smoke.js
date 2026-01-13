const fetch = require('node-fetch');

const BASE = 'http://localhost:3000';

async function run() {
  console.log('Running smoke test...');

  const gen = await fetch(`${BASE}/api/wallet/generate`, { method: 'POST' });
  const genJson = await gen.json();
  if (!genJson || !genJson.wallet) throw new Error('Generate failed');
  const { privateKey, publicKey } = genJson.wallet;
  console.log('Generated keys');

  const signRes = await fetch(`${BASE}/api/wallet/sign`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ privateKey, message: 'test' })
  });
  const signJson = await signRes.json();
  if (!signJson || !signJson.signature) throw new Error('Sign failed');
  const signature = signJson.signature;
  console.log('Signed message');

  const verRes = await fetch(`${BASE}/api/wallet/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ publicKey, message: 'test', signature })
  });
  const verJson = await verRes.json();
  if (!verJson || verJson.isValid !== true) throw new Error('Verify failed');
  console.log('Verification successful');

  console.log('Smoke test passed');
}

run().catch(err => {
  console.error('Smoke test failed:', err);
  process.exit(1);
});

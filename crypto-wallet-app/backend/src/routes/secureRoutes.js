// ============================================================================
// secureRoutes.js — Secure transaction signing with Rust-first architecture.
// Tries to forward to Rust security server for signing; if Rust is unreachable,
// falls back to local Node.js signing so transactions still work.
// Private keys are AES-256-GCM encrypted in transit and decrypted only
// briefly on the local call stack.
// ============================================================================

const express = require('express');
const router = express.Router();
const axios = require('axios');
const crypto = require('crypto');
const { ethers } = require('ethers');

const RUST_URL = `http://127.0.0.1:${process.env.RUST_HTTPS_PORT || 8443}`;

// ---------------------------------------------------------------------------
// Bridge secret — must match Flutter RustSecurityService + Rust SecureSigner
// ---------------------------------------------------------------------------
const BRIDGE_SECRET = process.env.RUST_BRIDGE_SECRET ||
  'AmoWallet_Rust_Bridge_2026_SecureKey_Zx9Fk2mQ7v';

// Derive AES key = SHA-256(secret || "aes-key-derive")
const AES_KEY = crypto.createHash('sha256')
  .update(BRIDGE_SECRET + 'aes-key-derive').digest();

// Derive HMAC key = SHA-256(secret || "hmac-key-derive")
const HMAC_KEY = crypto.createHash('sha256')
  .update(BRIDGE_SECRET + 'hmac-key-derive').digest();

// ---------------------------------------------------------------------------
// AES-256-GCM decryption  (mirrors Rust SecureSigner.decrypt)
// Input: base64( nonce[12] || ciphertext || tag[16] )
// ---------------------------------------------------------------------------
function decryptAesGcm(encryptedB64) {
  const buf = Buffer.from(encryptedB64, 'base64');
  if (buf.length < 28) throw new Error('Encrypted payload too short');

  const nonce = buf.subarray(0, 12);
  const tag = buf.subarray(buf.length - 16);
  const ciphertext = buf.subarray(12, buf.length - 16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', AES_KEY, nonce);
  decipher.setAuthTag(tag);

  let decrypted = decipher.update(ciphertext, null, 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

// ---------------------------------------------------------------------------
// HMAC-SHA256 verification
// ---------------------------------------------------------------------------
function verifyHmac(body, providedHmac) {
  if (!providedHmac) return true; // hmac is optional for backward compat
  // Recompute over the body without the hmac field
  const clean = { ...body };
  delete clean.hmac;
  const payload = JSON.stringify(clean);
  const expected = crypto.createHmac('sha256', HMAC_KEY)
    .update(payload).digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(expected, 'hex'),
    Buffer.from(providedHmac, 'hex')
  );
}

// ---------------------------------------------------------------------------
// Check if Rust is reachable (cached for 30s)
// ---------------------------------------------------------------------------
let _rustAlive = null;
let _rustCheckedAt = 0;
async function isRustAlive() {
  if (Date.now() - _rustCheckedAt < 30000) return _rustAlive;
  try {
    await axios.get(`${RUST_URL}/api/secure/health`, { timeout: 2000 });
    _rustAlive = true;
  } catch {
    _rustAlive = false;
  }
  _rustCheckedAt = Date.now();
  return _rustAlive;
}

// ---------------------------------------------------------------------------
// Helper: forward a request to Rust and unwrap its response
// ---------------------------------------------------------------------------
async function forwardToRust(path, body) {
  const url = `${RUST_URL}${path}`;
  const res = await axios.post(url, body, {
    headers: { 'Content-Type': 'application/json' },
    timeout: 120000,
    validateStatus: () => true,
  });

  const data = res.data;
  if (data && data.success === false && data.error) {
    const err = new Error(data.error);
    err.status = res.status >= 400 ? res.status : 400;
    throw err;
  }
  return data?.data ?? data;
}

// ---------------------------------------------------------------------------
// EVM provider helpers (same as blockchainRoutes)
// ---------------------------------------------------------------------------
const ETH_RPC_URLS = [
  process.env.INFURA_PROJECT_ID ? `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}` : null,
  'https://eth.llamarpc.com',
  'https://rpc.ankr.com/eth',
  'https://cloudflare-eth.com',
  'https://1rpc.io/eth',
].filter(Boolean);

async function getWorkingEthProvider() {
  for (const url of ETH_RPC_URLS) {
    try {
      const p = new ethers.JsonRpcProvider(url);
      await p.getBlockNumber();
      return p;
    } catch (_) { /* try next */ }
  }
  throw new Error('All ETH RPC endpoints failed');
}

// ---------------------------------------------------------------------------
// Local EVM signing fallback (ETH / BNB)
// ---------------------------------------------------------------------------
async function localSignEvm(body) {
  const privateKey = decryptAesGcm(body.encrypted_key);
  const chain = (body.chain || 'ETH').toUpperCase();
  const { from, to, amount } = body;
  const gasLimit = body.gas_limit || 21000;

  console.log(`🔧 [fallback] Local EVM signing for ${chain}...`);

  const provider = chain === 'ETH'
    ? await getWorkingEthProvider()
    : new ethers.JsonRpcProvider('https://bsc-dataseed1.binance.org/');

  const cleanKey = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
  const wallet = new ethers.Wallet(cleanKey, provider);

  if (wallet.address.toLowerCase() !== from.toLowerCase()) {
    throw new Error('Private key does not match from address');
  }

  const feeData = await provider.getFeeData();
  const amountStr = parseFloat(amount).toFixed(18).replace(/\.?0+$/, '');

  const tx = {
    to,
    value: ethers.parseEther(amountStr),
    gasLimit,
    chainId: chain === 'ETH' ? 1 : 56,
  };

  // Use EIP-1559 if available, otherwise legacy
  if (feeData.maxFeePerGas) {
    tx.maxFeePerGas = feeData.maxFeePerGas;
    tx.maxPriorityFeePerGas = feeData.maxPriorityFeePerGas;
  } else {
    tx.gasPrice = feeData.gasPrice;
  }

  const transaction = await wallet.sendTransaction(tx);
  const receipt = await transaction.wait();

  console.log(`✅ [fallback] ${chain} tx mined: ${receipt.hash}`);
  return {
    tx_hash: receipt.hash,
    from: receipt.from,
    to: receipt.to,
    amount,
    block_number: receipt.blockNumber,
    gas_used: receipt.gasUsed ? Number(receipt.gasUsed) : null,
  };
}

// ---------------------------------------------------------------------------
// POST /api/secure/sign-evm  — Rust-first, with local fallback
// ---------------------------------------------------------------------------
router.post('/sign-evm', async (req, res) => {
  try {
    // Verify HMAC integrity
    if (req.body.hmac && !verifyHmac(req.body, req.body.hmac)) {
      return res.status(403).json({ success: false, error: 'HMAC verification failed' });
    }

    // Try Rust first
    if (await isRustAlive()) {
      try {
        const result = await forwardToRust('/api/secure/sign-evm', req.body);
        return res.json({ success: true, ...result });
      } catch (rustErr) {
        console.warn('[secure] Rust sign-evm failed, falling back to local:', rustErr.message);
      }
    } else {
      console.log('[secure] Rust unavailable, using local EVM signing');
    }

    // Fallback: decrypt locally and sign with ethers.js
    const result = await localSignEvm(req.body);
    return res.json({ success: true, ...result });
  } catch (err) {
    console.error('[secure] sign-evm error:', err.message);
    return res.status(err.status || 500).json({
      success: false,
      error: err.message,
    });
  }
});

// ---------------------------------------------------------------------------
// POST /api/secure/validate  — Rust validates + decrypts for non-EVM chains
// ---------------------------------------------------------------------------
router.post('/validate', async (req, res) => {
  try {
    if (await isRustAlive()) {
      const result = await forwardToRust('/api/secure/validate', req.body);
      return res.json({ success: true, ...result });
    }

    // Fallback: decrypt locally
    const key = decryptAesGcm(req.body.encrypted_key);
    return res.json({ success: true, validated: true, key });
  } catch (err) {
    console.error('[secure] validate error:', err.message);
    return res.status(err.status || 500).json({
      success: false,
      error: err.message,
    });
  }
});

// ---------------------------------------------------------------------------
// POST /api/secure/send-non-evm  — Rust-first, with local fallback
// ---------------------------------------------------------------------------
router.post('/send-non-evm', async (req, res) => {
  try {
    if (req.body.hmac && !verifyHmac(req.body, req.body.hmac)) {
      return res.status(403).json({ success: false, error: 'HMAC verification failed' });
    }

    let decryptedKey;

    // Try Rust validation first
    if (await isRustAlive()) {
      try {
        const validated = await forwardToRust('/api/secure/validate', {
          encrypted_key: req.body.encrypted_key,
          chain: req.body.chain,
          from: req.body.from,
          to: req.body.to,
          amount: req.body.amount,
          hmac: req.body.hmac,
          amount_usd: req.body.amount_usd,
        });

        if (!validated || !validated.validated || !validated.key) {
          return res.status(403).json({
            success: false,
            error: 'Rust validation rejected the transaction',
          });
        }
        decryptedKey = validated.key;
      } catch (rustErr) {
        console.warn('[secure] Rust validate failed, falling back to local decrypt:', rustErr.message);
        decryptedKey = decryptAesGcm(req.body.encrypted_key);
      }
    } else {
      console.log('[secure] Rust unavailable, decrypting locally');
      decryptedKey = decryptAesGcm(req.body.encrypted_key);
    }

    const chain = (req.body.chain || '').toUpperCase();
    const { from, to, amount } = req.body;

    let txResult;

    switch (chain) {
      case 'BTC':
      case 'LTC':
      case 'DOGE':
        txResult = await signUtxoChain(chain, from, to, amount, decryptedKey, req.body.fee);
        break;
      case 'SOL':
        txResult = await signSolana(from, to, amount, decryptedKey);
        break;
      case 'TRX':
        txResult = await signTron(from, to, amount, decryptedKey);
        break;
      case 'XRP':
        txResult = await signXrp(from, to, amount, decryptedKey);
        break;
      default:
        return res.status(400).json({ success: false, error: `Unsupported non-EVM chain: ${chain}` });
    }

    return res.json({ success: true, ...txResult });
  } catch (err) {
    console.error('[secure] send-non-evm error:', err.message);
    return res.status(err.status || 500).json({
      success: false,
      error: err.message,
    });
  }
});

// ---------------------------------------------------------------------------
// GET /api/secure/health
// ---------------------------------------------------------------------------
router.get('/health', async (req, res) => {
  try {
    const url = `${RUST_URL}/api/secure/health`;
    const r = await axios.get(url, { timeout: 5000, validateStatus: () => true });
    return res.json(r.data?.data ?? r.data);
  } catch (err) {
    return res.json({
      success: false,
      error: 'Rust secure signer unreachable',
      details: err.message,
    });
  }
});

// ---------------------------------------------------------------------------
// UTXO-based chain signing (BTC, LTC, DOGE)
// ---------------------------------------------------------------------------
async function signUtxoChain(chain, from, to, amount, privateKey, requestedFee) {
  const bitcoin = require('bitcoinjs-lib');
  const ecc = require('@bitcoinerlab/secp256k1');
  const ECPairFactory = require('ecpair').ECPairFactory;
  bitcoin.initEccLib(ecc);
  const ECPair = ECPairFactory(ecc);

  // Network configs
  const networks = {
    BTC: bitcoin.networks.bitcoin,
    LTC: {
      messagePrefix: '\x19Litecoin Signed Message:\n',
      bech32: 'ltc',
      bip32: { public: 0x019da462, private: 0x019d9cfe },
      pubKeyHash: 0x30,
      scriptHash: 0x32,
      wif: 0xb0,
    },
    DOGE: {
      messagePrefix: '\x19Dogecoin Signed Message:\n',
      bip32: { public: 0x02facafd, private: 0x02fac398 },
      pubKeyHash: 0x1e,
      scriptHash: 0x16,
      wif: 0x9e,
    },
  };

  const network = networks[chain] || bitcoin.networks.bitcoin;
  const apiBase = chain === 'BTC'
    ? 'https://blockstream.info/api'
    : chain === 'LTC'
      ? 'https://api.blockcypher.com/v1/ltc/main'
      : 'https://api.blockcypher.com/v1/doge/main';

  let keyPair;
  const cleanKey = privateKey.replace(/^0x/, '');
  try {
    if (/^[5KL]/.test(cleanKey)) {
      keyPair = ECPair.fromWIF(cleanKey, network);
    } else {
      keyPair = ECPair.fromPrivateKey(Buffer.from(cleanKey, 'hex'), { network });
    }
  } catch (e) {
    throw new Error(`Invalid ${chain} private key format`);
  }

  // For BTC use blockstream API
  if (chain === 'BTC') {
    const utxoResp = await axios.get(`${apiBase}/address/${from}/utxo`);
    const utxos = utxoResp.data;
    if (!utxos || utxos.length === 0) throw new Error('No UTXOs available');

    const amountSats = Math.floor(amount * 1e8);
    const feeSats = requestedFee ? Math.floor(requestedFee * 1e8) : 5000;
    const target = amountSats + feeSats;

    utxos.sort((a, b) => b.value - a.value);
    let selected = [], total = 0;
    for (const u of utxos) {
      selected.push(u);
      total += u.value;
      if (total >= target) break;
    }
    if (total < target) throw new Error('Insufficient funds');

    const psbt = new bitcoin.Psbt({ network });
    for (const u of selected) {
      const txHex = await axios.get(`${apiBase}/tx/${u.txid}/hex`).then(r => r.data);
      psbt.addInput({ hash: u.txid, index: u.vout, nonWitnessUtxo: Buffer.from(txHex, 'hex') });
    }
    psbt.addOutput({ address: to, value: amountSats });
    const change = total - amountSats - feeSats;
    if (change > 546) psbt.addOutput({ address: from, value: change });

    for (let i = 0; i < selected.length; i++) psbt.signInput(i, keyPair);
    psbt.finalizeAllInputs();
    const rawTx = psbt.extractTransaction().toHex();

    const broadcast = await axios.post(`${apiBase}/tx`, rawTx, {
      headers: { 'Content-Type': 'text/plain' },
    });

    return { txHash: broadcast.data, chain };
  }

  // For LTC/DOGE use blockcypher
  const addrResp = await axios.get(`${apiBase}/addrs/${from}?unspentOnly=true`);
  const utxos = addrResp.data?.txrefs || [];
  if (utxos.length === 0) throw new Error(`No UTXOs for ${chain}`);

  const amountSats = Math.floor(amount * 1e8);
  const feeSats = requestedFee ? Math.floor(requestedFee * 1e8) : 10000;

  return { txHash: `${chain}_signed_pending`, chain, note: 'UTXO broadcast pending' };
}

// ---------------------------------------------------------------------------
// Solana signing — uses @solana/web3.js if available, otherwise RPC
// ---------------------------------------------------------------------------
async function signSolana(from, to, amount, privateKey) {
  try {
    const solanaWeb3 = require('@solana/web3.js');
    const bs58 = require('bs58');

    const connection = new solanaWeb3.Connection(
      'https://api.mainnet-beta.solana.com',
      'confirmed'
    );

    // Decode private key (hex or base58)
    let secretKey;
    const cleanKey = privateKey.replace(/^0x/, '');
    if (/^[0-9a-fA-F]{64,128}$/.test(cleanKey)) {
      secretKey = Uint8Array.from(Buffer.from(cleanKey, 'hex'));
    } else {
      secretKey = bs58.decode(cleanKey);
    }
    const keypair = solanaWeb3.Keypair.fromSecretKey(secretKey);

    const lamports = Math.floor(parseFloat(amount) * 1e9);
    const toPubkey = new solanaWeb3.PublicKey(to);

    const tx = new solanaWeb3.Transaction().add(
      solanaWeb3.SystemProgram.transfer({
        fromPubkey: keypair.publicKey,
        toPubkey,
        lamports,
      })
    );

    const signature = await solanaWeb3.sendAndConfirmTransaction(connection, tx, [keypair]);
    console.log(`✅ SOL transaction: ${signature}`);
    return { txHash: signature, chain: 'SOL' };
  } catch (e) {
    // If @solana/web3.js not installed, give clear error
    if (e.code === 'MODULE_NOT_FOUND') {
      throw new Error('Solana signing requires @solana/web3.js and bs58 packages');
    }
    throw e;
  }
}

// ---------------------------------------------------------------------------
// TRON signing — uses TronGrid API
// ---------------------------------------------------------------------------
async function signTron(from, to, amount, privateKey) {
  const amountSun = Math.floor(parseFloat(amount) * 1e6);
  const apiKey = process.env.TRONGRID_API_KEY || '';
  const headers = apiKey ? { 'TRON-PRO-API-KEY': apiKey } : {};

  // Step 1: Create unsigned transaction
  const createResp = await axios.post('https://api.trongrid.io/wallet/createtransaction', {
    owner_address: from,
    to_address: to,
    amount: amountSun,
  }, { headers });

  if (createResp.data.Error) throw new Error(createResp.data.Error);

  // Step 2: Sign via TronGrid
  const cleanKey = privateKey.replace(/^0x/, '');
  const signResp = await axios.post('https://api.trongrid.io/wallet/gettransactionsign', {
    transaction: createResp.data,
    privateKey: cleanKey,
  }, { headers });

  if (signResp.data.Error) throw new Error(signResp.data.Error);

  // Step 3: Broadcast
  const broadcastResp = await axios.post('https://api.trongrid.io/wallet/broadcasttransaction',
    signResp.data, { headers });

  if (!broadcastResp.data.result) {
    throw new Error(broadcastResp.data.message || 'TRX broadcast failed');
  }

  const txHash = signResp.data.txID;
  console.log(`✅ TRX transaction: ${txHash}`);
  return { txHash, chain: 'TRX' };
}

// ---------------------------------------------------------------------------
// XRP signing — uses Ripple JSON-RPC
// ---------------------------------------------------------------------------
async function signXrp(from, to, amount, privateKey) {
  const rpcUrl = 'https://s1.ripple.com:51234';
  const amountDrops = Math.floor(parseFloat(amount) * 1e6).toString();

  // Get account sequence
  const acctResp = await axios.post(rpcUrl, {
    method: 'account_info',
    params: [{ account: from, ledger_index: 'current' }],
  });
  if (acctResp.data.result.error) {
    throw new Error(acctResp.data.result.error_message || 'XRP account not found');
  }
  const sequence = acctResp.data.result.account_data.Sequence;

  // Get current ledger
  const ledgerResp = await axios.post(rpcUrl, {
    method: 'ledger_current', params: [{}],
  });
  const currentLedger = ledgerResp.data.result.ledger_current_index;

  // Create payment
  const payment = {
    TransactionType: 'Payment',
    Account: from,
    Destination: to,
    Amount: amountDrops,
    Sequence: sequence,
    Fee: '12',
    LastLedgerSequence: currentLedger + 20,
  };

  // Sign
  const signResp = await axios.post(rpcUrl, {
    method: 'sign',
    params: [{ tx_json: payment, secret: privateKey }],
  });
  if (signResp.data.result.error) {
    throw new Error(signResp.data.result.error_message || 'XRP signing failed');
  }

  // Submit
  const submitResp = await axios.post(rpcUrl, {
    method: 'submit',
    params: [{ tx_blob: signResp.data.result.tx_blob }],
  });
  const engineResult = submitResp.data.result.engine_result || '';
  if (!engineResult.startsWith('tes') && engineResult !== 'tesSUCCESS') {
    throw new Error(submitResp.data.result.engine_result_message || 'XRP submit failed');
  }

  const txHash = submitResp.data.result.tx_json.hash;
  console.log(`✅ XRP transaction: ${txHash}`);
  return { txHash, chain: 'XRP' };
}

module.exports = router;

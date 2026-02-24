const express = require('express');
const router = express.Router();
const axios = require('axios');
const { apiLimiter } = require('../middleware/rateLimiter');

/**
 * Multi-Signature Wallet Routes
 * All operations forwarded to the Rust crypto server for secure execution.
 * Rust handles: contract deployment, tx submission/confirmation/execution,
 * revocation, on-chain queries, and wallet state persistence.
 */

router.use(apiLimiter);

const RUST_URL = `http://127.0.0.1:${process.env.RUST_HTTPS_PORT || '8443'}`;
const TIMEOUT = 30000; // 30s — deploy can take a while

// ── Helper: forward to Rust ────────────────────────────────────────────────

async function rustGet(path) {
    const res = await axios.get(`${RUST_URL}${path}`, { timeout: TIMEOUT });
    // Rust wraps in { success, data, error } — unwrap the inner data for clients
    return res.data?.data ?? res.data;
}

async function rustPost(path, data) {
    const res = await axios.post(`${RUST_URL}${path}`, data, {
        timeout: TIMEOUT,
        headers: { 'Content-Type': 'application/json' },
    });
    // Rust wraps in { success, data, error } — unwrap the inner data for clients
    return res.data?.data ?? res.data;
}

function sendError(res, error) {
    const status = error.response?.status || 500;
    const msg = error.response?.data?.error || error.message || 'Internal error';
    console.error(`[multisig] ${msg}`);
    res.status(status).json({ success: false, error: msg });
}

// ── GET: Contract info ──────────────────────────────────────────────────────

router.get('/info', async (req, res) => {
    try {
        const data = await rustGet('/api/multisig/info');
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── GET: All stored wallets ─────────────────────────────────────────────────

router.get('/wallets', async (req, res) => {
    try {
        const data = await rustGet('/api/multisig/wallets');
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── GET: Find wallet for owner address ──────────────────────────────────────

router.get('/my-wallet/:ownerAddress', async (req, res) => {
    try {
        const { ownerAddress } = req.params;
        const data = await rustGet(`/api/multisig/my-wallet/${ownerAddress}`);
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// Backwards-compatible (no param → use query or return null)
router.get('/my-wallet', async (req, res) => {
    try {
        const owner = req.query.owner;
        if (!owner) {
            return res.json({ success: true, address: null });
        }
        const data = await rustGet(`/api/multisig/my-wallet/${owner}`);
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── GET: Wallet owners & info ───────────────────────────────────────────────

router.get('/owners/:contractAddress', async (req, res) => {
    try {
        const { contractAddress } = req.params;
        if (!contractAddress || !contractAddress.startsWith('0x')) {
            return res.status(400).json({ success: false, error: 'Invalid contract address' });
        }
        const data = await rustGet(`/api/multisig/owners/${contractAddress}`);
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── GET: Pending transactions ───────────────────────────────────────────────

router.get('/pending/:contractAddress', async (req, res) => {
    try {
        const { contractAddress } = req.params;
        if (!contractAddress) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress' });
        }
        const data = await rustGet(`/api/multisig/pending/${contractAddress}`);
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── GET: Transaction history ────────────────────────────────────────────────

router.get('/history/:contractAddress', async (req, res) => {
    try {
        const { contractAddress } = req.params;
        const data = await rustGet(`/api/multisig/history/${contractAddress}`);
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Deploy new multisig wallet ────────────────────────────────────────

router.post('/deploy', async (req, res) => {
    try {
        const { owners, required, requiredConfirmations, rpcUrl, privateKey } = req.body;

        if (!owners || !Array.isArray(owners) || owners.length < 2) {
            return res.status(400).json({ success: false, error: 'At least 2 owners required' });
        }

        const reqConf = required || requiredConfirmations || 2;
        if (reqConf < 1 || reqConf > owners.length) {
            return res.status(400).json({ success: false, error: 'Invalid required confirmations' });
        }

        const data = await rustPost('/api/multisig/deploy', {
            owners,
            required: reqConf,
            rpcUrl: rpcUrl || undefined,
            privateKey: privateKey || undefined,
        });
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Import existing wallet ────────────────────────────────────────────

router.post('/import', async (req, res) => {
    try {
        const { contractAddress, rpcUrl } = req.body;
        if (!contractAddress) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress' });
        }
        const data = await rustPost('/api/multisig/import', {
            contractAddress,
            rpcUrl: rpcUrl || undefined,
        });
        res.json(data);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Submit transaction ────────────────────────────────────────────────

router.post('/submit', async (req, res) => {
    try {
        const { contractAddress, to, value, data: txData, rpcUrl, privateKey } = req.body;

        if (!contractAddress || !to) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress or to' });
        }

        const result = await rustPost('/api/multisig/submit', {
            contractAddress,
            to,
            value: value || '0',
            data: txData || '0x',
            rpcUrl: rpcUrl || undefined,
            privateKey: privateKey || undefined,
        });
        res.json(result);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Confirm (approve) transaction ─────────────────────────────────────

router.post('/confirm', async (req, res) => {
    try {
        const { contractAddress, txIndex, rpcUrl, privateKey } = req.body;

        if (!contractAddress || txIndex === undefined) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress or txIndex' });
        }

        const result = await rustPost('/api/multisig/confirm', {
            contractAddress,
            txIndex,
            rpcUrl: rpcUrl || undefined,
            privateKey: privateKey || undefined,
        });
        res.json(result);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Execute confirmed transaction ─────────────────────────────────────

router.post('/execute', async (req, res) => {
    try {
        const { contractAddress, txIndex, rpcUrl, privateKey } = req.body;

        if (!contractAddress || txIndex === undefined) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress or txIndex' });
        }

        const result = await rustPost('/api/multisig/execute', {
            contractAddress,
            txIndex,
            rpcUrl: rpcUrl || undefined,
            privateKey: privateKey || undefined,
        });
        res.json(result);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Revoke confirmation ───────────────────────────────────────────────

router.post('/revoke', async (req, res) => {
    try {
        const { contractAddress, txIndex, rpcUrl, privateKey } = req.body;

        if (!contractAddress || txIndex === undefined) {
            return res.status(400).json({ success: false, error: 'Missing contractAddress or txIndex' });
        }

        const result = await rustPost('/api/multisig/revoke', {
            contractAddress,
            txIndex,
            rpcUrl: rpcUrl || undefined,
            privateKey: privateKey || undefined,
        });
        res.json(result);
    } catch (error) {
        sendError(res, error);
    }
});

// ── POST: Register wallet (manual) ─────────────────────────────────────────

router.post('/register', async (req, res) => {
    try {
        const { address, owners, required, rpcUrl } = req.body;
        if (!address) {
            return res.status(400).json({ success: false, error: 'Missing address' });
        }
        const result = await rustPost('/api/multisig/register', {
            address,
            owners: owners || [],
            required: required || 2,
            rpcUrl: rpcUrl || undefined,
        });
        res.json(result);
    } catch (error) {
        sendError(res, error);
    }
});

module.exports = router;

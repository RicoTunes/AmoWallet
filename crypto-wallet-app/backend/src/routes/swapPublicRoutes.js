/**
 * Public swap routes — no authentication required.
 * Mounted BEFORE the authenticated /api/swap block in app.js.
 * Handles: GET /providers, GET /rates, GET /coins
 *
 * These are read-only informational endpoints safe to expose publicly.
 */
const express = require('express');
const router = express.Router();
const { apiLimiter } = require('../middleware/rateLimiter');
const axios = require('axios');
require('dotenv').config();

const supportedCoins = [
  'BTC', 'ETH', 'BNB', 'USDT', 'USDC', 'DAI', 'LTC', 'DOGE', 'XRP', 'SOL',
  'USDT-ERC20', 'USDT-BEP20', 'USDT-TRC20',
  'USDC-ERC20', 'USDC-BEP20',
  'MATIC', 'TRX',
];

function getBaseCoin(coin) {
  return coin.includes('-') ? coin.split('-')[0] : coin;
}

function getCoinName(symbol) {
  const names = {
    BTC: 'Bitcoin', ETH: 'Ethereum', BNB: 'Binance Coin',
    USDT: 'Tether', USDC: 'USD Coin', DAI: 'Dai',
    LTC: 'Litecoin', DOGE: 'Dogecoin', XRP: 'Ripple',
    SOL: 'Solana', MATIC: 'Polygon', TRX: 'TRON',
  };
  return names[symbol] || symbol;
}

function determinePrimaryNetwork(coin) {
  switch (coin) {
    case 'BTC': return 'bitcoin';
    case 'ETH': return 'ethereum';
    case 'BNB': return 'bsc';
    case 'USDT': case 'USDC': case 'DAI': return 'multi-chain';
    case 'LTC': return 'litecoin';
    case 'DOGE': return 'dogecoin';
    case 'XRP': return 'ripple';
    case 'SOL': return 'solana';
    default: return 'unknown';
  }
}

function getMockPrices() {
  return {
    btc: { usd: 97000, usd_24h_change: 1.2 },
    eth: { usd: 2700,  usd_24h_change: -0.5 },
    bnb: { usd: 600,   usd_24h_change: 0.8 },
    usdt: { usd: 1.0,  usd_24h_change: 0.0 },
    usdc: { usd: 1.0,  usd_24h_change: 0.0 },
    dai:  { usd: 1.0,  usd_24h_change: 0.0 },
    ltc:  { usd: 90,   usd_24h_change: 0.5 },
    doge: { usd: 0.18, usd_24h_change: 2.0 },
    xrp:  { usd: 2.5,  usd_24h_change: 1.0 },
    sol:  { usd: 180,  usd_24h_change: 3.0 },
    matic: { usd: 0.4, usd_24h_change: -1.0 },
    trx:  { usd: 0.24, usd_24h_change: 0.5 },
  };
}

async function getRealTimePrices() {
  const coinGeckoIds = {
    BTC: 'bitcoin', ETH: 'ethereum', BNB: 'binancecoin',
    USDT: 'tether', USDC: 'usd-coin', DAI: 'dai',
    LTC: 'litecoin', DOGE: 'dogecoin', XRP: 'ripple',
    SOL: 'solana', MATIC: 'matic-network', TRX: 'tron',
  };
  try {
    const apiKey = process.env.COINGECKO_API_KEY
      ? `&x_cg_pro_api_key=${process.env.COINGECKO_API_KEY}` : '';
    const ids = Object.values(coinGeckoIds).join(',');
    const response = await axios.get(
      `https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd&include_24hr_change=true${apiKey}`,
      { timeout: 10000 },
    );
    const prices = {};
    Object.entries(coinGeckoIds).forEach(([symbol, geckoId]) => {
      if (response.data[geckoId]) {
        prices[symbol.toLowerCase()] = response.data[geckoId];
      }
    });
    return prices;
  } catch {
    return getMockPrices();
  }
}

// ── GET /api/swap/providers ──────────────────────────────────────────────────
router.get('/providers', apiLimiter, (req, res) => {
  res.json({
    success: true,
    providers: [
      {
        id: '1inch', name: '1inch', type: 'dex-aggregator',
        chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism'],
        features: ['best-price', 'split-routing', 'gas-optimization'],
        swapTypes: ['same-chain'],
      },
      {
        id: '0x', name: '0x Protocol', type: 'dex-aggregator',
        chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism'],
        features: ['professional-grade', 'limit-orders'],
        swapTypes: ['same-chain'],
      },
      {
        id: 'paraswap', name: 'Paraswap', type: 'dex-aggregator',
        chains: ['ethereum', 'bsc', 'polygon', 'arbitrum'],
        features: ['multi-path', 'gas-refund'],
        swapTypes: ['same-chain'],
      },
      {
        id: 'lifi', name: 'LI.FI', type: 'bridge-aggregator',
        chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism', 'avalanche'],
        features: ['cross-chain', 'bridge-aggregation'],
        swapTypes: ['same-chain', 'cross-chain'],
      },
      {
        id: 'thorchain', name: 'THORChain', type: 'native-swap',
        chains: ['bitcoin', 'ethereum', 'bsc', 'litecoin', 'dogecoin'],
        features: ['native-btc', 'no-wrapped-tokens'],
        swapTypes: ['cross-chain', 'native'],
      },
    ],
    timestamp: new Date().toISOString(),
  });
});

// ── GET /api/swap/rates ──────────────────────────────────────────────────────
router.get('/rates', apiLimiter, async (req, res) => {
  try {
    const prices = await getRealTimePrices();
    const rates = {};
    supportedCoins.forEach((coin) => {
      const key = getBaseCoin(coin).toLowerCase();
      if (prices[key]) rates[coin] = prices[key].usd;
    });
    res.json({
      success: true,
      rates,
      timestamp: new Date().toISOString(),
      source: 'CoinGecko',
      updateFrequency: '30 seconds',
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to fetch exchange rates' });
  }
});

// ── GET /api/swap/coins ──────────────────────────────────────────────────────
router.get('/coins', apiLimiter, async (req, res) => {
  try {
    const prices = await getRealTimePrices();
    const coins = supportedCoins.map((coin) => ({
      symbol: coin,
      name: getCoinName(getBaseCoin(coin)),
      price: prices[getBaseCoin(coin).toLowerCase()]?.usd || 0,
      change24h: prices[getBaseCoin(coin).toLowerCase()]?.usd_24h_change || 0,
      network: determinePrimaryNetwork(getBaseCoin(coin)),
    }));
    res.json({ success: true, coins, timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to fetch available coins' });
  }
});

module.exports = router;

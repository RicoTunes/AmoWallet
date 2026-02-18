const express = require('express');
const router = express.Router();
const https = require('https');

// Simple in-memory cache: { symbol: { data, fetchedAt } }
const cache = {};
const CACHE_TTL_MS = 2 * 60 * 1000; // 2 minutes

// CoinGecko IDs for each symbol
const COIN_GECKO_IDS = {
  BTC: 'bitcoin',
  ETH: 'ethereum',
  BNB: 'binancecoin',
  USDT: 'tether',
  SOL: 'solana',
  XRP: 'ripple',
  DOGE: 'dogecoin',
  LTC: 'litecoin',
  MATIC: 'matic-network',
  AVAX: 'avalanche-2',
  TRX: 'tron',
};

/**
 * Fetch prices from CoinGecko (runs server-side — no CORS issue).
 * Returns: { BTC: { price, change24h, source }, ETH: {...}, ... }
 */
async function fetchFromCoinGecko(symbols) {
  const ids = symbols
    .map((s) => COIN_GECKO_IDS[s.toUpperCase()])
    .filter(Boolean)
    .join(',');

  if (!ids) return {};

  return new Promise((resolve, reject) => {
    const url = `https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd&include_24hr_change=true`;
    https
      .get(url, { headers: { Accept: 'application/json' } }, (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          try {
            if (res.statusCode !== 200) {
              return reject(new Error(`CoinGecko returned ${res.statusCode}`));
            }
            const json = JSON.parse(body);
            const result = {};
            // Reverse lookup: geckoId -> our symbol
            const reverse = Object.fromEntries(
              Object.entries(COIN_GECKO_IDS).map(([sym, id]) => [id, sym])
            );
            for (const [geckoId, data] of Object.entries(json)) {
              const sym = reverse[geckoId];
              if (sym) {
                result[sym] = {
                  price: data.usd || 0,
                  change24h: data.usd_24h_change || 0,
                  source: 'CoinGecko',
                };
              }
            }
            resolve(result);
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

/**
 * GET /api/prices?symbols=BTC,ETH,SOL,...
 * Returns prices for requested symbols, served from cache when fresh.
 */
router.get('/', async (req, res) => {
  try {
    const raw = req.query.symbols || 'BTC,ETH,BNB,USDT,SOL,XRP,DOGE,LTC,TRX';
    const symbols = raw
      .split(',')
      .map((s) => s.trim().toUpperCase())
      .filter(Boolean);

    const now = Date.now();
    const result = {};
    const needFetch = [];

    // Check cache for each symbol
    for (const sym of symbols) {
      const cached = cache[sym];
      if (cached && now - cached.fetchedAt < CACHE_TTL_MS) {
        result[sym] = cached.data;
      } else {
        needFetch.push(sym);
      }
    }

    // Fetch missing/stale symbols
    if (needFetch.length > 0) {
      try {
        const fresh = await fetchFromCoinGecko(needFetch);
        for (const [sym, data] of Object.entries(fresh)) {
          cache[sym] = { data, fetchedAt: now };
          result[sym] = data;
        }
        // For any symbols that CoinGecko didn't return, use stale cache if available
        for (const sym of needFetch) {
          if (!result[sym] && cache[sym]) {
            result[sym] = cache[sym].data; // stale but better than nothing
          }
        }
      } catch (err) {
        console.error('Price fetch error:', err.message);
        // Return stale cache on error
        for (const sym of needFetch) {
          if (cache[sym]) result[sym] = cache[sym].data;
        }
      }
    }

    res.json({ success: true, prices: result, timestamp: new Date().toISOString() });
  } catch (err) {
    console.error('Price route error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;

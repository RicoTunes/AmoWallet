const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const { swapQuoteLimiter, transactionLimiter, apiLimiter } = require('../middleware/rateLimiter');
const axios = require('axios');
const TransactionManager = require('../lib/transactionManager');
const { SwapEngine } = require('../swap-engine/swapEngine');
const revenueService = require('../services/revenueService');
require('dotenv').config();

// Fee configuration (loaded from env)
const SWAP_FEE_PERCENTAGE = parseFloat(process.env.SWAP_FEE_PERCENTAGE || '1.0'); // 1% default
const MIN_SWAP_FEE_USD = parseFloat(process.env.MIN_TRANSACTION_FEE_USD || '0.50');
const TREASURY_ADDRESS = process.env.TREASURY_USDT_ADDRESS || '0x726dac06826a2e48be08cc02835a2083644076b2';

console.log(`💰 Swap Fee Configuration: ${SWAP_FEE_PERCENTAGE}% (min $${MIN_SWAP_FEE_USD})`);
console.log(`💎 Treasury Address: ${TREASURY_ADDRESS}`);

// Initialize REAL swap engine with decentralized DEX providers
const swapEngine = new SwapEngine();

// Security middleware for swap routes
router.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true
  }
}));

// Supported coins for swapping (including network variants)
const supportedCoins = [
  'BTC', 'ETH', 'BNB', 'USDT', 'USDC', 'DAI', 'LTC', 'DOGE', 'XRP', 'SOL',
  'USDT-ERC20', 'USDT-BEP20', 'USDT-TRC20',
  'USDC-ERC20', 'USDC-BEP20',
  'MATIC', 'TRX'
];

// Helper to get base coin from network variant (e.g., USDT-BEP20 -> USDT)
function getBaseCoin(coin) {
  if (coin.includes('-')) {
    return coin.split('-')[0];
  }
  return coin;
}

// Real DEX configuration with actual router contracts and environment variables
const dexConfigs = {
  'ethereum': {
    name: 'Uniswap V3',
    router: process.env.UNISWAP_V3_ROUTER || '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    routerV2: process.env.UNISWAP_V2_ROUTER || '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    fee: parseFloat(process.env.SWAP_FEE_BPS || '30') / 10000, // 0.3% default
    api: 'https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3'
  },
  'bsc': {
    name: 'PancakeSwap V3',
    router: process.env.PANCAKESWAP_V3_ROUTER || '0x13f4EA83D0bd40E75C8222255bc855a974568Dd4',
    routerV2: process.env.PANCAKESWAP_V2_ROUTER || '0x10ED43C718714eb63d5aA57B78B54704E256024E',
    fee: parseFloat(process.env.SWAP_FEE_BPS || '25') / 10000, // 0.25% default
    api: 'https://api.thegraph.com/subgraphs/name/pancakeswap/exchange-v3-bsc'
  },
  'polygon': {
    name: 'QuickSwap',
    router: '0xf5b509bb0fdcd1f0c1165b27057037561abc6ec5',
    fee: 0.003,
    api: 'https://api.thegraph.com/subgraphs/name/quickswap/quickswap'
  },
  'arbitrum': {
    name: 'Uniswap V3 (Arbitrum)',
    router: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    fee: 0.003,
    api: 'https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3-arbitrum'
  }
};

// Token contract addresses for major tokens
const tokenContracts = {
  'ethereum': {
    'USDT': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    'USDC': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    'DAI': '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    'WBTC': '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599'
  },
  'bsc': {
    'USDT': '0x55d398326f99059fF775485246999027B3197955',
    'USDC': '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    'BUSD': '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56'
  }
};

const transactionManager = new TransactionManager();

// Token addresses for DEX swaps
const TOKEN_ADDRESSES = {
  ethereum: {
    ETH: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
    WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    USDT: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    WBTC: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
  },
  bsc: {
    BNB: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
    WBNB: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
    USDT: '0x55d398326f99059fF775485246999027B3197955',
    USDC: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    ETH: '0x2170Ed0880ac9A755fd29B2688956BD959F933F8',
  },
  polygon: {
    MATIC: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
    WMATIC: '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270',
    USDT: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
    USDC: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174',
    WETH: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
  },
  arbitrum: {
    ETH: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
    WETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    USDT: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    USDC: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    ARB: '0x912CE59144191C1204E64559FE8253a0e49E6548',
  },
};

const CHAIN_IDS = {
  ethereum: 1,
  bsc: 56,
  polygon: 137,
  arbitrum: 42161,
  optimism: 10,
};

// Helper to get token address
function getTokenAddress(coin, chain) {
  const baseCoin = getBaseCoin(coin);
  return TOKEN_ADDRESSES[chain]?.[baseCoin] || TOKEN_ADDRESSES[chain]?.[`W${baseCoin}`] || null;
}

// POST get REAL swap quotes from decentralized DEX aggregators
router.post('/quote', swapQuoteLimiter, [
  body('fromCoin').isString().notEmpty(),
  body('toCoin').isString().notEmpty(),
  body('amount').isFloat({ min: 0.00000001 }),
  body('slippage').optional().isFloat({ min: 0.1, max: 50.0 }),
  body('userAddress').optional().isString(),
  body('preferredProvider').optional().isString()
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    console.log('Validation errors:', errors.array());
    return res.status(400).json({
      success: false,
      error: 'Invalid quote parameters',
      details: errors.array()
    });
  }

  try {
    const { fromCoin, toCoin, amount, slippage = 1.0, userAddress, preferredProvider } = req.body;
    
    const fromBase = getBaseCoin(fromCoin);
    const toBase = getBaseCoin(toCoin);

    console.log(`[REAL SWAP] Quote request: ${amount} ${fromCoin} -> ${toCoin}`);

    if (fromCoin === toCoin) {
      return res.status(400).json({
        success: false,
        error: 'Cannot swap the same coin'
      });
    }

    // Determine chain and get token addresses
    const chain = determineNetwork(fromCoin, toCoin);
    const chainId = CHAIN_IDS[chain] || 1;
    const fromTokenAddress = getTokenAddress(fromCoin, chain);
    const toTokenAddress = getTokenAddress(toCoin, chain);

    // Get REAL quotes from decentralized DEX aggregators
    const quoteParams = {
      fromCoin: fromBase,
      toCoin: toBase,
      fromTokenAddress,
      toTokenAddress,
      amount: amount.toString(),
      slippage,
      chainId,
      userAddress: userAddress || '0x0000000000000000000000000000000000000000',
    };

    console.log(`[REAL SWAP] Fetching quotes from DEX aggregators...`);
    
    // Get quotes from all available providers
    const result = await swapEngine.getQuotes(quoteParams);
    
    // Ensure quotes is always an array
    let quotes = [];
    if (Array.isArray(result)) {
      quotes = result;
    } else if (result && Array.isArray(result.quotes)) {
      quotes = result.quotes;
    } else if (result && result.success === false) {
      console.log(`[REAL SWAP] Swap engine returned error: ${result.error}`);
      quotes = [];
    }

    if (!quotes || quotes.length === 0) {
      // Fallback to price estimation if no DEX quotes available
      console.log(`[REAL SWAP] No DEX quotes available, using price estimation`);
      const prices = await getRealTimePrices();
      const fromPrice = prices[fromBase.toLowerCase()]?.usd || 1;
      const toPrice = prices[toBase.toLowerCase()]?.usd || 1;
      const exchangeRate = fromPrice / toPrice;
      const estimatedOutput = amount * exchangeRate * 0.997; // 0.3% fee estimate

      return res.json({
        success: true,
        quotes: [{
          provider: 'price-estimate',
          fromCoin,
          toCoin,
          fromAmount: amount,
          toAmount: estimatedOutput,
          exchangeRate,
          protocolFee: amount * 0.003,
          gasFee: 0,
          slippage,
          estimatedTime: '1-5 minutes',
          isEstimate: true,
        }],
        bestQuote: {
          provider: 'price-estimate',
          toAmount: estimatedOutput,
        },
        timestamp: new Date().toISOString(),
      });
    }

    // Filter by preferred provider if specified
    let filteredQuotes = Array.isArray(quotes) ? quotes : [];
    if (preferredProvider && filteredQuotes.length > 0) {
      const filtered = filteredQuotes.filter(q => q.provider === preferredProvider);
      if (filtered.length > 0) filteredQuotes = filtered;
    }

    // Safety check - ensure we have quotes
    if (!filteredQuotes || filteredQuotes.length === 0) {
      // Fallback to price estimation
      console.log(`[REAL SWAP] No valid quotes after filtering, using price estimation`);
      const prices = await getRealTimePrices();
      const fromPrice = prices[fromBase.toLowerCase()]?.usd || getFallbackPrice(fromBase);
      const toPrice = prices[toBase.toLowerCase()]?.usd || getFallbackPrice(toBase);
      const exchangeRate = fromPrice / toPrice;
      const estimatedOutput = amount * exchangeRate * 0.997;

      return res.json({
        success: true,
        quotes: [{
          provider: 'price-estimate',
          fromCoin,
          toCoin,
          fromAmount: amount,
          toAmount: estimatedOutput,
          exchangeRate,
          protocolFee: amount * 0.003,
          gasFee: 0,
          slippage,
          estimatedTime: '1-5 minutes',
          isEstimate: true,
        }],
        bestQuote: {
          provider: 'price-estimate',
          toAmount: estimatedOutput,
          exchangeRate,
        },
        chain,
        chainId,
        timestamp: new Date().toISOString(),
      });
    }

    // Find best quote (highest output amount)
    const bestQuote = filteredQuotes.reduce((best, current) => 
      (current.toAmount > best.toAmount) ? current : best
    , filteredQuotes[0]);

    console.log(`[REAL SWAP] Got ${quotes.length} quotes, best: ${bestQuote.provider} = ${bestQuote.toAmount} ${toCoin}`);

    // Calculate platform fee (our revenue)
    const platformFeeRate = SWAP_FEE_PERCENTAGE / 100;
    
    res.json({
      success: true,
      quotes: filteredQuotes.map(q => {
        // Calculate platform fee on this quote
        const platformFee = q.toAmount * platformFeeRate;
        const netToAmount = q.toAmount - platformFee;
        
        return {
          provider: q.provider,
          fromCoin,
          toCoin,
          fromAmount: amount,
          toAmount: netToAmount, // Amount after our fee
          grossAmount: q.toAmount, // Amount before our fee
          exchangeRate: netToAmount / amount,
          protocolFee: q.protocolFee || 0,
          gasFee: q.gasFee || 0,
          bridgeFee: q.bridgeFee || 0,
          platformFee: platformFee, // OUR FEE
          platformFeeRate: SWAP_FEE_PERCENTAGE,
          totalFees: (q.protocolFee || 0) + (q.gasFee || 0) + (q.bridgeFee || 0) + platformFee,
          slippage: q.slippage || slippage,
          minOutput: (q.minOutput || q.toAmount * (1 - slippage / 100)) - platformFee,
          estimatedTime: q.estimatedTime || '1-5 minutes',
          route: q.route || null,
          quoteId: q.quoteId || null,
          treasuryAddress: TREASURY_ADDRESS, // Where fee goes
        };
      }),
      bestQuote: {
        provider: bestQuote.provider,
        toAmount: bestQuote.toAmount - (bestQuote.toAmount * platformFeeRate),
        grossAmount: bestQuote.toAmount,
        exchangeRate: (bestQuote.toAmount - (bestQuote.toAmount * platformFeeRate)) / amount,
        platformFee: bestQuote.toAmount * platformFeeRate,
      },
      feeInfo: {
        platformFeeRate: SWAP_FEE_PERCENTAGE,
        minFeeUSD: MIN_SWAP_FEE_USD,
        treasuryAddress: TREASURY_ADDRESS,
      },
      chain,
      chainId,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('[REAL SWAP] Quote error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get swap quotes: ' + error.message
    });
  }
});

// POST build transaction for user to sign (NON-CUSTODIAL)
router.post('/build-transaction', transactionLimiter, [
  body('provider').isString().notEmpty(),
  body('fromCoin').isString().notEmpty(),
  body('toCoin').isString().notEmpty(),
  body('fromAmount').isFloat({ min: 0.00000001 }),
  body('userAddress').isString().isLength({ min: 26 }),
  body('slippage').optional().isFloat({ min: 0.1, max: 50.0 }),
  body('quoteId').optional().isString()
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Invalid parameters',
      details: errors.array()
    });
  }

  try {
    const { provider, fromCoin, toCoin, fromAmount, userAddress, slippage = 1.0, quoteId } = req.body;
    
    console.log(`[REAL SWAP] Building transaction: ${provider} ${fromAmount} ${fromCoin} -> ${toCoin}`);

    const chain = determineNetwork(fromCoin, toCoin);
    const chainId = CHAIN_IDS[chain] || 1;
    const fromBase = getBaseCoin(fromCoin);
    const toBase = getBaseCoin(toCoin);

    // Build the transaction using the swap engine
    const txData = await swapEngine.buildTransaction({
      provider,
      fromToken: fromBase,
      toToken: toBase,
      fromTokenAddress: getTokenAddress(fromCoin, chain),
      toTokenAddress: getTokenAddress(toCoin, chain),
      amount: fromAmount.toString(),
      userAddress,
      slippage,
      chainId,
      quoteId,
    });

    if (!txData || txData.error) {
      throw new Error(txData?.error || 'Failed to build transaction');
    }

    console.log(`[REAL SWAP] Transaction built successfully for ${provider}`);

    // Return unsigned transaction for user to sign locally
    res.json({
      success: true,
      transaction: {
        to: txData.to,
        data: txData.data,
        value: txData.value || '0',
        gasLimit: txData.gasLimit || txData.gas,
        gasPrice: txData.gasPrice,
        chainId,
      },
      provider,
      fromCoin,
      toCoin,
      fromAmount,
      expectedOutput: txData.toAmount,
      minOutput: txData.minOutput,
      // User signs this transaction locally - we never touch their private key
      instructions: 'Sign this transaction with your wallet. We never have access to your funds.',
    });
  } catch (error) {
    console.error('[REAL SWAP] Build transaction error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to build transaction: ' + error.message
    });
  }
});

// POST execute real swap with DEX integration (LEGACY - for backwards compatibility)
router.post('/execute', transactionLimiter, [
  body('fromCoin').isString().notEmpty(),
  body('toCoin').isString().notEmpty(),
  body('fromAmount').isFloat({ min: 0.00000001 }),
  body('toAmount').isFloat({ min: 0 }),
  body('exchangeRate').isFloat({ min: 0.00000001 }),
  body('fee').isFloat({ min: 0 }),
  body('slippage').optional().isFloat({ min: 0.1, max: 5.0 }),
  body('userAddress').isString().isLength({ min: 26 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Invalid swap execution parameters'
    });
  }

  try {
    const {
      fromCoin,
      toCoin,
      fromAmount,
      toAmount,
      exchangeRate,
      fee,
      slippage = 1.0,
      userAddress,
      provider = 'auto'
    } = req.body;

    const network = determineNetwork(fromCoin, toCoin);
    const chainId = CHAIN_IDS[network] || 1;
    const fromBase = getBaseCoin(fromCoin);
    const toBase = getBaseCoin(toCoin);

    console.log(`[REAL SWAP] Execute: ${fromAmount} ${fromCoin} -> ${toCoin} via ${provider}`);

    // Build real transaction from DEX aggregator
    let txData;
    try {
      txData = await swapEngine.buildTransaction({
        provider: provider === 'auto' ? '1inch' : provider,
        fromToken: fromBase,
        toToken: toBase,
        fromTokenAddress: getTokenAddress(fromCoin, network),
        toTokenAddress: getTokenAddress(toCoin, network),
        amount: fromAmount.toString(),
        userAddress,
        slippage,
        chainId,
      });
    } catch (buildError) {
      console.log(`[REAL SWAP] DEX build failed, using quote data: ${buildError.message}`);
      // If DEX call fails, return the quote data for local execution
      txData = null;
    }

    // Generate transaction hash placeholder (real hash comes after user signs)
    const txHash = generateDexTransactionHash(network);

    res.json({
      success: true,
      type: 'swap',
      fromCoin,
      toCoin,
      fromAmount,
      toAmount,
      exchangeRate,
      fee,
      slippage,
      network,
      chainId,
      provider: txData?.provider || provider,
      userAddress,
      // If we have real tx data, include it for signing
      transaction: txData ? {
        to: txData.to,
        data: txData.data,
        value: txData.value || '0',
        gasLimit: txData.gasLimit || txData.gas,
        gasPrice: txData.gasPrice,
      } : null,
      txHash, // Placeholder until user signs
      status: 'pending_signature',
      timestamp: new Date().toISOString(),
      explorerUrl: generateExplorerUrl(network, txHash),
      // Non-custodial: user must sign locally
      instructions: 'Sign transaction locally with your private key. We never hold your funds.',
    });
  } catch (error) {
    console.error('[REAL SWAP] Execution error:', error);
    res.status(500).json({
      success: false,
      error: 'Swap execution failed: ' + error.message
    });
  }
});

// GET available DEX providers
router.get('/providers', apiLimiter, async (req, res) => {
  try {
    res.json({
      success: true,
      providers: [
        {
          id: '1inch',
          name: '1inch',
          type: 'dex-aggregator',
          chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism'],
          features: ['best-price', 'split-routing', 'gas-optimization'],
          swapTypes: ['same-chain'],
        },
        {
          id: '0x',
          name: '0x Protocol',
          type: 'dex-aggregator',
          chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism'],
          features: ['professional-grade', 'limit-orders'],
          swapTypes: ['same-chain'],
        },
        {
          id: 'paraswap',
          name: 'Paraswap',
          type: 'dex-aggregator',
          chains: ['ethereum', 'bsc', 'polygon', 'arbitrum'],
          features: ['multi-path', 'gas-refund'],
          swapTypes: ['same-chain'],
        },
        {
          id: 'lifi',
          name: 'LI.FI',
          type: 'bridge-aggregator',
          chains: ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism', 'avalanche'],
          features: ['cross-chain', 'bridge-aggregation'],
          swapTypes: ['same-chain', 'cross-chain'],
        },
        {
          id: 'thorchain',
          name: 'THORChain',
          type: 'native-swap',
          chains: ['bitcoin', 'ethereum', 'bsc', 'litecoin', 'dogecoin'],
          features: ['native-btc', 'no-wrapped-tokens'],
          swapTypes: ['cross-chain', 'native'],
        },
      ],
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to get providers' });
  }
});

// GET available coins for swapping with real-time data
router.get('/coins', apiLimiter, async (req, res) => {
  try {
    // Get real-time prices to include in response
    const prices = await getRealTimePrices();
    
    const coinsWithPrices = supportedCoins.map(coin => ({
      symbol: coin,
      name: getCoinName(coin),
      price: prices[getBaseCoin(coin).toLowerCase()]?.usd || 0,
      change24h: prices[getBaseCoin(coin).toLowerCase()]?.usd_24h_change || 0,
      network: determinePrimaryNetwork(coin)
    }));

    res.json({
      success: true,
      coins: coinsWithPrices,
      timestamp: new Date().toISOString(),
      priceSource: 'CoinGecko'
    });
  } catch (error) {
    console.error('Coins error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch available coins'
    });
  }
});

// GET current exchange rates from real API
router.get('/rates', apiLimiter, async (req, res) => {
  try {
    const prices = await getRealTimePrices();
    
    // Filter prices to only include supported coins
    const rates = {};
    supportedCoins.forEach(coin => {
      if (prices[coin.toLowerCase()]) {
        rates[coin] = prices[coin.toLowerCase()].usd;
      }
    });

    res.json({
      success: true,
      rates: rates,
      timestamp: new Date().toISOString(),
      source: 'CoinGecko',
      updateFrequency: '30 seconds'
    });
  } catch (error) {
    console.error('Rates error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch exchange rates'
    });
  }
});

// GET swap history for user
router.get('/history/:userAddress', apiLimiter, async (req, res) => {
  try {
    const { userAddress } = req.params;
    
    // In real implementation, this would query a database
    // For now, return empty history for new users
    const swapHistory = [];

    res.json({
      success: true,
      userAddress,
      swaps: swapHistory,
      count: swapHistory.length
    });
  } catch (error) {
    console.error('History error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch swap history'
    });
  }
});

// Helper functions
async function getRealTimePrices() {
  try {
    // Map supportedCoins to CoinGecko IDs
    const coinGeckoIds = {
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'BNB': 'binancecoin',
      'USDT': 'tether',
      'USDC': 'usd-coin',
      'DAI': 'dai',
      'LTC': 'litecoin',
      'DOGE': 'dogecoin',
      'XRP': 'ripple',
      'SOL': 'solana'
    };

    const coinIds = Object.values(coinGeckoIds).join(',');
    
    // Use CoinGecko API with optional API key from environment
    const apiKey = process.env.COINGECKO_API_KEY ? `&x_cg_pro_api_key=${process.env.COINGECKO_API_KEY}` : '';
    const response = await axios.get(
      `https://api.coingecko.com/api/v3/simple/price?ids=${coinIds}&vs_currencies=usd&include_24hr_change=true${apiKey}`,
      { timeout: 10000 }
    );
    
    // Transform response to use symbol keys
    const prices = {};
    Object.entries(coinGeckoIds).forEach(([symbol, geckoId]) => {
      if (response.data[geckoId]) {
        prices[symbol.toLowerCase()] = response.data[geckoId];
      }
    });
    
    return prices;
  } catch (error) {
    console.error('CoinGecko API error:', error.message);
    
    try {
      // Fallback to CoinMarketCap if available
      if (process.env.COINMARKETCAP_API_KEY) {
        return await getCoinMarketCapPrices();
      }
    } catch (fallbackError) {
      console.error('CoinMarketCap fallback error:', fallbackError.message);
    }
    
    // Last resort: return mock data
    return getMockPrices();
  }
}

async function getCoinMarketCapPrices() {
  try {
    const response = await axios.get(
      'https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest',
      {
        params: {
          symbol: 'BTC,ETH,BNB,USDT,USDC,DAI,LTC,DOGE,XRP,SOL',
          convert: 'USD'
        },
        headers: {
          'X-CMC_PRO_API_KEY': process.env.COINMARKETCAP_API_KEY
        },
        timeout: 10000
      }
    );

    const prices = {};
    Object.entries(response.data.data).forEach(([symbol, data]) => {
      prices[symbol.toLowerCase()] = {
        usd: data.quote.USD.price,
        usd_24h_change: data.quote.USD.percent_change_24h
      };
    });

    return prices;
  } catch (error) {
    console.error('CoinMarketCap error:', error.message);
    throw error;
  }
}

function getMockPrices() {
  return {
    'btc': { usd: 60250.75, usd_24h_change: 2.34 },
    'eth': { usd: 3450.20, usd_24h_change: 1.56 },
    'bnb': { usd: 585.30, usd_24h_change: 0.89 },
    'usdt': { usd: 1.00, usd_24h_change: 0.01 },
    'usdc': { usd: 1.00, usd_24h_change: 0.01 },
    'dai': { usd: 1.00, usd_24h_change: 0.02 },
    'ltc': { usd: 82.45, usd_24h_change: -0.45 },
    'doge': { usd: 0.15, usd_24h_change: 3.21 },
    'xrp': { usd: 0.52, usd_24h_change: 1.23 },
    'sol': { usd: 145.67, usd_24h_change: 5.67 }
  };
}

// Get fallback price for a coin
function getFallbackPrice(coin) {
  const fallbackPrices = {
    'BTC': 90000,
    'ETH': 3000,
    'BNB': 600,
    'USDT': 1,
    'USDC': 1,
    'DAI': 1,
    'LTC': 100,
    'DOGE': 0.3,
    'XRP': 2,
    'SOL': 200,
    'MATIC': 0.5,
    'AVAX': 35,
  };
  return fallbackPrices[coin.toUpperCase()] || 1;
}

function determineNetwork(fromCoin, toCoin) {
  // Network determination based on coin types
  const ethCoins = ['ETH', 'USDT', 'USDC', 'DAI'];
  const bscCoins = ['BNB', 'BUSD'];
  
  if (ethCoins.includes(fromCoin) || ethCoins.includes(toCoin)) return 'ethereum';
  if (bscCoins.includes(fromCoin) || bscCoins.includes(toCoin)) return 'bsc';
  
  return 'ethereum'; // default
}

function determinePrimaryNetwork(coin) {
  switch (coin) {
    case 'BTC': return 'bitcoin';
    case 'ETH': return 'ethereum';
    case 'BNB': return 'bsc';
    case 'USDT':
    case 'USDC':
    case 'DAI': return 'multi-chain';
    case 'LTC': return 'litecoin';
    case 'DOGE': return 'dogecoin';
    case 'XRP': return 'ripple';
    case 'SOL': return 'solana';
    default: return 'unknown';
  }
}

function getCoinName(symbol) {
  const names = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'BNB': 'Binance Coin',
    'USDT': 'Tether',
    'USDC': 'USD Coin',
    'DAI': 'Dai',
    'LTC': 'Litecoin',
    'DOGE': 'Dogecoin',
    'XRP': 'Ripple',
    'SOL': 'Solana'
  };
  return names[symbol] || symbol;
}

function generateDexTransactionHash(network) {
  const crypto = require('crypto');
  const hash = crypto.randomBytes(32).toString('hex');
  
  switch (network) {
    case 'ethereum':
    case 'bsc':
    case 'polygon':
    case 'arbitrum':
      return '0x' + hash;
    case 'tron':
      return hash.toUpperCase();
    default:
      return hash;
  }
}

function generateExplorerUrl(network, txHash) {
  const explorers = {
    'ethereum': `https://etherscan.io/tx/${txHash}`,
    'bsc': `https://bscscan.com/tx/${txHash}`,
    'polygon': `https://polygonscan.com/tx/${txHash}`,
    'arbitrum': `https://arbiscan.io/tx/${txHash}`,
    'tron': `https://tronscan.org/#/transaction/${txHash}`
  };
  return explorers[network] || '#';
}

module.exports = router;

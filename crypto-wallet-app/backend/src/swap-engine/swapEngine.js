/**
 * Decentralized Swap Engine
 * 
 * SECURITY PRINCIPLES:
 * - Non-custodial: App NEVER holds user funds
 * - No KYC: All providers are permissionless
 * - User signs all transactions locally
 * 
 * ALLOWED PROVIDERS:
 * - 1inch (same-chain ERC20)
 * - 0x API (same-chain ERC20)
 * - Paraswap (same-chain ERC20)
 * - THORChain (native BTC swaps)
 * - LI.FI (cross-chain aggregator)
 */

const axios = require('axios');

// Chain configurations
const CHAINS = {
  1: { name: 'Ethereum', symbol: 'ETH', rpc: 'https://eth.llamarpc.com' },
  56: { name: 'BSC', symbol: 'BNB', rpc: 'https://bsc-dataseed.binance.org' },
  137: { name: 'Polygon', symbol: 'MATIC', rpc: 'https://polygon-rpc.com' },
  42161: { name: 'Arbitrum', symbol: 'ETH', rpc: 'https://arb1.arbitrum.io/rpc' },
  10: { name: 'Optimism', symbol: 'ETH', rpc: 'https://mainnet.optimism.io' },
  43114: { name: 'Avalanche', symbol: 'AVAX', rpc: 'https://api.avax.network/ext/bc/C/rpc' },
  8453: { name: 'Base', symbol: 'ETH', rpc: 'https://mainnet.base.org' },
};

const NATIVE_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

// Token addresses by chain
const TOKENS = {
  USDT: {
    1: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    56: '0x55d398326f99059fF775485246999027B3197955',
    137: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
    42161: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
  },
  USDC: {
    1: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    56: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    137: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174',
    42161: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    10: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
    8453: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
  },
};

const DECIMALS = {
  BTC: 8, ETH: 18, BNB: 18, MATIC: 18, AVAX: 18, USDT: 6, USDC: 6,
};

class SwapEngine {
  constructor() {
    this.providers = {
      '1inch': new OneInchProvider(),
      '0x': new ZeroXProvider(),
      'paraswap': new ParaswapProvider(),
      'lifi': new LiFiProvider(),
      'thorchain': new THORChainProvider(),
    };
  }

  /**
   * Get quotes from all applicable providers
   */
  async getQuotes(params) {
    // Support both naming conventions
    const fromCoin = params.fromCoin || params.fromToken;
    const toCoin = params.toCoin || params.toToken;
    const amount = params.amount;
    const userAddress = params.userAddress || '0x0000000000000000000000000000000000000000';
    const slippage = params.slippage || 0.5;
    
    if (!fromCoin || !toCoin || !amount) {
      console.log('Missing required params:', { fromCoin, toCoin, amount });
      return [];
    }
    
    console.log(`\n🔄 Getting real swap quotes: ${amount} ${fromCoin} → ${toCoin}`);
    
    // Detect swap type and applicable providers
    const swapType = this.detectSwapType(fromCoin, toCoin);
    const applicableProviders = this.getApplicableProviders(swapType);
    
    console.log(`   Swap type: ${swapType}`);
    console.log(`   Providers: ${applicableProviders.join(', ')}`);
    
    // Build token info
    const fromToken = this.buildToken(fromCoin);
    const toToken = this.buildToken(toCoin);
    
    // Convert amount to smallest unit
    const amountWei = this.toSmallestUnit(amount, fromToken.decimals);
    
    // Query all providers in parallel
    const quotePromises = applicableProviders.map(async (providerName) => {
      try {
        const provider = this.providers[providerName];
        const quote = await provider.getQuote({
          fromToken,
          toToken,
          amount: amountWei,
          userAddress,
          slippage,
        });
        
        if (quote) {
          quote.provider = providerName;
          return quote;
        }
      } catch (err) {
        console.log(`   ❌ ${providerName}: ${err.message}`);
      }
      return null;
    });
    
    const results = await Promise.all(quotePromises);
    const quotes = results.filter(q => q !== null);
    
    if (quotes.length === 0) {
      return { success: false, error: 'No quotes available from any provider' };
    }
    
    // Sort by best output amount
    quotes.sort((a, b) => parseFloat(b.toAmount) - parseFloat(a.toAmount));
    
    // Format for frontend
    const formattedQuotes = quotes.map(q => ({
      provider: q.provider,
      fromCoin,
      toCoin,
      fromAmount: parseFloat(amount),
      toAmount: this.fromSmallestUnit(q.toAmount, toToken.decimals),
      toAmountMin: this.fromSmallestUnit(q.toAmountMin, toToken.decimals),
      exchangeRate: q.exchangeRate,
      fees: q.fees,
      priceImpact: q.priceImpact || 0,
      route: q.route || [q.provider],
      estimatedGas: q.estimatedGas,
      tx: q.tx, // Transaction data for signing
    }));
    
    console.log(`\n   ✅ Got ${formattedQuotes.length} quotes`);
    formattedQuotes.forEach(q => {
      console.log(`      ${q.provider}: ${q.toAmount.toFixed(6)} ${toCoin} (fee: $${q.fees.totalUSD.toFixed(2)})`);
    });
    
    return {
      success: true,
      quotes: formattedQuotes,
      bestQuote: formattedQuotes[0],
      swapType,
    };
  }

  /**
   * Build transaction for user to sign
   */
  async buildTransaction(quote, userAddress) {
    const provider = this.providers[quote.provider];
    if (!provider) {
      throw new Error(`Unknown provider: ${quote.provider}`);
    }
    
    return await provider.buildTransaction(quote, userAddress);
  }

  detectSwapType(fromCoin, toCoin) {
    const fromBase = fromCoin.split('-')[0];
    const toBase = toCoin.split('-')[0];
    
    // Native BTC swap
    if (fromBase === 'BTC' || toBase === 'BTC') {
      return 'btc-swap';
    }
    
    // Get chains
    const fromChain = this.getChainId(fromCoin);
    const toChain = this.getChainId(toCoin);
    
    // Cross-chain
    if (fromChain !== toChain) {
      return 'cross-chain';
    }
    
    return 'same-chain';
  }

  getApplicableProviders(swapType) {
    switch (swapType) {
      case 'btc-swap':
        return ['thorchain'];
      case 'cross-chain':
        return ['lifi'];
      case 'same-chain':
      default:
        return ['1inch', '0x', 'paraswap', 'lifi'];
    }
  }

  getChainId(coin) {
    if (coin.includes('-BEP20') || coin.includes('-BSC')) return 56;
    if (coin.includes('-POLYGON')) return 137;
    if (coin.includes('-ARB') || coin.includes('-ARBITRUM')) return 42161;
    if (coin.includes('-OP') || coin.includes('-OPTIMISM')) return 10;
    if (coin.includes('-AVAX')) return 43114;
    if (coin.includes('-BASE')) return 8453;
    
    const base = coin.split('-')[0];
    if (base === 'BNB') return 56;
    if (base === 'MATIC') return 137;
    if (base === 'AVAX') return 43114;
    
    return 1; // Default Ethereum
  }

  buildToken(coin) {
    const parts = coin.split('-');
    const symbol = parts[0];
    const chainId = this.getChainId(coin);
    const decimals = DECIMALS[symbol] || 18;
    
    let address = NATIVE_ADDRESS;
    if (['USDT', 'USDC'].includes(symbol)) {
      address = TOKENS[symbol]?.[chainId] || NATIVE_ADDRESS;
    }
    
    return { symbol, address, decimals, chainId, name: symbol };
  }

  toSmallestUnit(amount, decimals) {
    return BigInt(Math.floor(parseFloat(amount) * Math.pow(10, decimals))).toString();
  }

  fromSmallestUnit(amount, decimals) {
    return parseFloat(amount) / Math.pow(10, decimals);
  }
}

/**
 * 1inch Provider - Same-chain ERC20 swaps
 * Non-custodial DEX aggregator
 */
class OneInchProvider {
  constructor() {
    this.name = '1inch';
    this.baseUrls = {
      1: 'https://api.1inch.dev/swap/v6.0/1',
      56: 'https://api.1inch.dev/swap/v6.0/56',
      137: 'https://api.1inch.dev/swap/v6.0/137',
      42161: 'https://api.1inch.dev/swap/v6.0/42161',
      10: 'https://api.1inch.dev/swap/v6.0/10',
      43114: 'https://api.1inch.dev/swap/v6.0/43114',
      8453: 'https://api.1inch.dev/swap/v6.0/8453',
    };
  }

  async getQuote({ fromToken, toToken, amount, userAddress, slippage }) {
    if (fromToken.chainId !== toToken.chainId) return null;
    
    const baseUrl = this.baseUrls[fromToken.chainId];
    if (!baseUrl) return null;
    
    try {
      const headers = { Accept: 'application/json' };
      if (process.env.ONEINCH_API_KEY) {
        headers.Authorization = `Bearer ${process.env.ONEINCH_API_KEY}`;
      }
      
      // Get quote first
      const quoteRes = await axios.get(`${baseUrl}/quote`, {
        headers,
        params: {
          src: fromToken.address,
          dst: toToken.address,
          amount,
          includeGas: true,
        },
        timeout: 10000,
      });
      
      const data = quoteRes.data;
      const gasPrice = await this.getGasPrice(fromToken.chainId);
      const gasFeeWei = BigInt(gasPrice) * BigInt(data.gas || 200000);
      const nativePrice = await this.getNativePrice(fromToken.chainId);
      const gasFeeUSD = (Number(gasFeeWei) / 1e18) * nativePrice;
      
      const toAmountMin = BigInt(BigInt(data.dstAmount) * BigInt(Math.floor((100 - slippage) * 100)) / BigInt(10000)).toString();
      
      return {
        toAmount: data.dstAmount,
        toAmountMin,
        exchangeRate: (parseFloat(data.dstAmount) / Math.pow(10, toToken.decimals)) / 
                      (parseFloat(amount) / Math.pow(10, fromToken.decimals)),
        estimatedGas: data.gas || '200000',
        fees: {
          protocolUSD: 0,
          gasUSD: gasFeeUSD,
          bridgeUSD: 0,
          totalUSD: gasFeeUSD,
        },
        route: ['1inch Aggregator'],
        fromToken,
        toToken,
        amount,
        userAddress,
        slippage,
      };
    } catch (err) {
      console.error(`1inch error:`, err.response?.data?.description || err.message);
      return null;
    }
  }

  async buildTransaction(quote, userAddress) {
    const baseUrl = this.baseUrls[quote.fromToken.chainId];
    
    const headers = { Accept: 'application/json' };
    if (process.env.ONEINCH_API_KEY) {
      headers.Authorization = `Bearer ${process.env.ONEINCH_API_KEY}`;
    }
    
    const swapRes = await axios.get(`${baseUrl}/swap`, {
      headers,
      params: {
        src: quote.fromToken.address,
        dst: quote.toToken.address,
        amount: quote.amount,
        from: userAddress,
        slippage: quote.slippage,
        disableEstimate: false,
      },
      timeout: 15000,
    });
    
    const tx = swapRes.data.tx;
    return {
      to: tx.to,
      data: tx.data,
      value: tx.value || '0',
      gasLimit: tx.gas?.toString() || '300000',
      chainId: quote.fromToken.chainId,
    };
  }

  async getGasPrice(chainId) {
    try {
      const rpc = CHAINS[chainId]?.rpc;
      const res = await axios.post(rpc, {
        jsonrpc: '2.0', method: 'eth_gasPrice', params: [], id: 1,
      });
      return res.data.result;
    } catch {
      return '20000000000';
    }
  }

  async getNativePrice(chainId) {
    const ids = { 1: 'ethereum', 56: 'binancecoin', 137: 'matic-network', 42161: 'ethereum', 10: 'ethereum', 43114: 'avalanche-2', 8453: 'ethereum' };
    try {
      const res = await axios.get(`https://api.coingecko.com/api/v3/simple/price?ids=${ids[chainId]}&vs_currencies=usd`);
      return res.data[ids[chainId]]?.usd || 0;
    } catch {
      return { 1: 3000, 56: 600, 137: 0.9, 42161: 3000, 10: 3000, 43114: 35, 8453: 3000 }[chainId] || 0;
    }
  }
}

/**
 * 0x Protocol Provider - Same-chain ERC20 swaps
 */
class ZeroXProvider {
  constructor() {
    this.name = '0x';
    this.baseUrls = {
      1: 'https://api.0x.org',
      56: 'https://bsc.api.0x.org',
      137: 'https://polygon.api.0x.org',
      42161: 'https://arbitrum.api.0x.org',
      10: 'https://optimism.api.0x.org',
      43114: 'https://avalanche.api.0x.org',
      8453: 'https://base.api.0x.org',
    };
  }

  async getQuote({ fromToken, toToken, amount, userAddress, slippage }) {
    if (fromToken.chainId !== toToken.chainId) return null;
    
    const baseUrl = this.baseUrls[fromToken.chainId];
    if (!baseUrl) return null;
    
    try {
      const headers = { Accept: 'application/json' };
      if (process.env.ZEROX_API_KEY) {
        headers['0x-api-key'] = process.env.ZEROX_API_KEY;
      }
      
      const res = await axios.get(`${baseUrl}/swap/v1/price`, {
        headers,
        params: {
          sellToken: fromToken.address,
          buyToken: toToken.address,
          sellAmount: amount,
          takerAddress: userAddress,
          slippagePercentage: slippage / 100,
        },
        timeout: 10000,
      });
      
      const data = res.data;
      const gasFeeUSD = parseFloat(data.estimatedGas || 0) * parseFloat(data.gasPrice || 0) / 1e18 * 3000;
      const toAmountMin = BigInt(BigInt(data.buyAmount) * BigInt(Math.floor((100 - slippage) * 100)) / BigInt(10000)).toString();
      
      return {
        toAmount: data.buyAmount,
        toAmountMin,
        exchangeRate: (parseFloat(data.buyAmount) / Math.pow(10, toToken.decimals)) / 
                      (parseFloat(amount) / Math.pow(10, fromToken.decimals)),
        estimatedGas: data.estimatedGas || '200000',
        priceImpact: parseFloat(data.estimatedPriceImpact || 0),
        fees: {
          protocolUSD: 0,
          gasUSD: gasFeeUSD,
          bridgeUSD: 0,
          totalUSD: gasFeeUSD,
        },
        route: data.sources?.filter(s => parseFloat(s.proportion) > 0).map(s => s.name) || ['0x'],
        fromToken,
        toToken,
        amount,
        userAddress,
        slippage,
      };
    } catch (err) {
      console.error(`0x error:`, err.response?.data?.reason || err.message);
      return null;
    }
  }

  async buildTransaction(quote, userAddress) {
    const baseUrl = this.baseUrls[quote.fromToken.chainId];
    
    const headers = { Accept: 'application/json' };
    if (process.env.ZEROX_API_KEY) {
      headers['0x-api-key'] = process.env.ZEROX_API_KEY;
    }
    
    const res = await axios.get(`${baseUrl}/swap/v1/quote`, {
      headers,
      params: {
        sellToken: quote.fromToken.address,
        buyToken: quote.toToken.address,
        sellAmount: quote.amount,
        takerAddress: userAddress,
        slippagePercentage: quote.slippage / 100,
      },
      timeout: 15000,
    });
    
    return {
      to: res.data.to,
      data: res.data.data,
      value: res.data.value || '0',
      gasLimit: res.data.gas || '300000',
      chainId: quote.fromToken.chainId,
    };
  }
}

/**
 * Paraswap Provider - Same-chain ERC20 swaps
 */
class ParaswapProvider {
  constructor() {
    this.name = 'paraswap';
    this.baseUrl = 'https://apiv5.paraswap.io';
  }

  async getQuote({ fromToken, toToken, amount, userAddress, slippage }) {
    if (fromToken.chainId !== toToken.chainId) return null;
    
    try {
      const res = await axios.get(`${this.baseUrl}/prices`, {
        params: {
          srcToken: fromToken.address,
          destToken: toToken.address,
          amount,
          srcDecimals: fromToken.decimals,
          destDecimals: toToken.decimals,
          network: fromToken.chainId,
          side: 'SELL',
        },
        timeout: 10000,
      });
      
      const data = res.data.priceRoute;
      const gasFeeUSD = parseFloat(data.gasCostUSD || 0);
      const toAmountMin = BigInt(BigInt(data.destAmount) * BigInt(Math.floor((100 - slippage) * 100)) / BigInt(10000)).toString();
      
      return {
        toAmount: data.destAmount,
        toAmountMin,
        exchangeRate: (parseFloat(data.destAmount) / Math.pow(10, toToken.decimals)) / 
                      (parseFloat(amount) / Math.pow(10, fromToken.decimals)),
        estimatedGas: data.gasCost || '200000',
        fees: {
          protocolUSD: 0,
          gasUSD: gasFeeUSD,
          bridgeUSD: 0,
          totalUSD: gasFeeUSD,
        },
        route: data.bestRoute?.map(r => r.swaps?.[0]?.exchange || 'Paraswap') || ['Paraswap'],
        priceRoute: data, // Needed for building tx
        fromToken,
        toToken,
        amount,
        userAddress,
        slippage,
      };
    } catch (err) {
      console.error(`Paraswap error:`, err.response?.data?.error || err.message);
      return null;
    }
  }

  async buildTransaction(quote, userAddress) {
    const res = await axios.post(`${this.baseUrl}/transactions/${quote.fromToken.chainId}`, {
      srcToken: quote.fromToken.address,
      destToken: quote.toToken.address,
      srcAmount: quote.amount,
      destAmount: quote.toAmountMin,
      priceRoute: quote.priceRoute,
      userAddress,
      partner: 'crypto-wallet-pro',
      srcDecimals: quote.fromToken.decimals,
      destDecimals: quote.toToken.decimals,
    }, { timeout: 15000 });
    
    return {
      to: res.data.to,
      data: res.data.data,
      value: res.data.value || '0',
      gasLimit: res.data.gas || '300000',
      chainId: quote.fromToken.chainId,
    };
  }
}

/**
 * LI.FI Provider - Cross-chain and same-chain swaps
 */
class LiFiProvider {
  constructor() {
    this.name = 'lifi';
    this.baseUrl = 'https://li.quest/v1';
  }

  async getQuote({ fromToken, toToken, amount, userAddress, slippage }) {
    try {
      const res = await axios.get(`${this.baseUrl}/quote`, {
        params: {
          fromChain: fromToken.chainId,
          toChain: toToken.chainId,
          fromToken: fromToken.address,
          toToken: toToken.address,
          fromAmount: amount,
          fromAddress: userAddress,
          toAddress: userAddress,
          slippage: slippage / 100,
          integrator: 'crypto-wallet-pro',
        },
        timeout: 30000,
      });
      
      const data = res.data;
      const estimate = data.estimate;
      
      const gasFeeUSD = estimate.gasCosts?.reduce((sum, c) => sum + parseFloat(c.amountUSD || 0), 0) || 0;
      const protocolFeeUSD = estimate.feeCosts?.reduce((sum, c) => sum + parseFloat(c.amountUSD || 0), 0) || 0;
      
      return {
        toAmount: estimate.toAmount,
        toAmountMin: estimate.toAmountMin || estimate.toAmount,
        exchangeRate: (parseFloat(estimate.toAmount) / Math.pow(10, toToken.decimals)) / 
                      (parseFloat(amount) / Math.pow(10, fromToken.decimals)),
        estimatedGas: estimate.gasCosts?.[0]?.amount || '300000',
        priceImpact: estimate.slippage || 0,
        fees: {
          protocolUSD: protocolFeeUSD,
          gasUSD: gasFeeUSD,
          bridgeUSD: 0,
          totalUSD: gasFeeUSD + protocolFeeUSD,
        },
        route: data.includedSteps?.map(s => `${s.toolDetails?.name || s.tool} (${s.type})`) || ['LI.FI'],
        tx: data.transactionRequest ? {
          to: data.transactionRequest.to,
          data: data.transactionRequest.data,
          value: data.transactionRequest.value || '0',
          gasLimit: data.transactionRequest.gasLimit || '500000',
          chainId: fromToken.chainId,
        } : null,
        fromToken,
        toToken,
        amount,
        userAddress,
        slippage,
      };
    } catch (err) {
      console.error(`LI.FI error:`, err.response?.data?.message || err.message);
      return null;
    }
  }

  async buildTransaction(quote, userAddress) {
    if (quote.tx) return quote.tx;
    
    const res = await axios.get(`${this.baseUrl}/quote`, {
      params: {
        fromChain: quote.fromToken.chainId,
        toChain: quote.toToken.chainId,
        fromToken: quote.fromToken.address,
        toToken: quote.toToken.address,
        fromAmount: quote.amount,
        fromAddress: userAddress,
        toAddress: userAddress,
        slippage: quote.slippage / 100,
        integrator: 'crypto-wallet-pro',
      },
      timeout: 30000,
    });
    
    const tx = res.data.transactionRequest;
    return {
      to: tx.to,
      data: tx.data,
      value: tx.value || '0',
      gasLimit: tx.gasLimit || '500000',
      chainId: quote.fromToken.chainId,
    };
  }
}

/**
 * THORChain Provider - Native BTC swaps
 * Truly decentralized, no KYC, no custody
 */
class THORChainProvider {
  constructor() {
    this.name = 'thorchain';
    this.thornodeUrl = 'https://thornode.ninerealms.com';
  }

  async getQuote({ fromToken, toToken, amount, userAddress, slippage }) {
    try {
      const fromAsset = this.getTHORAsset(fromToken.symbol);
      const toAsset = this.getTHORAsset(toToken.symbol);
      
      if (!fromAsset || !toAsset) return null;
      
      // Convert to THORChain base units (8 decimals)
      const thorAmount = this.toTHORAmount(amount, fromToken.decimals);
      
      const res = await axios.get(`${this.thornodeUrl}/thorchain/quote/swap`, {
        params: {
          from_asset: fromAsset,
          to_asset: toAsset,
          amount: thorAmount,
          destination: userAddress,
          streaming_interval: 1,
        },
        timeout: 15000,
      });
      
      const data = res.data;
      
      // Convert output from THORChain units
      const toAmount = this.fromTHORAmount(data.expected_amount_out, toToken.decimals);
      const feeTotal = parseFloat(data.fees?.total || 0) / 1e8;
      
      return {
        toAmount: toAmount.toString(),
        toAmountMin: Math.floor(toAmount * (1 - slippage / 100)).toString(),
        exchangeRate: toAmount / (parseFloat(amount) / Math.pow(10, fromToken.decimals)),
        estimatedGas: '0',
        priceImpact: data.slippage_bps / 100,
        fees: {
          protocolUSD: feeTotal * 90000, // Rough BTC price
          gasUSD: 0,
          bridgeUSD: 0,
          totalUSD: feeTotal * 90000,
        },
        route: [`THORChain: ${fromAsset} → ${toAsset}`],
        thorData: {
          inboundAddress: data.inbound_address,
          memo: `=:${toAsset}:${userAddress}`,
          expiry: data.expiry,
          router: data.router,
        },
        fromToken,
        toToken,
        amount,
        userAddress,
        slippage,
      };
    } catch (err) {
      console.error(`THORChain error:`, err.response?.data?.error || err.message);
      return null;
    }
  }

  async buildTransaction(quote, userAddress) {
    // For BTC: Return deposit info (user sends BTC to inbound address with memo)
    if (quote.fromToken.symbol === 'BTC') {
      return {
        type: 'btc-deposit',
        to: quote.thorData.inboundAddress,
        memo: quote.thorData.memo,
        value: quote.amount,
        instructions: 'Send BTC to this address with the memo in OP_RETURN',
      };
    }
    
    // For EVM chains: Use THORChain router
    if (quote.thorData.router) {
      // Would encode router.deposit() call here
      return {
        to: quote.thorData.router,
        data: '0x', // Actual encoding needed
        value: quote.amount,
        gasLimit: '300000',
        chainId: quote.fromToken.chainId,
      };
    }
    
    return {
      to: quote.thorData.inboundAddress,
      data: '0x',
      value: quote.amount,
      gasLimit: '21000',
      chainId: quote.fromToken.chainId,
    };
  }

  getTHORAsset(symbol) {
    const assets = {
      BTC: 'BTC.BTC',
      ETH: 'ETH.ETH',
      BNB: 'BNB.BNB',
      AVAX: 'AVAX.AVAX',
      USDT: 'ETH.USDT-0xdAC17F958D2ee523a2206206994597C13D831ec7',
      USDC: 'ETH.USDC-0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    };
    return assets[symbol] || null;
  }

  toTHORAmount(amount, decimals) {
    const value = BigInt(amount);
    if (decimals === 8) return value.toString();
    if (decimals > 8) return (value / BigInt(10 ** (decimals - 8))).toString();
    return (value * BigInt(10 ** (8 - decimals))).toString();
  }

  fromTHORAmount(amount, decimals) {
    const value = BigInt(amount);
    if (decimals === 8) return Number(value);
    if (decimals > 8) return Number(value * BigInt(10 ** (decimals - 8)));
    return Number(value / BigInt(10 ** (8 - decimals)));
  }
}

module.exports = { SwapEngine };

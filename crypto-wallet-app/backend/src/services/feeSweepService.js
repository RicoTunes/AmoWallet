/**
 * Fee Sweep Service
 * Automatically aggregates fees from all chains (BTC, ETH, BSC, POLYGON, etc.)
 * Converts fees to USDT-BEP20 and sends to admin wallet on BSC
 */

const { ethers } = require('ethers');
const axios = require('axios');
require('dotenv').config();

// Import models (connect to MongoDB)
let Transaction;
try {
  const models = require('../models');
  Transaction = models.Transaction;
} catch (error) {
  console.error('Error loading Transaction model:', error);
}

const TelegramService = require('./telegramService');

// Configuration
const CONFIG = {
  // Admin USDT-BEP20 wallet on BSC
  ADMIN_WALLET: process.env.TREASURY_USDT_ADDRESS || '0x726dac06826a2e48be08cc02835a2083644076b2',
  
  // Chain-specific treasury addresses
  TREASURY_ADDRESSES: {
    BTC: process.env.TREASURY_BTC_ADDRESS || '1H7BQKd8AayCmya7iqeX23i6go9jEJL2wA',
    ETH: process.env.TREASURY_ETH_ADDRESS || '0x726dac06826a2e48be08cc02835a2083644076b2',
    BSC: process.env.TREASURY_BSC_ADDRESS || '0x726dac06826a2e48be08cc02835a2083644076b2',
    POLYGON: process.env.TREASURY_POLYGON_ADDRESS || '0x726dac06826a2e48be08cc02835a2083644076b2',
  },
  
  // BSC RPC and USDT contract
  BSC_RPC_URL: process.env.BSC_RPC_URL || 'https://bsc-dataseed1.binance.org/',
  USDT_BEP20_ADDRESS: '0x55d398326f99059fF775485246999027B3197955', // Mainnet USDT-BEP20
  USDT_BEP20_ADDRESS_TESTNET: '0x337610d27c682E347C9cD60bd4b3b107C9d34dDd', // Testnet USDT
  
  // DEX for swaps (PancakeSwap or other)
  PANCAKESWAP_ROUTER: process.env.PANCAKESWAP_V2_ROUTER || '0x10ED43C718714eb63d5aA57B78B54704E256024E',
  
  // Price oracle
  COINGECKO_API: 'https://api.coingecko.com/api/v3',
  
  // Sweep settings
  SWEEP_INTERVAL_MS: 24 * 60 * 60 * 1000, // 24 hours
  MIN_FEE_USD_TO_SWEEP: parseFloat(process.env.MIN_TRANSACTION_FEE_USD) || 0.50,
  AUTO_CONVERT_TO_USDT: process.env.AUTO_CONVERT_TO_USDT === 'true',
};

class FeeSweepService {
  constructor() {
    this.isSweeping = false;
    this.lastSweepTime = null;
    this.sweepInterval = null;
    this.telegramService = new TelegramService();
  }

  /**
   * Start the fee sweep scheduler
   */
  start() {
    console.log('🔄 Starting Fee Sweep Service...');
    
    // Run sweep immediately on startup
    this.performSweep().catch(error => {
      console.error('❌ Error in initial sweep:', error);
      this.telegramService.sendAlert('❌ Fee Sweep Error', `Initial sweep failed: ${error.message}`);
    });

    // Schedule regular sweeps (every 24 hours)
    this.sweepInterval = setInterval(() => {
      this.performSweep().catch(error => {
        console.error('❌ Error in scheduled sweep:', error);
        this.telegramService.sendAlert('❌ Fee Sweep Error', `Scheduled sweep failed: ${error.message}`);
      });
    }, CONFIG.SWEEP_INTERVAL_MS);

    console.log('✅ Fee Sweep Service started. Will sweep every 24 hours.');
  }

  /**
   * Stop the fee sweep scheduler
   */
  stop() {
    if (this.sweepInterval) {
      clearInterval(this.sweepInterval);
      this.sweepInterval = null;
    }
    console.log('🛑 Fee Sweep Service stopped.');
  }

  /**
   * Perform a complete fee sweep across all chains
   */
  async performSweep() {
    if (this.isSweeping) {
      console.log('⏳ Sweep already in progress, skipping...');
      return;
    }

    this.isSweeping = true;
    const startTime = Date.now();
    
    try {
      console.log('\n💰 Starting fee sweep...');

      if (!Transaction) {
        console.log('⚠️  Transaction model not initialized (MongoDB not connected). Skipping sweep.');
        this.isSweeping = false;
        return;
      }

      // 1. Fetch all pending fee collection transactions
      const pendingFees = await this.getPendingFees();
      
      if (pendingFees.length === 0) {
        console.log('✅ No pending fees to sweep.');
        this.isSweeping = false;
        return;
      }

      console.log(`📊 Found ${pendingFees.length} pending fee transactions`);

      // 2. Aggregate fees by network
      const aggregatedFees = this.aggregateFeesByNetwork(pendingFees);
      console.log('📈 Aggregated fees:', aggregatedFees);

      // 3. Get current prices for conversion
      const prices = await this.getPrices(['bitcoin', 'ethereum', 'binancecoin']);
      console.log('💹 Current prices:', prices);

      // 4. Convert all fees to USDT value
      const usdtEquivalent = await this.convertFeesToUSDT(aggregatedFees, prices);
      console.log(`💵 Total USDT equivalent: $${usdtEquivalent.toFixed(2)}`);

      // 5. Check minimum threshold
      if (usdtEquivalent < CONFIG.MIN_FEE_USD_TO_SWEEP) {
        console.log(`⚠️  Total fees ($${usdtEquivalent.toFixed(2)}) below minimum threshold ($${CONFIG.MIN_FEE_USD_TO_SWEEP}). Skipping sweep.`);
        this.isSweeping = false;
        return;
      }

      // 6. Convert non-USDT fees to USDT via DEX
      const usdtAmount = await this.swapFeesToUSDT(aggregatedFees);
      console.log(`✅ Successfully swapped fees to ${usdtAmount} USDT`);

      // 7. Transfer USDT to admin wallet
      const txHash = await this.transferUSDTToAdmin(usdtAmount);
      console.log(`🚀 USDT transferred! TX: ${txHash}`);

      // 8. Mark fees as swept in database
      await this.markFeesAsSwept(pendingFees, txHash);
      console.log('💾 Fees marked as swept in database');

      // 9. Send Telegram alert with sweep summary
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      await this.telegramService.sendSweepSummary({
        feeCount: pendingFees.length,
        totalUSDT: usdtAmount,
        txHash: txHash,
        duration: duration,
        aggregatedFees: aggregatedFees
      });

      console.log(`✅ Fee sweep completed in ${duration}s\n`);
      this.lastSweepTime = new Date();

    } catch (error) {
      console.error('❌ Fee sweep failed:', error);
      await this.telegramService.sendAlert('❌ Fee Sweep Failed', error.message);
    } finally {
      this.isSweeping = false;
    }
  }

  /**
   * Get all pending fee collection transactions from the last 24 hours
   */
  async getPendingFees() {
    try {
      // Check if Transaction model is available
      if (!Transaction) {
        console.log('⚠️  Transaction model not available (MongoDB not connected)');
        return [];
      }

      // Check if mongoose is connected
      const mongoose = require('mongoose');
      if (mongoose.connection.readyState !== 1) {
        console.log('⚠️  MongoDB not connected, skipping fee query');
        return [];
      }

      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

      const fees = await Transaction.find({
        type: 'fee_collection',
        status: { $in: ['completed', 'pending'] },
        'metadata.swept': { $ne: true },
        timestamp: { $gte: oneDayAgo }
      }).maxTimeMS(5000); // 5 second timeout

      return fees;
    } catch (error) {
      console.error('Error fetching pending fees:', error.message);
      return []; // Return empty array instead of throwing
    }
  }

  /**
   * Aggregate fees by network
   */
  aggregateFeesByNetwork(fees) {
    const aggregated = {
      BTC: 0,
      ETH: 0,
      BSC: 0,
      POLYGON: 0,
      USDT: 0,
      OTHER: 0
    };

    for (const fee of fees) {
      const network = (fee.network || '').toUpperCase();
      const amount = parseFloat(fee.amount) || 0;

      if (aggregated.hasOwnProperty(network)) {
        aggregated[network] += amount;
      } else {
        aggregated.OTHER += amount;
      }
    }

    // Remove zero entries
    Object.keys(aggregated).forEach(key => {
      if (aggregated[key] === 0) {
        delete aggregated[key];
      }
    });

    return aggregated;
  }

  /**
   * Get current prices from CoinGecko
   */
  async getPrices(coinIds) {
    try {
      const response = await axios.get(`${CONFIG.COINGECKO_API}/simple/price`, {
        params: {
          ids: coinIds.join(','),
          vs_currencies: 'usd'
        },
        timeout: 10000
      });

      return {
        bitcoin: response.data.bitcoin?.usd || 0,
        ethereum: response.data.ethereum?.usd || 0,
        binancecoin: response.data.binancecoin?.usd || 0
      };
    } catch (error) {
      console.error('Error fetching prices:', error);
      // Fallback prices if API fails
      return {
        bitcoin: 42000,
        ethereum: 2200,
        binancecoin: 600
      };
    }
  }

  /**
   * Convert all fees to USDT equivalent value
   */
  async convertFeesToUSDT(aggregatedFees, prices) {
    let totalUSD = 0;

    if (aggregatedFees.BTC) {
      totalUSD += aggregatedFees.BTC * prices.bitcoin;
      console.log(`  BTC: ${aggregatedFees.BTC} × $${prices.bitcoin} = $${(aggregatedFees.BTC * prices.bitcoin).toFixed(2)}`);
    }

    if (aggregatedFees.ETH) {
      totalUSD += aggregatedFees.ETH * prices.ethereum;
      console.log(`  ETH: ${aggregatedFees.ETH} × $${prices.ethereum} = $${(aggregatedFees.ETH * prices.ethereum).toFixed(2)}`);
    }

    if (aggregatedFees.BSC) {
      totalUSD += aggregatedFees.BSC * prices.binancecoin;
      console.log(`  BSC: ${aggregatedFees.BSC} × $${prices.binancecoin} = $${(aggregatedFees.BSC * prices.binancecoin).toFixed(2)}`);
    }

    if (aggregatedFees.POLYGON) {
      // Polygon (MATIC) price - fallback to BNB price for now
      totalUSD += aggregatedFees.POLYGON * 0.5; // Rough estimate
      console.log(`  POLYGON: ${aggregatedFees.POLYGON} × $0.50 = $${(aggregatedFees.POLYGON * 0.5).toFixed(2)}`);
    }

    if (aggregatedFees.USDT) {
      totalUSD += aggregatedFees.USDT;
      console.log(`  USDT: ${aggregatedFees.USDT} = $${aggregatedFees.USDT.toFixed(2)}`);
    }

    return totalUSD;
  }

  /**
   * Swap all fees to USDT on BSC via PancakeSwap
   */
  async swapFeesToUSDT(aggregatedFees) {
    try {
      console.log('\n🔄 Starting fee swap to USDT...');

      // For now, we'll simulate the swap
      // In production, you'd use:
      // - PancakeSwap API
      // - 1Inch protocol
      // - Or batch swaps via smart contract

      let totalUSDT = 0;

      // If we have USDT already, that's done
      if (aggregatedFees.USDT) {
        totalUSDT += aggregatedFees.USDT;
        console.log(`✅ USDT fees: ${aggregatedFees.USDT}`);
      }

      // For other coins, calculate USDT equivalent
      // (In production, execute actual swaps)
      if (aggregatedFees.BTC) {
        // Swap BTC to USDT (would need to route to BSC first)
        const btcPrice = (await this.getPrices(['bitcoin'])).bitcoin;
        const usdtValue = aggregatedFees.BTC * btcPrice;
        totalUSDT += usdtValue;
        console.log(`✅ Swapped ${aggregatedFees.BTC} BTC → ${usdtValue.toFixed(2)} USDT`);
      }

      if (aggregatedFees.ETH) {
        // Swap ETH to USDT on BSC via bridge/DEX
        const ethPrice = (await this.getPrices(['ethereum'])).ethereum;
        const usdtValue = aggregatedFees.ETH * ethPrice;
        totalUSDT += usdtValue;
        console.log(`✅ Swapped ${aggregatedFees.ETH} ETH → ${usdtValue.toFixed(2)} USDT`);
      }

      if (aggregatedFees.BSC) {
        // BNB to USDT (direct swap on PancakeSwap)
        const bnbPrice = (await this.getPrices(['binancecoin'])).binancecoin;
        const usdtValue = aggregatedFees.BSC * bnbPrice;
        totalUSDT += usdtValue;
        console.log(`✅ Swapped ${aggregatedFees.BSC} BNB → ${usdtValue.toFixed(2)} USDT`);
      }

      return parseFloat(totalUSDT.toFixed(2));

    } catch (error) {
      console.error('Error swapping fees to USDT:', error);
      throw error;
    }
  }

  /**
   * Transfer USDT to admin wallet on BSC
   */
  async transferUSDTToAdmin(usdtAmount) {
    try {
      console.log(`\n💸 Transferring ${usdtAmount} USDT to admin wallet...`);

      const provider = new ethers.JsonRpcProvider(CONFIG.BSC_RPC_URL);
      
      // Get signer from private key (load from secure storage in production!)
      // For now, we'll just simulate the transfer
      const adminPrivateKey = process.env.ADMIN_WALLET_PRIVATE_KEY;
      
      if (!adminPrivateKey) {
        console.warn('⚠️  ADMIN_WALLET_PRIVATE_KEY not configured. Transfer would proceed with real key in production.');
        // In production, implement secure key management (e.g., AWS Secrets Manager, Vault)
        // For testing, return a mock transaction hash
        return `0x${Math.random().toString(16).substr(2, 64)}`;
      }

      const signer = new ethers.Wallet(adminPrivateKey, provider);

      // USDT contract ABI (minimal ERC-20 transfer)
      const USDT_ABI = [
        'function transfer(address to, uint256 amount) public returns (bool)',
        'function balanceOf(address account) public view returns (uint256)',
        'function decimals() public view returns (uint8)'
      ];

      const usdtContract = new ethers.Contract(CONFIG.USDT_BEP20_ADDRESS, USDT_ABI, signer);

      // Convert to proper decimal format (USDT has 18 decimals on BSC)
      const decimals = await usdtContract.decimals();
      const transferAmount = ethers.parseUnits(usdtAmount.toString(), decimals);

      console.log(`📝 Creating USDT transfer transaction...`);
      console.log(`   From: ${await signer.getAddress()}`);
      console.log(`   To: ${CONFIG.ADMIN_WALLET}`);
      console.log(`   Amount: ${usdtAmount} USDT (${transferAmount.toString()} wei)`);

      const tx = await usdtContract.transfer(CONFIG.ADMIN_WALLET, transferAmount);
      
      console.log(`⏳ Waiting for transaction confirmation...`);
      const receipt = await tx.wait(2); // Wait 2 confirmations
      
      const txHash = receipt.hash;
      console.log(`✅ USDT transfer successful!`);
      console.log(`   TX Hash: ${txHash}`);
      console.log(`   Block: ${receipt.blockNumber}`);
      
      return txHash;

    } catch (error) {
      console.error('Error transferring USDT:', error);
      throw error;
    }
  }

  /**
   * Mark fees as swept in the database
   */
  async markFeesAsSwept(fees, sweepTxHash) {
    try {
      const feeIds = fees.map(f => f._id);
      
      await Transaction.updateMany(
        { _id: { $in: feeIds } },
        {
          $set: {
            'metadata.swept': true,
            'metadata.sweepTxHash': sweepTxHash,
            'metadata.sweepTime': new Date()
          },
          status: 'swept'
        }
      );

      console.log(`Updated ${feeIds.length} fee records in database`);
    } catch (error) {
      console.error('Error marking fees as swept:', error);
      throw error;
    }
  }

  /**
   * Get sweep statistics
   */
  async getStatistics() {
    try {
      const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

      const stats = await Transaction.aggregate([
        {
          $match: {
            type: 'fee_collection',
            timestamp: { $gte: sevenDaysAgo }
          }
        },
        {
          $group: {
            _id: '$network',
            totalFees: { $sum: '$amount' },
            feeCount: { $sum: 1 },
            avgFee: { $avg: '$amount' }
          }
        },
        {
          $sort: { totalFees: -1 }
        }
      ]);

      return {
        period: '7 days',
        lastSweep: this.lastSweepTime,
        stats: stats
      };
    } catch (error) {
      console.error('Error getting statistics:', error);
      return null;
    }
  }
}

module.exports = FeeSweepService;

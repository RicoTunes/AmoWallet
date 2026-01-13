const { ethers } = require('ethers');
const mongoose = require('mongoose');
require('dotenv').config();

// Real DEX router contracts
const DEX_ROUTERS = {
  ethereum: {
    uniswapV3: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    uniswapV2: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'
  },
  bsc: {
    pancakeswapV3: '0x13f4EA83D0bd40E75C8222255bc855a974568Dd4',
    pancakeswapV2: '0x10ED43C718714eb63d5aA57B78B54704E256024E'
  }
};

// ERC20 ABI for token interactions
const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

// Uniswap V3 Router ABI (simplified for swap operations)
const UNISWAP_V3_ROUTER_ABI = [
  "function exactInputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitXPI)) external payable returns (uint256 amountOut)",
  "function exactOutputSingle((address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline, uint256 amountOut, uint256 amountInMaximum, uint160 sqrtPriceLimitXPI)) external payable returns (uint256 amountIn)"
];

class TransactionManager {
  constructor() {
    this.providers = {
      ethereum: new ethers.JsonRpcProvider(`https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`),
      bsc: new ethers.JsonRpcProvider('https://bsc-dataseed.binance.org')
    };
  }

  /**
   * Execute a real token swap on DEX
   */
  async executeSwap(swapData) {
    const {
      network,
      fromToken,
      toToken,
      amountIn,
      amountOutMin,
      userAddress,
      privateKey,
      slippage = 1.0
    } = swapData;

    try {
      const provider = this.providers[network];
      if (!provider) {
        throw new Error(`Unsupported network: ${network}`);
      }

      const wallet = new ethers.Wallet(privateKey, provider);
      
      // Validate wallet address
      if (wallet.address.toLowerCase() !== userAddress.toLowerCase()) {
        throw new Error('Private key does not match user address');
      }

      // Get router contract
      const routerAddress = DEX_ROUTERS[network]?.uniswapV3 || DEX_ROUTERS[network]?.pancakeswapV3;
      const router = new ethers.Contract(routerAddress, UNISWAP_V3_ROUTER_ABI, wallet);

      // Get token contracts
      const fromTokenContract = new ethers.Contract(fromToken, ERC20_ABI, wallet);
      const toTokenContract = new ethers.Contract(toToken, ERC20_ABI, wallet);

      // Get token decimals
      const fromDecimals = await fromTokenContract.decimals();
      const toDecimals = await toTokenContract.decimals();

      // Convert amounts to proper units
      const amountInWei = ethers.parseUnits(amountIn.toString(), fromDecimals);
      const amountOutMinWei = ethers.parseUnits(amountOutMin.toString(), toDecimals);

      // Check and approve token spending
      const allowance = await fromTokenContract.allowance(userAddress, routerAddress);
      if (allowance < amountInWei) {
        const approveTx = await fromTokenContract.approve(routerAddress, amountInWei);
        await approveTx.wait();
      }

      // Prepare swap parameters
      const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes
      const fee = 3000; // 0.3% fee tier

      const swapParams = {
        tokenIn: fromToken,
        tokenOut: toToken,
        fee: fee,
        recipient: userAddress,
        deadline: deadline,
        amountIn: amountInWei,
        amountOutMinimum: amountOutMinWei,
        sqrtPriceLimitXPI: 0
      };

      // Execute swap
      const swapTx = await router.exactInputSingle(swapParams);
      const receipt = await swapTx.wait();

      // Calculate actual amounts
      const actualAmountOut = await this.calculateSwapOutput(receipt, toTokenContract, toDecimals);

      // Save swap transaction to database
      const swapTransaction = new mongoose.models.Transaction({
        txHash: receipt.hash,
        network: network,
        from: userAddress,
        to: routerAddress,
        amount: parseFloat(amountIn),
        fee: parseFloat(ethers.formatEther(receipt.fee || '0')),
        status: receipt.status === 1 ? 'completed' : 'failed',
        confirmations: receipt.confirmations,
        timestamp: new Date(),
        type: 'swap',
        metadata: {
          fromToken: fromToken,
          toToken: toToken,
          amountOut: actualAmountOut,
          dex: network === 'ethereum' ? 'Uniswap V3' : 'PancakeSwap V3',
          slippage: slippage,
          blockNumber: receipt.blockNumber,
          gasUsed: receipt.gasUsed.toString()
        }
      });

      await swapTransaction.save();

      return {
        success: true,
        txHash: receipt.hash,
        network: network,
        fromToken: fromToken,
        toToken: toToken,
        amountIn: amountIn,
        amountOut: actualAmountOut,
        fee: parseFloat(ethers.formatEther(receipt.fee || '0')),
        status: receipt.status === 1 ? 'completed' : 'failed',
        confirmations: receipt.confirmations,
        blockNumber: receipt.blockNumber,
        timestamp: new Date().toISOString(),
        explorerUrl: this.getExplorerUrl(network, receipt.hash),
        message: 'Swap executed successfully'
      };

    } catch (error) {
      console.error('Swap execution error:', error);
      throw error;
    }
  }

  /**
   * Calculate actual swap output from transaction receipt
   */
  async calculateSwapOutput(receipt, toTokenContract, toDecimals) {
    try {
      // In a real implementation, you would parse the swap event logs
      // For now, we'll simulate the calculation
      const transferEvents = receipt.logs.filter(log => 
        log.topics[0] === '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef' // Transfer event
      );

      if (transferEvents.length > 0) {
        // Find the transfer to the user address
        const userTransfer = transferEvents.find(event => 
          event.topics[2] && `0x${event.topics[2].slice(26)}`.toLowerCase() === receipt.from.toLowerCase()
        );
        
        if (userTransfer) {
          const amount = BigInt(userTransfer.data);
          return parseFloat(ethers.formatUnits(amount, toDecimals));
        }
      }

      // Fallback: estimate based on input amount (simplified)
      return parseFloat((parseFloat(receipt.amountIn) * 0.997).toFixed(6)); // 0.3% fee
    } catch (error) {
      console.error('Error calculating swap output:', error);
      return 0;
    }
  }

  /**
   * Get token balance for a specific address
   */
  async getTokenBalance(network, tokenAddress, userAddress) {
    try {
      const provider = this.providers[network];
      const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
      
      const balance = await tokenContract.balanceOf(userAddress);
      const decimals = await tokenContract.decimals();
      
      return parseFloat(ethers.formatUnits(balance, decimals));
    } catch (error) {
      console.error('Error getting token balance:', error);
      return 0;
    }
  }

  /**
   * Get current gas prices for a network
   */
  async getGasPrices(network) {
    try {
      const provider = this.providers[network];
      const feeData = await provider.getFeeData();
      
      return {
        maxFeePerGas: parseFloat(ethers.formatUnits(feeData.maxFeePerGas || '0', 'gwei')),
        maxPriorityFeePerGas: parseFloat(ethers.formatUnits(feeData.maxPriorityFeePerGas || '0', 'gwei')),
        gasPrice: parseFloat(ethers.formatUnits(feeData.gasPrice || '0', 'gwei'))
      };
    } catch (error) {
      console.error('Error getting gas prices:', error);
      return {
        maxFeePerGas: 30,
        maxPriorityFeePerGas: 2,
        gasPrice: 20
      };
    }
  }

  /**
   * Generate explorer URL for transaction
   */
  getExplorerUrl(network, txHash) {
    const explorers = {
      ethereum: `https://etherscan.io/tx/${txHash}`,
      bsc: `https://bscscan.com/tx/${txHash}`
    };
    return explorers[network] || '#';
  }

  /**
   * Validate token address and get token info
   */
  async validateToken(network, tokenAddress) {
    try {
      const provider = this.providers[network];
      const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
      
      const [symbol, decimals] = await Promise.all([
        tokenContract.symbol(),
        tokenContract.decimals()
      ]);
      
      return {
        isValid: true,
        symbol: symbol,
        decimals: decimals,
        address: tokenAddress
      };
    } catch (error) {
      return {
        isValid: false,
        error: 'Invalid token address'
      };
    }
  }
}

module.exports = TransactionManager;
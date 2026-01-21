/**
 * Database Models with Enhanced Validation
 * Comprehensive MongoDB schemas for production-ready transaction and wallet management
 */

const mongoose = require('mongoose');

// Lazy load ethers to avoid startup issues
let ethers = null;
const getEthers = () => {
  if (!ethers) {
    try {
      ethers = require('ethers');
    } catch (e) {
      console.warn('ethers not available:', e.message);
    }
  }
  return ethers;
};

// Supported blockchain networks
const SUPPORTED_NETWORKS = ['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism', 'avalanche', 'bitcoin', 'litecoin', 'dogecoin', 'tron', 'ripple', 'solana'];

// Transaction validation middleware
const validateEthereumAddress = (address) => {
  // Use regex validation (ethers.isAddress can fail in some environments)
  if (typeof address !== 'string') return false;
  if (!/^0x[a-fA-F0-9]{40}$/.test(address)) return false;
  return true;
};

const validateBitcoinAddress = (address) => {
  // Basic Bitcoin address validation (P2PKH, P2SH, Bech32)
  return /^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$|^bc1[a-z0-9]{39,59}$/.test(address);
};

const validateAddress = (network, address) => {
  switch (network.toLowerCase()) {
    case 'ethereum':
    case 'bsc':
    case 'polygon':
    case 'arbitrum':
    case 'optimism':
    case 'avalanche':
      return validateEthereumAddress(address);
    case 'bitcoin':
    case 'litecoin':
      return validateBitcoinAddress(address);
    case 'dogecoin':
      return /^[D][a-km-zA-HJ-NP-Z1-9]{25,34}$/.test(address);
    case 'solana':
      return /^[1-9A-HJ-NP-Za-km-z]{44}$/.test(address);
    case 'tron':
      return /^T[a-zA-Z0-9]{33}$/.test(address);
    case 'ripple':
      return /^r[a-zA-Z0-9]{24,34}$/.test(address);
    default:
      return false;
  }
};

const validateTransactionHash = (hash) => {
  return /^0x[a-fA-F0-9]{64}$/.test(hash) || /^[a-fA-F0-9]{64}$/.test(hash);
};

// Enhanced Transaction Schema
const transactionSchema = new mongoose.Schema(
  {
    // Basic transaction info
    txHash: {
      type: String,
      required: [true, 'Transaction hash is required'],
      unique: true,
      sparse: true,
      validate: {
        validator: function(v) {
          return validateTransactionHash(v);
        },
        message: 'Invalid transaction hash format'
      }
    },
    
    network: {
      type: String,
      required: [true, 'Network is required'],
      enum: {
        values: SUPPORTED_NETWORKS,
        message: `Network must be one of: ${SUPPORTED_NETWORKS.join(', ')}`
      },
      lowercase: true,
      index: true
    },
    
    // Addresses with validation per network
    from: {
      type: String,
      required: [true, 'From address is required'],
      index: true,
      validate: {
        validator: function(v) {
          return validateAddress(this.network, v);
        },
        message: 'Invalid "from" address for the specified network'
      }
    },
    
    to: {
      type: String,
      required: [true, 'To address is required'],
      index: true,
      validate: {
        validator: function(v) {
          return validateAddress(this.network, v);
        },
        message: 'Invalid "to" address for the specified network'
      }
    },
    
    // Amount and fee with precision
    amount: {
      type: mongoose.Decimal128,
      required: [true, 'Amount is required'],
      validate: {
        validator: function(v) {
          return parseFloat(v) > 0;
        },
        message: 'Amount must be greater than 0'
      }
    },
    
    fee: {
      type: mongoose.Decimal128,
      required: [true, 'Fee is required'],
      validate: {
        validator: function(v) {
          return parseFloat(v) >= 0;
        },
        message: 'Fee cannot be negative'
      }
    },
    
    // Gas/blockchain specific info
    gasPrice: {
      type: String,
      default: null
    },
    
    gasUsed: {
      type: String,
      default: null
    },
    
    gasLimit: {
      type: String,
      default: null
    },
    
    // Transaction status
    status: {
      type: String,
      enum: {
        values: ['pending', 'confirmed', 'failed', 'cancelled'],
        message: 'Status must be one of: pending, confirmed, failed, cancelled'
      },
      default: 'pending',
      index: true
    },
    
    // Block confirmation details
    blockNumber: {
      type: Number,
      default: null
    },
    
    blockHash: {
      type: String,
      default: null
    },
    
    confirmations: {
      type: Number,
      default: 0,
      min: 0
    },
    
    // Transaction type
    type: {
      type: String,
      enum: {
        values: ['send', 'receive', 'swap', 'contract'],
        message: 'Type must be one of: send, receive, swap, contract'
      },
      required: true,
      index: true
    },
    
    // Token transfer info (for ERC20, BEP20, etc.)
    token: {
      contract: {
        type: String,
        default: null
      },
      symbol: {
        type: String,
        default: null
      },
      decimals: {
        type: Number,
        default: 18
      },
      amount: {
        type: String,
        default: null
      }
    },
    
    // Swap specific info
    swap: {
      fromToken: String,
      toToken: String,
      fromAmount: String,
      toAmount: String,
      dex: String,
      slippage: Number
    },
    
    // Additional metadata
    metadata: {
      nonce: String,
      input: String,
      output: String,
      chain_id: Number,
      replacedBy: String, // if replaced by another tx
      replaces: String    // if replaces another tx
    },
    
    // Timestamps
    createdAt: {
      type: Date,
      default: Date.now,
      index: true
    },
    
    confirmedAt: {
      type: Date,
      default: null
    },
    
    updatedAt: {
      type: Date,
      default: Date.now
    }
  },
  {
    collection: 'transactions',
    timestamps: true,
    toJSON: { virtuals: true },
    toObject: { virtuals: true }
  }
);

// Compound indexes for efficient queries
transactionSchema.index({ network: 1, from: 1, createdAt: -1 });
transactionSchema.index({ network: 1, to: 1, createdAt: -1 });
transactionSchema.index({ network: 1, status: 1, createdAt: -1 });
transactionSchema.index({ from: 1, to: 1 });

// Virtual for display amount
transactionSchema.virtual('displayAmount').get(function() {
  return this.amount ? parseFloat(this.amount.toString()).toFixed(8) : '0';
});

// Virtual for display fee
transactionSchema.virtual('displayFee').get(function() {
  return this.fee ? parseFloat(this.fee.toString()).toFixed(8) : '0';
});

// Pre-save hook for validation
transactionSchema.pre('save', async function(next) {
  // Ensure from and to are different for send/receive transactions
  if (['send', 'receive'].includes(this.type)) {
    if (this.from.toLowerCase() === this.to.toLowerCase()) {
      throw new Error('From and To addresses cannot be the same for send/receive transactions');
    }
  }
  
  // Validate amount is not absurdly large
  const amount = parseFloat(this.amount.toString());
  if (amount > 1e10) {
    throw new Error('Amount exceeds maximum transaction limit');
  }
  
  next();
});

// Enhanced Wallet Schema
const walletSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User ID is required'],
      index: true
    },
    
    network: {
      type: String,
      required: [true, 'Network is required'],
      enum: {
        values: SUPPORTED_NETWORKS,
        message: `Network must be one of: ${SUPPORTED_NETWORKS.join(', ')}`
      },
      lowercase: true
    },
    
    address: {
      type: String,
      required: [true, 'Address is required'],
      index: true,
      validate: {
        validator: function(v) {
          return validateAddress(this.network, v);
        },
        message: 'Invalid address for the specified network'
      }
    },
    
    label: {
      type: String,
      default: null,
      maxlength: 100
    },
    
    isDefault: {
      type: Boolean,
      default: false
    },
    
    isHardware: {
      type: Boolean,
      default: false
    },
    
    // Balance tracking (cached)
    balance: {
      type: mongoose.Decimal128,
      default: 0
    },
    
    balanceUpdatedAt: {
      type: Date,
      default: null
    },
    
    // Tokens held in this wallet
    tokens: [{
      contract: String,
      symbol: String,
      balance: String,
      decimals: Number,
      updatedAt: Date
    }],
    
    createdAt: {
      type: Date,
      default: Date.now,
      index: true
    },
    
    updatedAt: {
      type: Date,
      default: Date.now
    }
  },
  {
    collection: 'wallets',
    timestamps: true
  }
);

// Compound index for user + network uniqueness
walletSchema.index({ userId: 1, network: 1, address: 1 }, { unique: true });
walletSchema.index({ userId: 1, isDefault: 1 });

// Transaction Fee Cache Schema (for network fee suggestions)
const feeCacheSchema = new mongoose.Schema(
  {
    network: {
      type: String,
      required: true,
      enum: SUPPORTED_NETWORKS,
      index: true
    },
    
    gasPrice: {
      type: String,
      required: true
    },
    
    baseFee: {
      type: String,
      default: null
    },
    
    slow: {
      type: String,
      default: null
    },
    
    standard: {
      type: String,
      default: null
    },
    
    fast: {
      type: String,
      default: null
    },
    
    instant: {
      type: String,
      default: null
    },
    
    updatedAt: {
      type: Date,
      default: Date.now,
      expires: 600 // Auto-delete after 10 minutes
    }
  },
  {
    collection: 'feeCaches',
    timestamps: false
  }
);

// Index for efficient lookups
feeCacheSchema.index({ network: 1, updatedAt: -1 });

// API Rate Limit Schema (for per-wallet rate limiting)
const rateLimitSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    
    endpoint: {
      type: String,
      required: true
    },
    
    count: {
      type: Number,
      default: 1
    },
    
    resetAt: {
      type: Date,
      required: true,
      index: { expires: 3600 } // Auto-delete after 1 hour
    }
  },
  {
    collection: 'rateLimits',
    timestamps: false
  }
);

rateLimitSchema.index({ userId: 1, endpoint: 1 });

// Create models (check if already exists to avoid "Cannot overwrite model" error)
const Transaction = mongoose.models.Transaction || mongoose.model('Transaction', transactionSchema);
const Wallet = mongoose.models.Wallet || mongoose.model('Wallet', walletSchema);
const FeeCache = mongoose.models.FeeCache || mongoose.model('FeeCache', feeCacheSchema);
const RateLimit = mongoose.models.RateLimit || mongoose.model('RateLimit', rateLimitSchema);

// Export everything
module.exports = {
  Transaction,
  Wallet,
  FeeCache,
  RateLimit,
  schemas: {
    transactionSchema,
    walletSchema,
    feeCacheSchema,
    rateLimitSchema
  },
  validators: {
    validateEthereumAddress,
    validateBitcoinAddress,
    validateAddress,
    validateTransactionHash
  },
  constants: {
    SUPPORTED_NETWORKS
  }
};

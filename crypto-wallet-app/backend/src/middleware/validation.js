iys/**
 * Enhanced Validation Middleware
 * Comprehensive input validation and sanitization for blockchain operations
 */

const { body, param, validationResult, query } = require('express-validator');
const { ethers } = require('ethers');
const { validators } = require('../models');

// Custom validation functions
const validateNetworkParam = param('network')
  .isString()
  .toLowerCase()
  .isIn(['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism', 'avalanche', 'bitcoin', 'litecoin', 'dogecoin', 'tron', 'ripple', 'solana'])
  .withMessage('Invalid network');

const validateAddressParam = param('address')
  .isString()
  .trim()
  .custom((value, { req }) => {
    const network = req.params.network?.toLowerCase();
    if (!validators.validateAddress(network, value)) {
      throw new Error(`Invalid ${network} address format`);
    }
    return true;
  });

const validateAddressBody = (fieldName = 'address') => {
  return body(fieldName)
    .isString()
    .trim()
    .custom((value, { req }) => {
      const network = req.body.network?.toLowerCase();
      if (network && !validators.validateAddress(network, value)) {
        throw new Error(`Invalid ${network} address format`);
      }
      return true;
    });
};

const validateAmount = (fieldName = 'amount') => {
  return body(fieldName)
    .isFloat({ min: 0.00000001, max: 1e10 })
    .withMessage('Amount must be a positive number between 0.00000001 and 10,000,000,000')
    .toFloat();
};

const validateSlippage = () => {
  return body('slippage')
    .optional()
    .isFloat({ min: 0.1, max: 50 })
    .withMessage('Slippage must be between 0.1% and 50%')
    .toFloat();
};

const validatePrivateKey = () => {
  return body('privateKey')
    .isString()
    .trim()
    .matches(/^[a-fA-F0-9]{64}$/)
    .withMessage('Invalid private key format (must be 64 hex characters)')
    .custom((value) => {
      try {
        // Verify it's a valid private key by attempting to create a wallet
        new ethers.Wallet(value);
        return true;
      } catch (error) {
        throw new Error('Invalid private key');
      }
    });
};

// Validation chain builders
const validateBalanceRequest = () => {
  return [
    validateNetworkParam,
    validateAddressParam,
    handleValidationErrors
  ];
};

const validateTransactionRequest = () => {
  return [
    body('network')
      .isString()
      .toLowerCase()
      .isIn(['ethereum', 'bsc', 'polygon', 'arbitrum', 'optimism', 'avalanche', 'bitcoin', 'litecoin', 'dogecoin', 'tron', 'ripple', 'solana'])
      .withMessage('Invalid network'),
    body('fromAddress')
      .isString()
      .trim()
      .custom((value, { req }) => {
        if (!validators.validateAddress(req.body.network?.toLowerCase(), value)) {
          throw new Error('Invalid from address');
        }
        return true;
      }),
    body('toAddress')
      .isString()
      .trim()
      .custom((value, { req }) => {
        if (!validators.validateAddress(req.body.network?.toLowerCase(), value)) {
          throw new Error('Invalid to address');
        }
        return true;
      }),
    validateAmount('amount'),
    body('data')
      .optional()
      .isString()
      .matches(/^0x[a-fA-F0-9]*$/)
      .withMessage('Invalid transaction data format'),
    handleValidationErrors
  ];
};

const validateSwapRequest = () => {
  return [
    body('fromCoin')
      .isString()
      .uppercase()
      .isIn(['BTC', 'ETH', 'BNB', 'USDT', 'USDC', 'DAI', 'LTC', 'DOGE', 'XRP', 'SOL'])
      .withMessage('Invalid from coin'),
    body('toCoin')
      .isString()
      .uppercase()
      .isIn(['BTC', 'ETH', 'BNB', 'USDT', 'USDC', 'DAI', 'LTC', 'DOGE', 'XRP', 'SOL'])
      .withMessage('Invalid to coin')
      .custom((value, { req }) => {
        if (value === req.body.fromCoin) {
          throw new Error('From and to coins must be different');
        }
        return true;
      }),
    validateAmount('amount'),
    validateSlippage(),
    body('userAddress')
      .isString()
      .trim()
      .custom((value) => {
        if (!ethers.isAddress(value)) {
          throw new Error('Invalid user address');
        }
        return true;
      }),
    handleValidationErrors
  ];
};

const validateWalletGeneration = () => {
  return [
    body('network')
      .optional()
      .isString()
      .toLowerCase()
      .isIn(['ethereum', 'bsc', 'polygon', 'bitcoin', 'solana', 'tron'])
      .withMessage('Invalid network'),
    handleValidationErrors
  ];
};

const validateSignMessage = () => {
  return [
    validatePrivateKey(),
    body('message')
      .isString()
      .trim()
      .notEmpty()
      .withMessage('Message is required')
      .isLength({ max: 10000 })
      .withMessage('Message cannot exceed 10000 characters'),
    handleValidationErrors
  ];
};

const validateVerifySignature = () => {
  return [
    body('publicKey')
      .isString()
      .trim()
      .matches(/^[a-fA-F0-9]{64,130}$/)
      .withMessage('Invalid public key format'),
    body('message')
      .isString()
      .trim()
      .notEmpty()
      .withMessage('Message is required')
      .isLength({ max: 10000 })
      .withMessage('Message cannot exceed 10000 characters'),
    body('signature')
      .isString()
      .trim()
      .matches(/^[a-fA-F0-9]{128,}$/)
      .withMessage('Invalid signature format'),
    handleValidationErrors
  ];
};

// Error handling middleware
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Validation failed',
      details: errors.array().map(err => ({
        field: err.param,
        message: err.msg
      }))
    });
  }
  next();
};

// Rate limiting validation
const validateRateLimit = (req, res, next) => {
  const clientId = req.user?.id || req.ip;
  const endpoint = req.path;
  const windowMs = 60000; // 1 minute
  const maxRequests = 30;

  // This would typically use Redis for distributed systems
  // For now, using in-memory cache
  if (!global.rateLimitCache) {
    global.rateLimitCache = {};
  }

  const key = `${clientId}:${endpoint}`;
  const now = Date.now();

  if (!global.rateLimitCache[key]) {
    global.rateLimitCache[key] = { count: 0, resetAt: now + windowMs };
  }

  const record = global.rateLimitCache[key];

  if (now > record.resetAt) {
    record.count = 0;
    record.resetAt = now + windowMs;
  }

  record.count++;

  if (record.count > maxRequests) {
    return res.status(429).json({
      success: false,
      error: 'Rate limit exceeded',
      retryAfter: Math.ceil((record.resetAt - now) / 1000)
    });
  }

  res.set('X-RateLimit-Limit', maxRequests);
  res.set('X-RateLimit-Remaining', maxRequests - record.count);
  res.set('X-RateLimit-Reset', Math.ceil(record.resetAt / 1000));

  next();
};

// Sanitization helpers
const sanitizeAddress = (address) => {
  return address.trim().toLowerCase();
};

const sanitizeAmount = (amount) => {
  return parseFloat(amount).toString();
};

// Export all validation functions
module.exports = {
  validateNetworkParam,
  validateAddressParam,
  validateAddressBody,
  validateAmount,
  validateSlippage,
  validatePrivateKey,
  validateBalanceRequest,
  validateTransactionRequest,
  validateSwapRequest,
  validateWalletGeneration,
  validateSignMessage,
  validateVerifySignature,
  handleValidationErrors,
  validateRateLimit,
  sanitizeAddress,
  sanitizeAmount
};

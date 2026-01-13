const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const { walletCreationLimiter, strictLimiter, apiLimiter } = require('../middleware/rateLimiter');
const RustCrypto = require('../lib/rust-crypto');
const PythonCrypto = require('../lib/python-client');

const USE_PY = process.env.USE_PYTHON_CRYPTO === '1';

function getCrypto() {
  return USE_PY ? PythonCrypto : RustCrypto;
}

// Security middleware for wallet routes
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

// Generate new wallet with strict rate limiting
router.post('/generate', walletCreationLimiter, [
  // Validate user agent to prevent automated requests
  (req, res, next) => {
    const userAgent = req.get('User-Agent');
    if (!userAgent || userAgent.length < 10) {
      return res.status(400).json({
        success: false,
        error: 'Invalid request'
      });
    }
    next();
  }
], async (req, res) => {
  try {
    const keypair = await getCrypto().generateKeypair();
    
    // Log generation without exposing sensitive data
    console.log('Wallet generated successfully for IP:', req.ip);
    
    res.json({
      success: true,
      wallet: {
        privateKey: keypair.privateKey,
        publicKey: keypair.publicKey
      }
    });
  } catch (error) {
    console.error('Wallet generation error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to generate wallet'
    });
  }
});

// Sign message
router.post('/sign', apiLimiter, [
  body('privateKey').isString().isLength({ min: 64, max: 64 }).matches(/^[a-fA-F0-9]+$/),
  body('message').isString().notEmpty().isLength({ max: 10000 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Invalid input parameters'
    });
  }

  try {
    const { privateKey, message } = req.body;
    
    // Additional security: limit message size and prevent injection
    if (message.length > 10000) {
      return res.status(400).json({
        success: false,
        error: 'Message too long'
      });
    }
    
    const signature = await getCrypto().signMessage(privateKey, message);
    
    // Log without sensitive data
    console.log('Message signed successfully for IP:', req.ip);
    
    res.json({
      success: true,
      signature
    });
  } catch (error) {
    console.error('Message signing error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to sign message'
    });
  }
});

// Verify signature
router.post('/verify', apiLimiter, [
  body('publicKey').isString().matches(/^[a-fA-F0-9]+$/),
  body('message').isString().notEmpty().isLength({ max: 10000 }),
  body('signature').isString().matches(/^[a-fA-F0-9]+$/)
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Invalid input parameters'
    });
  }

  try {
    const { publicKey, message, signature } = req.body;
    
    // Additional input validation
    if (publicKey.length < 64 || publicKey.length > 130) {
      return res.status(400).json({
        success: false,
        error: 'Invalid public key format'
      });
    }
    
    if (signature.length < 128 || signature.length > 144) {
      return res.status(400).json({
        success: false,
        error: 'Invalid signature format'
      });
    }
    
    const isValid = await getCrypto().verifySignature(publicKey, message, signature);
    
    res.json({
      success: true,
      isValid
    });
  } catch (error) {
    console.error('Signature verification error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to verify signature'
    });
  }
});

module.exports = router;
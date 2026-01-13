const crypto = require('crypto');
const rateLimit = require('express-rate-limit');

/**
 * API Authentication Middleware
 * Implements API key verification and HMAC-SHA256 request signing
 * 
 * Security Features:
 * - API key authentication
 * - Request signature verification (HMAC-SHA256)
 * - Timestamp validation (prevents replay attacks)
 * - Nonce tracking (prevents duplicate requests)
 * - Rate limiting per API key
 */

// In-memory storage (in production, use database)
const apiKeys = new Map();
const usedNonces = new Map(); // Store nonces with expiry
const keyUsageStats = new Map();

// Configuration
const SIGNATURE_VALIDITY_WINDOW = 5 * 60 * 1000; // 5 minutes
const NONCE_CLEANUP_INTERVAL = 10 * 60 * 1000; // 10 minutes

/**
 * Generate a new API key
 * @returns {Object} { apiKey, apiSecret }
 */
function generateAPIKey() {
  const apiKey = 'key_' + crypto.randomBytes(16).toString('hex');
  const apiSecret = crypto.randomBytes(32).toString('hex');
  
  const keyData = {
    apiKey,
    apiSecret,
    createdAt: new Date(),
    lastUsed: null,
    usageCount: 0,
    isActive: true,
    expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days
  };
  
  apiKeys.set(apiKey, keyData);
  keyUsageStats.set(apiKey, {
    requestCount: 0,
    lastRequest: null,
  });
  
  console.log('✅ Generated new API key:', apiKey);
  
  return { apiKey, apiSecret };
}

/**
 * Verify HMAC-SHA256 signature
 * @param {string} method - HTTP method
 * @param {string} path - Request path
 * @param {string} timestamp - Request timestamp
 * @param {string} nonce - Unique request identifier
 * @param {string} body - Request body (JSON string)
 * @param {string} signature - HMAC signature to verify
 * @param {string} apiSecret - API secret key
 * @returns {boolean}
 */
function verifySignature(method, path, timestamp, nonce, body, signature, apiSecret) {
  // Construct the message to sign (same format as client)
  const message = `${method}${path}${timestamp}${nonce}${body}`;
  
  // Calculate expected signature
  const expectedSignature = crypto
    .createHmac('sha256', apiSecret)
    .update(message)
    .digest('hex');
  
  // Constant-time comparison to prevent timing attacks
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expectedSignature)
  );
}

/**
 * Clean up expired nonces
 */
function cleanupExpiredNonces() {
  const now = Date.now();
  for (const [nonce, expiry] of usedNonces.entries()) {
    if (now > expiry) {
      usedNonces.delete(nonce);
    }
  }
}

// Start periodic nonce cleanup
setInterval(cleanupExpiredNonces, NONCE_CLEANUP_INTERVAL);

/**
 * Authentication middleware
 */
function authenticate(req, res, next) {
  try {
    // Extract headers
    const apiKey = req.headers['x-api-key'];
    const signature = req.headers['x-signature'];
    const timestamp = req.headers['x-timestamp'];
    const nonce = req.headers['x-nonce'];
    
    // Validate required headers
    if (!apiKey || !signature || !timestamp || !nonce) {
      return res.status(401).json({
        success: false,
        error: 'Missing authentication headers',
        required: ['X-API-Key', 'X-Signature', 'X-Timestamp', 'X-Nonce'],
      });
    }
    
    // Check if API key exists and is active
    const keyData = apiKeys.get(apiKey);
    if (!keyData) {
      return res.status(401).json({
        success: false,
        error: 'Invalid API key',
      });
    }
    
    if (!keyData.isActive) {
      return res.status(401).json({
        success: false,
        error: 'API key is deactivated',
      });
    }
    
    // Check if key has expired
    if (new Date() > keyData.expiresAt) {
      return res.status(401).json({
        success: false,
        error: 'API key has expired',
        expiresAt: keyData.expiresAt,
      });
    }
    
    // Validate timestamp (prevent replay attacks)
    const requestTime = parseInt(timestamp);
    const now = Date.now();
    const timeDiff = Math.abs(now - requestTime);
    
    if (timeDiff > SIGNATURE_VALIDITY_WINDOW) {
      return res.status(401).json({
        success: false,
        error: 'Request timestamp out of valid window',
        validWindow: `${SIGNATURE_VALIDITY_WINDOW / 1000} seconds`,
      });
    }
    
    // Check nonce (prevent duplicate requests)
    if (usedNonces.has(nonce)) {
      return res.status(401).json({
        success: false,
        error: 'Nonce already used (duplicate request)',
      });
    }
    
    // Get request body as string
    const body = req.body ? JSON.stringify(req.body) : '';
    
    // Verify signature
    const isValid = verifySignature(
      req.method,
      req.originalUrl,
      timestamp,
      nonce,
      body,
      signature,
      keyData.apiSecret
    );
    
    if (!isValid) {
      return res.status(401).json({
        success: false,
        error: 'Invalid signature',
      });
    }
    
    // Mark nonce as used (with expiry)
    usedNonces.set(nonce, now + SIGNATURE_VALIDITY_WINDOW);
    
    // Update usage statistics
    keyData.lastUsed = new Date();
    keyData.usageCount++;
    
    const stats = keyUsageStats.get(apiKey);
    stats.requestCount++;
    stats.lastRequest = new Date();
    
    // Attach key info to request for logging
    req.apiKey = apiKey;
    req.authenticated = true;
    
    next();
  } catch (error) {
    console.error('❌ Authentication error:', error);
    return res.status(500).json({
      success: false,
      error: 'Authentication failed',
      message: error.message,
    });
  }
}

/**
 * Rate limiter for authenticated requests
 */
const authenticatedRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Limit each API key to 1000 requests per window
  keyGenerator: (req) => req.apiKey || req.ip,
  message: {
    success: false,
    error: 'Too many requests, please try again later',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

/**
 * Get all API keys (admin only)
 */
function getAllKeys() {
  return Array.from(apiKeys.entries()).map(([key, data]) => ({
    apiKey: key,
    createdAt: data.createdAt,
    lastUsed: data.lastUsed,
    usageCount: data.usageCount,
    isActive: data.isActive,
    expiresAt: data.expiresAt,
    stats: keyUsageStats.get(key),
  }));
}

/**
 * Revoke an API key
 */
function revokeKey(apiKey) {
  const keyData = apiKeys.get(apiKey);
  if (keyData) {
    keyData.isActive = false;
    console.log('🔒 Revoked API key:', apiKey);
    return true;
  }
  return false;
}

/**
 * Delete an API key
 */
function deleteKey(apiKey) {
  const deleted = apiKeys.delete(apiKey);
  if (deleted) {
    keyUsageStats.delete(apiKey);
    console.log('🗑️  Deleted API key:', apiKey);
  }
  return deleted;
}

/**
 * Initialize with a default API key for development
 */
function initializeDefaultKey() {
  if (process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test') {
    const defaultKey = generateAPIKey();
    console.log('🔑 Development API Key:', defaultKey.apiKey);
    console.log('🔐 Development API Secret:', defaultKey.apiSecret);
    console.log('⚠️  Store these credentials securely!');
    return defaultKey;
  }
  return null;
}

module.exports = {
  authenticate,
  authenticatedRateLimiter,
  generateAPIKey,
  getAllKeys,
  revokeKey,
  deleteKey,
  initializeDefaultKey,
  verifySignature, // Export for testing
};

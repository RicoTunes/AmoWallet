const rateLimit = require('express-rate-limit');

// General API rate limiter - 500 requests per 15 minutes (increased for development)
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 500, // Increased from 100 to 500 for development/testing
  message: {
    error: 'Too many requests from this IP',
    message: 'Please try again after 15 minutes',
  },
  standardHeaders: true, // Return rate limit info in the `RateLimit-*` headers
  legacyHeaders: false, // Disable the `X-RateLimit-*` headers
  handler: (req, res) => {
    res.status(429).json({
      error: 'Too many requests',
      message: 'You have exceeded the rate limit. Please try again later.',
      retryAfter: req.rateLimit.resetTime,
    });
  },
});

// Strict rate limiter for sensitive operations - 50 requests per 15 minutes
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 50, // Increased from 10 to 50 for development/testing
  message: {
    error: 'Too many requests',
    message: 'Please try again after 15 minutes',
  },
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    res.status(429).json({
      error: 'Too many requests for this operation',
      message: 'You have exceeded the rate limit for sensitive operations.',
      retryAfter: req.rateLimit.resetTime,
    });
  },
});

// Transaction rate limiter - 20 transactions per minute
const transactionLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 20, // Increased from 5 to 20 for development/testing
  message: {
    error: 'Transaction rate limit exceeded',
    message: 'Please wait before sending another transaction',
  },
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: false, // Count all requests
  handler: (req, res) => {
    res.status(429).json({
      error: 'Transaction rate limit exceeded',
      message: 'You are sending transactions too quickly. Please wait a moment.',
      retryAfter: req.rateLimit.resetTime,
    });
  },
});

// Wallet generation limiter - 3 wallets per hour per IP
const walletCreationLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3, // Limit each IP to 3 wallet creations per hour
  message: {
    error: 'Wallet creation limit exceeded',
    message: 'Too many wallet creation attempts. Please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    res.status(429).json({
      error: 'Wallet creation limit exceeded',
      message: 'You have created too many wallets. Please try again in an hour.',
      retryAfter: req.rateLimit.resetTime,
    });
  },
});

// Balance check limiter - 30 requests per minute
const balanceLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 30, // Limit each IP to 30 balance checks per minute
  message: {
    error: 'Balance check limit exceeded',
    message: 'Too many balance check requests',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Swap quote limiter - 20 requests per minute
const swapQuoteLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 20,
  message: {
    error: 'Swap quote limit exceeded',
    message: 'Too many swap quote requests',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

module.exports = {
  apiLimiter,
  strictLimiter,
  transactionLimiter,
  walletCreationLimiter,
  balanceLimiter,
  swapQuoteLimiter,
};

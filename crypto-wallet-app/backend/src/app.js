const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();

// Import security middleware
const { 
  applySecurity, 
  adminIpWhitelist,
  validateSignature,
} = require('./middleware/securityMiddleware');

// Import API key authentication
const { authenticate } = require('./middleware/auth');

// Apply comprehensive security (DDoS, headers, etc.)
applySecurity(app);

// Middleware
app.use(cors({
  origin: function (origin, callback) {
    // In development, allow all localhost/127.0.0.1 origins
    if (process.env.NODE_ENV === 'development' || !origin) {
      callback(null, true);
      return;
    }
    
    // Allow localhost and 127.0.0.1 with any port in development
    if (origin && (origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:'))) {
      callback(null, true);
      return;
    }
    
    // In production, check against allowed origins
    const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',');
    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('CORS not allowed'));
    }
  },
  credentials: true,
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Import routes
const walletRoutes = require('./routes/walletRoutes');
const blockchainRoutes = require('./routes/blockchainRoutes');
const swapRoutes = require('./routes/swapRoutes');
const multisigRoutes = require('./routes/multisigRoutes');
const auditRoutes = require('./routes/auditRoutes');
const authRoutes = require('./routes/authRoutes');
const healthRoutes = require('./routes/healthRoutes');
const adminRoutes = require('./routes/adminRoutes');
const spendingRoutes = require('./routes/spendingRoutes');
const priceRoutes = require('./routes/priceRoutes');
const secureRoutes = require('./routes/secureRoutes');

// Import middleware
const errorHandler = require('./middleware/errorHandler');
const adminControlService = require('./services/adminControlService');
const { WalletModes } = require('./services/adminControlService');

// App control middleware
const checkAppActive = (req, res, next) => {
  const state = adminControlService.getWalletState();
  if (state.mode === WalletModes.PAUSED) {
    return res.status(503).json({
      success: false,
      error: 'Service temporarily unavailable',
      message: state.message || 'The wallet is currently paused for maintenance',
      mode: state.mode,
    });
  }
  next();
};

const checkReadOnly = (req, res, next) => {
  const state = adminControlService.getWalletState();
  if (state.mode === WalletModes.READ_ONLY && ['POST', 'PUT', 'DELETE'].includes(req.method)) {
    return res.status(503).json({
      success: false,
      error: 'Read-only mode',
      message: state.message || 'The wallet is in read-only mode. Transactions are disabled.',
      mode: state.mode,
    });
  }
  next();
};

const { apiLimiter } = require('./middleware/rateLimiter');

// Basic health check endpoint (no auth required)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development',
    message: 'Crypto Wallet API is running'
  });
});

// Detailed health routes
app.use('/health', healthRoutes);

// Apply rate limiting to all API routes
app.use('/api', apiLimiter);

// Admin routes (IP whitelist + authentication in production)
app.use('/api/admin', adminIpWhitelist, adminRoutes);

// Conditionally apply authentication based on environment
const requireAuth = process.env.REQUIRE_API_AUTH === 'true' || process.env.NODE_ENV === 'production';

// Public swap read-only endpoints — providers, rates, coins are safe to expose without auth.
// Must be registered BEFORE the authenticated app.use('/api/swap', ...) below.
const publicSwapRoutes = require('./routes/swapPublicRoutes');
app.use('/api/swap', publicSwapRoutes);

// Apply app status check and authentication to protected routes
// Transaction routes require signature validation
app.use('/api/wallet', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, walletRoutes);
app.use('/api/swap', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, swapRoutes);
app.use('/api/multisig', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, multisigRoutes);

// Secure routes — encrypted key forwarding to Rust (no raw keys in Node.js)
app.use('/api/secure', checkAppActive, checkReadOnly, secureRoutes);

// Blockchain routes — legacy (being replaced by /api/secure routes)
// Security is enforced per-route via rate limiting (transactionLimiter) and the
// client-provided private key (the server never stores keys).
app.use('/api/blockchain', checkAppActive, checkReadOnly, blockchainRoutes);
app.use('/api/spending', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), spendingRoutes);
app.use('/api/audit', checkAppActive, requireAuth ? authenticate : (req, res, next) => next(), auditRoutes);

// Auth routes (public - no kill switch)
app.use('/api/auth', authRoutes);

// Price proxy — public, no auth (server fetches from CoinGecko, no CORS for clients)
app.use('/api/prices', priceRoutes);

// 404 handler for unmatched routes
app.use((req, res) => {
  res.status(404).json({
    error: 'Route not found',
    message: `The requested endpoint ${req.originalUrl} does not exist`,
  });
});

// Global error handling middleware
app.use(errorHandler);

module.exports = app;

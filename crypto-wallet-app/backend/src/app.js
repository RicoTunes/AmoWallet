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

// Apply app status check and authentication to protected routes
// Transaction routes require signature validation
app.use('/api/wallet', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, walletRoutes);
app.use('/api/swap', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, swapRoutes);
app.use('/api/multisig', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), validateSignature, multisigRoutes);

// Read-heavy routes (auth required, no signature needed)
app.use('/api/blockchain', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), blockchainRoutes);
app.use('/api/spending', checkAppActive, checkReadOnly, requireAuth ? authenticate : (req, res, next) => next(), spendingRoutes);
app.use('/api/audit', checkAppActive, requireAuth ? authenticate : (req, res, next) => next(), auditRoutes);

// Auth routes (public - no kill switch)
app.use('/api/auth', authRoutes);

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

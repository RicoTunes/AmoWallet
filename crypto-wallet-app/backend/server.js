// AmoWallet Server - Fail-safe startup for Railway
const http = require('http');

const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';

console.log('Starting AmoWallet Server...');
console.log('PORT:', PORT);
console.log('NODE_ENV:', process.env.NODE_ENV || 'development');

// Create a basic server FIRST to pass healthcheck
let app = null;
let serverReady = false;
let lastError = null;

const server = http.createServer((req, res) => {
  // Health check - always respond
  if (req.url === '/health' || req.url === '/health/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'OK',
      timestamp: new Date().toISOString(),
      ready: serverReady,
      message: serverReady ? 'Crypto Wallet API is running' : 'Server starting...',
      error: lastError
    }));
    return;
  }

  // Status endpoint to check errors
  if (req.url === '/status' || req.url === '/status/') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ready: serverReady,
      error: lastError,
      env: {
        NODE_ENV: process.env.NODE_ENV || 'not set',
        PORT: PORT
      }
    }));
    return;
  }

  // If app is loaded, delegate to Express
  if (app && serverReady) {
    app(req, res);
    return;
  }

  // Not ready yet
  res.writeHead(503, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Server starting...', ready: false }));
});

// Start listening IMMEDIATELY
server.listen(PORT, HOST, () => {
  console.log('Server listening on ' + HOST + ':' + PORT);
  console.log('Loading application...');

  // Now load the full Express app asynchronously
  loadApp();
});

async function loadApp() {
  try {
    // Load dotenv
    require('dotenv').config();
    console.log('dotenv loaded');

    // Load Express app
    console.log('Loading Express app...');
    app = require('./src/app');
    console.log('Express app loaded');

    // Initialize auth
    try {
      const { initializeDefaultKey } = require('./src/middleware/auth');
      const defaultKey = initializeDefaultKey();
      if (defaultKey) {
        console.log('Default API key initialized');
      }
    } catch (e) {
      console.log('Auth init skipped:', e.message);
    }

    // Load optional services
    if (process.env.MINIMAL_MODE !== 'true') {
      try {
        const FeeSweepService = require('./src/services/feeSweepService');
        const TelegramService = require('./src/services/telegramService');
        const feeSweepService = new FeeSweepService();
        const telegramService = new TelegramService();
        
        if (process.env.FEE_SWEEP_ENABLED !== 'false') {
          feeSweepService.start();
          console.log('Fee sweep service started');
        }
        
        telegramService.sendStartupNotification({
          port: PORT,
          environment: process.env.NODE_ENV || 'development',
          features: ['Fee Collection', 'Multi-Chain Support']
        });
      } catch (e) {
        console.log('Optional services not loaded:', e.message);
      }
    }

    serverReady = true;
    console.log('');
    console.log('AmoWallet API Server Ready!');
    console.log('Health: http://localhost:' + PORT + '/health');
    console.log('API: http://localhost:' + PORT + '/api');
    console.log('');

  } catch (error) {
    console.error('Failed to load app:', error.message);
    console.error(error.stack);
    lastError = error.message + ' | ' + (error.stack || '').split('\n').slice(0, 3).join(' ');
    // Keep server running for healthcheck, but not ready
    serverReady = false;
  }
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled Rejection:', reason);
});

module.exports = server;

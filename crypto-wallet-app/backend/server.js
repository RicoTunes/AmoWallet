const app = require('./src/app');
const SSLConfigManager = require('./src/config/ssl-config');
const { initializeDefaultKey } = require('./src/middleware/auth');
const FeeSweepService = require('./src/services/feeSweepService');
const TelegramService = require('./src/services/telegramService');

// Port configuration
const PORT = process.env.PORT || 3000;
const HTTPS_PORT = process.env.HTTPS_PORT || 443;
const HTTP_REDIRECT_PORT = process.env.HTTP_REDIRECT_PORT || 80;

// Initialize SSL configuration
const sslConfig = new SSLConfigManager();
const enableHTTPS = process.env.ENABLE_HTTPS === 'true';

// Create server (HTTP or HTTPS based on configuration)
const server = sslConfig.createHTTPSServer(app);
const protocol = enableHTTPS ? 'https' : 'http';
const serverPort = enableHTTPS && process.env.NODE_ENV === 'production' ? HTTPS_PORT : PORT;

// Initialize authentication (generate default dev key)
const defaultKey = initializeDefaultKey();

// Initialize services
const feeSweepService = new FeeSweepService();
const telegramService = new TelegramService();

// Start main server
server.listen(serverPort, () => {
  console.log('\n🚀 Crypto Wallet API Server Started Successfully!');
  console.log(`📡 Server running on port ${serverPort}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`� HTTPS: ${enableHTTPS ? 'Enabled ✅' : 'Disabled ⚠️'}`);
  
  if (defaultKey) {
    console.log('\n🔐 Authentication:');
    console.log(`   API Key: ${defaultKey.apiKey}`);
    console.log(`   API Secret: ${defaultKey.apiSecret}`);
    console.log('   ⚠️  Save these credentials securely!');
  }
  
  console.log(`\n🔗 Health check: ${protocol}://localhost:${serverPort}/health`);
  console.log(`📚 API Base URL: ${protocol}://localhost:${serverPort}/api`);
  console.log('\n📝 Available endpoints:');
  console.log('   🔑 Authentication:');
  console.log('   - POST /api/auth/keys/generate - Generate API key');
  console.log('   - GET  /api/auth/keys - List all API keys');
  console.log('   - GET  /api/auth/test - Test authentication');
  console.log('\n   💼 Wallet:');
  console.log('   - POST /api/wallet/generate - Generate new wallet');
  console.log('   - POST /api/wallet/restore - Restore wallet from mnemonic');
  console.log('\n   ⛓️  Blockchain:');
  console.log('   - GET  /api/blockchain/balance/:network/:address - Get balance');
  console.log('   - POST /api/blockchain/send - Send transaction');
  console.log('   - GET  /api/blockchain/confirmations/:chain/:txHash - Get confirmations');
  console.log('\n   🔄 Swap:');
  console.log('   - POST /api/swap/quote - Get swap quote');
  console.log('   - POST /api/swap/build - Build swap transaction');
  console.log('\n   👥 Multi-sig:');
  console.log('   - GET  /api/multisig/info - Multi-sig contract info');
  console.log('   - POST /api/multisig/deploy - Deploy multi-sig wallet');
  console.log('   - POST /api/multisig/submit - Submit transaction');
  console.log('   - POST /api/multisig/confirm - Confirm transaction');
  console.log('   - POST /api/multisig/execute - Execute transaction');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  
  // Start fee sweep service
  if (process.env.FEE_SWEEP_ENABLED !== 'false') {
    console.log('\n💰 Starting Fee Sweep Service...');
    feeSweepService.start();
    console.log('✅ Fee sweep service running (24h interval)');
  }
  
  // Send startup notification to Telegram
  telegramService.sendStartupNotification({
    port: serverPort,
    environment: process.env.NODE_ENV || 'development',
    features: [
      'Fee Collection ✅',
      'Automated Sweep Service ✅',
      'Telegram Alerts ✅',
      'Multi-Chain Support ✅',
      'USDT Auto-Conversion ✅'
    ]
  });
});

// Setup HTTP to HTTPS redirect (production only)
if (enableHTTPS && process.env.NODE_ENV === 'production') {
  const redirectServer = sslConfig.setupHTTPRedirect(HTTPS_PORT);
  if (redirectServer) {
    redirectServer.listen(HTTP_REDIRECT_PORT, () => {
      console.log(`🔀 HTTP to HTTPS redirect enabled on port ${HTTP_REDIRECT_PORT}`);
    });
  }
}

// Graceful shutdown handling
const gracefulShutdown = (signal) => {
  console.log(`\n⚠️ Received ${signal}. Starting graceful shutdown...`);
  
  // Stop fee sweep service
  feeSweepService.stop();
  
  server.close(() => {
    console.log('✅ HTTP server closed');
    process.exit(0);
  });
  
  // Force close after 10 seconds
  setTimeout(() => {
    console.error('❌ Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000);
};

// Handle process termination
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  gracefulShutdown('UNCAUGHT_EXCEPTION');
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  gracefulShutdown('UNHANDLED_REJECTION');
});

module.exports = server;

const app = require('./src/app');
const SSLConfigManager = require('./src/config/ssl-config');
const { initializeDefaultKey } = require('./src/middleware/auth');
const database = require('./src/config/database');
const { logger, Sentry } = require('./src/config/monitoring');

// Port configuration
const PORT = process.env.PORT || 3000;
const HTTPS_PORT = process.env.HTTPS_PORT || 443;
const HTTP_REDIRECT_PORT = process.env.HTTP_REDIRECT_PORT || 80;

// Initialize SSL configuration
const sslConfig = new SSLConfigManager();
const enableHTTPS = process.env.ENABLE_HTTPS === 'true';

// Initialize Sentry error tracking (production only)
if (Sentry && process.env.NODE_ENV === 'production') {
  app.use(Sentry.Handlers.requestHandler());
  app.use(Sentry.Handlers.tracingHandler());
}

// Create server (HTTP or HTTPS based on configuration)
const server = sslConfig.createHTTPSServer(app);
const protocol = enableHTTPS ? 'https' : 'http';
const serverPort = enableHTTPS && process.env.NODE_ENV === 'production' ? HTTPS_PORT : PORT;

// Async initialization
async function startServer() {
  try {
    // Connect to database and Redis (production only)
    if (process.env.NODE_ENV === 'production' && process.env.DATABASE_URL) {
      logger.info('🔗 Connecting to database...');
      await database.connect();
      logger.info('✅ Database connected successfully');
    } else {
      logger.warn('⚠️  Running in development mode without database');
    }
    
    // Initialize authentication (generate default dev key)
    const defaultKey = initializeDefaultKey();

    // Start main server
    server.listen(serverPort, () => {
      logger.info('🚀 Crypto Wallet API Server Started Successfully!');
      logger.info(`📡 Server running on port ${serverPort}`);
      logger.info(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
      logger.info(`🔒 HTTPS: ${enableHTTPS ? 'Enabled ✅' : 'Disabled ⚠️'}`);
      
      if (defaultKey) {
        console.log('\n🔐 Authentication:');
        console.log(`   API Key: ${defaultKey.apiKey}`);
        console.log(`   API Secret: ${defaultKey.apiSecret}`);
        console.log('   ⚠️  Save these credentials securely!');
      }
      
      console.log(`\n🔗 Health check: ${protocol}://localhost:${serverPort}/health`);
      console.log(`📚 API Base URL: ${protocol}://localhost:${serverPort}/api`);
      console.log('\n📝 Available endpoints:');
      console.log('   🏥 Health:');
      console.log('   - GET  /health - Basic health check');
      console.log('   - GET  /health/detailed - Detailed health with DB status');
      console.log('   - GET  /health/db - Database health');
      console.log('   - GET  /health/redis - Redis health');
      console.log('   - GET  /health/ready - Readiness probe');
      console.log('   - GET  /health/live - Liveness probe');
      console.log('   - GET  /health/metrics - Performance metrics');
      console.log('\n   🔑 Authentication:');
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
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    });

    // Setup HTTP to HTTPS redirect (production only)
    if (enableHTTPS && process.env.NODE_ENV === 'production') {
      const redirectServer = sslConfig.setupHTTPRedirect(HTTPS_PORT);
      if (redirectServer) {
        redirectServer.listen(HTTP_REDIRECT_PORT, () => {
          logger.info(`🔀 HTTP to HTTPS redirect enabled on port ${HTTP_REDIRECT_PORT}`);
        });
      }
    }
    
    // Add Sentry error handler (must be after all routes)
    if (Sentry && process.env.NODE_ENV === 'production') {
      app.use(Sentry.Handlers.errorHandler());
    }

  } catch (error) {
    logger.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown handling
const gracefulShutdown = async (signal) => {
  logger.info(`⚠️ Received ${signal}. Starting graceful shutdown...`);
  
  // Close server
  server.close(() => {
    logger.info('✅ HTTP server closed');
  });
  
  // Disconnect from database
  if (process.env.NODE_ENV === 'production' && process.env.DATABASE_URL) {
    try {
      await database.disconnect();
      logger.info('✅ Database disconnected');
    } catch (error) {
      logger.error('❌ Error disconnecting database:', error);
    }
  }
  
  // Close Sentry
  if (Sentry && process.env.NODE_ENV === 'production') {
    await Sentry.close(2000);
  }
  
  process.exit(0);
};

// Handle process termination
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error('❌ Uncaught Exception:', error);
  if (Sentry) {
    Sentry.captureException(error);
  }
  gracefulShutdown('UNCAUGHT_EXCEPTION');
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  if (Sentry) {
    Sentry.captureException(reason);
  }
  gracefulShutdown('UNHANDLED_REJECTION');
});

// Start the server
startServer();

module.exports = server;

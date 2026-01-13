const express = require('express');
const router = express.Router();
const database = require('../config/database');
const { getSystemHealth } = require('../config/monitoring');

/**
 * Health Check Routes
 * Provides endpoints for monitoring service health and readiness
 */

/**
 * Basic health check - service is running
 * GET /health
 */
router.get('/', async (req, res) => {
  const health = {
    status: 'healthy',
    service: 'crypto-wallet-pro',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  };
  
  res.status(200).json(health);
});

/**
 * Detailed health check - includes all subsystems
 * GET /health/detailed
 */
router.get('/detailed', async (req, res) => {
  const health = {
    status: 'healthy',
    service: 'crypto-wallet-pro',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    checks: {},
  };
  
  try {
    // Check database
    try {
      await database.testConnection();
      health.checks.database = {
        status: 'healthy',
        message: 'Connected',
      };
    } catch (error) {
      health.checks.database = {
        status: 'unhealthy',
        message: error.message,
      };
      health.status = 'unhealthy';
    }
    
    // Check Redis
    try {
      await database.testRedis();
      health.checks.redis = {
        status: 'healthy',
        message: 'Connected',
      };
    } catch (error) {
      health.checks.redis = {
        status: 'unhealthy',
        message: error.message,
      };
      health.status = 'degraded'; // Redis is not critical
    }
    
    // Check memory
    const memUsage = process.memoryUsage();
    const memoryThreshold = 500 * 1024 * 1024; // 500MB
    health.checks.memory = {
      status: memUsage.heapUsed > memoryThreshold ? 'warning' : 'healthy',
      heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
      heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`,
    };
    
    const statusCode = health.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(health);
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      service: 'crypto-wallet-pro',
      timestamp: new Date().toISOString(),
      error: error.message,
    });
  }
});

/**
 * Database health check
 * GET /health/db
 */
router.get('/db', async (req, res) => {
  try {
    await database.testConnection();
    res.status(200).json({
      status: 'healthy',
      message: 'Database connected',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      message: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

/**
 * Redis health check
 * GET /health/redis
 */
router.get('/redis', async (req, res) => {
  try {
    await database.testRedis();
    res.status(200).json({
      status: 'healthy',
      message: 'Redis connected',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      message: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

/**
 * Readiness probe - all systems ready
 * GET /health/ready
 * Used by load balancers to determine if service can accept traffic
 */
router.get('/ready', async (req, res) => {
  try {
    // Check critical systems
    await database.testConnection();
    
    res.status(200).json({
      status: 'ready',
      message: 'Service is ready to accept traffic',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: 'not-ready',
      message: 'Service is not ready to accept traffic',
      error: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

/**
 * Liveness probe - service is alive
 * GET /health/live
 * Used by orchestrators to determine if service should be restarted
 */
router.get('/live', (req, res) => {
  // Simple check - if we can respond, we're alive
  res.status(200).json({
    status: 'alive',
    message: 'Service is running',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

/**
 * Metrics endpoint
 * GET /health/metrics
 */
router.get('/metrics', (req, res) => {
  const systemHealth = getSystemHealth();
  res.status(200).json(systemHealth);
});

module.exports = router;

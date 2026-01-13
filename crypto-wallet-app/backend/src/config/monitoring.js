const winston = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');
const path = require('path');
require('dotenv').config();

/**
 * Monitoring & Logging Configuration
 * Provides structured logging with rotation and error tracking
 */

// Log directory
const logDir = process.env.LOG_FILE_PATH || path.join(__dirname, '../../logs');

// Winston logger configuration
const loggerConfig = {
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
  ),
  defaultMeta: { service: 'crypto-wallet-pro' },
  transports: [],
};

// Console transport (development)
if (process.env.NODE_ENV !== 'production') {
  loggerConfig.transports.push(
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      ),
    })
  );
}

// File transport with rotation (production)
if (process.env.NODE_ENV === 'production') {
  // Error logs
  loggerConfig.transports.push(
    new DailyRotateFile({
      filename: path.join(logDir, 'error-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      level: 'error',
      maxSize: '20m',
      maxFiles: '30d',
      zippedArchive: true,
    })
  );
  
  // Combined logs
  loggerConfig.transports.push(
    new DailyRotateFile({
      filename: path.join(logDir, 'combined-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxSize: '20m',
      maxFiles: '30d',
      zippedArchive: true,
    })
  );
  
  // API logs
  loggerConfig.transports.push(
    new DailyRotateFile({
      filename: path.join(logDir, 'api-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      level: 'http',
      maxSize: '20m',
      maxFiles: '14d',
      zippedArchive: true,
    })
  );
}

// Create logger
const logger = winston.createLogger(loggerConfig);

/**
 * Request logging middleware
 */
function requestLogger(req, res, next) {
  const startTime = Date.now();
  
  // Log response
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    const logData = {
      method: req.method,
      url: req.originalUrl,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      userAgent: req.get('user-agent'),
      apiKey: req.apiKey || 'none',
    };
    
    if (res.statusCode >= 500) {
      logger.error('Server error', logData);
    } else if (res.statusCode >= 400) {
      logger.warn('Client error', logData);
    } else {
      logger.http('Request completed', logData);
    }
  });
  
  next();
}

/**
 * Metrics tracking
 */
class MetricsCollector {
  constructor() {
    this.metrics = {
      requests: {
        total: 0,
        success: 0,
        errors: 0,
        byEndpoint: {},
      },
      performance: {
        avgResponseTime: 0,
        maxResponseTime: 0,
        minResponseTime: Infinity,
      },
      authentication: {
        attempts: 0,
        successes: 0,
        failures: 0,
      },
      blockchain: {
        transactions: 0,
        confirmations: 0,
        errors: 0,
      },
    };
  }
  
  recordRequest(endpoint, statusCode, duration) {
    this.metrics.requests.total++;
    
    if (statusCode >= 200 && statusCode < 400) {
      this.metrics.requests.success++;
    } else {
      this.metrics.requests.errors++;
    }
    
    // Track by endpoint
    if (!this.metrics.requests.byEndpoint[endpoint]) {
      this.metrics.requests.byEndpoint[endpoint] = 0;
    }
    this.metrics.requests.byEndpoint[endpoint]++;
    
    // Update performance metrics
    this.metrics.performance.maxResponseTime = Math.max(
      this.metrics.performance.maxResponseTime,
      duration
    );
    this.metrics.performance.minResponseTime = Math.min(
      this.metrics.performance.minResponseTime,
      duration
    );
    
    // Calculate average response time
    const total = this.metrics.requests.total;
    const currentAvg = this.metrics.performance.avgResponseTime;
    this.metrics.performance.avgResponseTime = 
      (currentAvg * (total - 1) + duration) / total;
  }
  
  recordAuth(success) {
    this.metrics.authentication.attempts++;
    if (success) {
      this.metrics.authentication.successes++;
    } else {
      this.metrics.authentication.failures++;
    }
  }
  
  recordTransaction() {
    this.metrics.blockchain.transactions++;
  }
  
  recordConfirmation() {
    this.metrics.blockchain.confirmations++;
  }
  
  recordBlockchainError() {
    this.metrics.blockchain.errors++;
  }
  
  getMetrics() {
    return {
      ...this.metrics,
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      timestamp: new Date().toISOString(),
    };
  }
  
  reset() {
    this.metrics = {
      requests: {
        total: 0,
        success: 0,
        errors: 0,
        byEndpoint: {},
      },
      performance: {
        avgResponseTime: 0,
        maxResponseTime: 0,
        minResponseTime: Infinity,
      },
      authentication: {
        attempts: 0,
        successes: 0,
        failures: 0,
      },
      blockchain: {
        transactions: 0,
        confirmations: 0,
        errors: 0,
      },
    };
  }
}

// Global metrics collector
const metrics = new MetricsCollector();

/**
 * Health monitoring
 */
function getSystemHealth() {
  const health = {
    status: 'healthy',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    memory: process.memoryUsage(),
    cpu: process.cpuUsage(),
    metrics: metrics.getMetrics(),
  };
  
  // Check memory usage
  const memUsage = process.memoryUsage();
  const memoryThreshold = 500 * 1024 * 1024; // 500MB
  if (memUsage.heapUsed > memoryThreshold) {
    health.status = 'degraded';
    health.warnings = health.warnings || [];
    health.warnings.push('High memory usage');
  }
  
  // Check error rate
  const errorRate = metrics.metrics.requests.total > 0
    ? metrics.metrics.requests.errors / metrics.metrics.requests.total
    : 0;
  if (errorRate > 0.1) { // More than 10% errors
    health.status = 'degraded';
    health.warnings = health.warnings || [];
    health.warnings.push('High error rate');
  }
  
  return health;
}

/**
 * Performance monitoring middleware
 */
function performanceMonitor(req, res, next) {
  const startTime = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    metrics.recordRequest(req.path, res.statusCode, duration);
    
    // Log slow requests
    if (duration > 1000) {
      logger.warn('Slow request detected', {
        method: req.method,
        url: req.originalUrl,
        duration: `${duration}ms`,
      });
    }
  });
  
  next();
}

/**
 * Error tracking (Sentry integration)
 */
let Sentry = null;
if (process.env.SENTRY_DSN && process.env.NODE_ENV === 'production') {
  try {
    Sentry = require('@sentry/node');
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      environment: process.env.NODE_ENV,
      tracesSampleRate: 0.1,
    });
    logger.info('✅ Sentry error tracking initialized');
  } catch (error) {
    logger.warn('⚠️  Sentry not available:', error.message);
  }
}

function captureException(error, context = {}) {
  logger.error('Exception caught:', { error: error.message, stack: error.stack, ...context });
  
  if (Sentry) {
    Sentry.captureException(error, {
      extra: context,
    });
  }
}

module.exports = {
  logger,
  requestLogger,
  performanceMonitor,
  metrics,
  getSystemHealth,
  captureException,
  Sentry,
};

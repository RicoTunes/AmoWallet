const { Pool } = require('pg');
const Redis = require('redis');
require('dotenv').config();

/**
 * Database Configuration Manager
 * Handles PostgreSQL and Redis connections
 */

// PostgreSQL Configuration
const pgConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME || 'crypto_wallet_pro',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  min: parseInt(process.env.DB_POOL_MIN) || 2,
  max: parseInt(process.env.DB_POOL_MAX) || 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
};

// PostgreSQL Pool
let pgPool = null;

function getPostgresPool() {
  if (!pgPool) {
    pgPool = new Pool(pgConfig);
    
    pgPool.on('error', (err) => {
      console.error('❌ Unexpected PostgreSQL error:', err);
    });
    
    pgPool.on('connect', () => {
      console.log('✅ PostgreSQL client connected');
    });
    
    console.log('📊 PostgreSQL pool initialized');
  }
  
  return pgPool;
}

// Redis Configuration
const redisConfig = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD || undefined,
  db: parseInt(process.env.REDIS_DB) || 0,
  retryStrategy: (times) => {
    const delay = Math.min(times * 50, 2000);
    return delay;
  },
};

// Redis Client
let redisClient = null;

function getRedisClient() {
  if (!redisClient) {
    redisClient = Redis.createClient(redisConfig);
    
    redisClient.on('error', (err) => {
      console.error('❌ Redis error:', err);
    });
    
    redisClient.on('connect', () => {
      console.log('✅ Redis client connected');
    });
    
    redisClient.on('ready', () => {
      console.log('✅ Redis client ready');
    });
    
    redisClient.connect().catch(console.error);
    
    console.log('🔴 Redis client initialized');
  }
  
  return redisClient;
}

// Initialize database tables
async function initializeTables() {
  const pool = getPostgresPool();
  
  try {
    // API Keys table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS api_keys (
        id SERIAL PRIMARY KEY,
        api_key VARCHAR(64) UNIQUE NOT NULL,
        api_secret VARCHAR(128) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_used TIMESTAMP,
        usage_count INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT true,
        expires_at TIMESTAMP,
        description TEXT,
        user_id INTEGER,
        rate_limit INTEGER DEFAULT 1000
      )
    `);
    
    // Spending limits table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS spending_limits (
        id SERIAL PRIMARY KEY,
        user_id VARCHAR(64) NOT NULL,
        daily_spending DECIMAL(20, 8) DEFAULT 0,
        daily_limit DECIMAL(20, 8) DEFAULT 10000000,
        last_reset TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Transaction confirmations table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pending_transactions (
        id SERIAL PRIMARY KEY,
        tx_hash VARCHAR(128) UNIQUE NOT NULL,
        chain VARCHAR(20) NOT NULL,
        coin VARCHAR(20) NOT NULL,
        amount DECIMAL(20, 8),
        tx_type VARCHAR(20),
        user_id VARCHAR(64),
        confirmations INTEGER DEFAULT 0,
        notified_at_1 BOOLEAN DEFAULT false,
        notified_at_6 BOOLEAN DEFAULT false,
        notified_at_12 BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Request logs table (for monitoring)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS request_logs (
        id SERIAL PRIMARY KEY,
        api_key VARCHAR(64),
        endpoint VARCHAR(255),
        method VARCHAR(10),
        status_code INTEGER,
        response_time INTEGER,
        ip_address VARCHAR(45),
        user_agent TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Create indexes
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_api_keys_api_key ON api_keys(api_key);
      CREATE INDEX IF NOT EXISTS idx_pending_tx_hash ON pending_transactions(tx_hash);
      CREATE INDEX IF NOT EXISTS idx_pending_tx_user ON pending_transactions(user_id);
      CREATE INDEX IF NOT EXISTS idx_spending_user ON spending_limits(user_id);
      CREATE INDEX IF NOT EXISTS idx_logs_api_key ON request_logs(api_key);
      CREATE INDEX IF NOT EXISTS idx_logs_created_at ON request_logs(created_at);
    `);
    
    console.log('✅ Database tables initialized');
  } catch (error) {
    console.error('❌ Error initializing tables:', error);
    throw error;
  }
}

// Health check
async function healthCheck() {
  const health = {
    postgres: false,
    redis: false,
    timestamp: new Date().toISOString(),
  };
  
  // Check PostgreSQL
  try {
    const pool = getPostgresPool();
    await pool.query('SELECT 1');
    health.postgres = true;
  } catch (error) {
    console.error('PostgreSQL health check failed:', error.message);
  }
  
  // Check Redis
  try {
    const redis = getRedisClient();
    await redis.ping();
    health.redis = true;
  } catch (error) {
    console.error('Redis health check failed:', error.message);
  }
  
  return health;
}

// Graceful shutdown
async function closeConnections() {
  console.log('🔄 Closing database connections...');
  
  if (pgPool) {
    await pgPool.end();
    console.log('✅ PostgreSQL pool closed');
  }
  
  if (redisClient) {
    await redisClient.quit();
    console.log('✅ Redis client closed');
  }
}

module.exports = {
  getPostgresPool,
  getRedisClient,
  initializeTables,
  healthCheck,
  closeConnections,
};

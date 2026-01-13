/**
 * Environment Variables Test Script
 * Tests all API endpoints and services to verify configuration
 */

const axios = require('axios');
require('dotenv').config();

// Optional ethers import (not needed for basic tests)
let ethers;
try {
  ethers = require('ethers');
} catch (e) {
  // ethers not installed, tests will skip ethers-specific checks
}

// ANSI color codes for terminal output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[36m',
  gray: '\x1b[90m'
};

const log = {
  success: (msg) => console.log(`${colors.green}✓${colors.reset} ${msg}`),
  error: (msg) => console.log(`${colors.red}✗${colors.reset} ${msg}`),
  warning: (msg) => console.log(`${colors.yellow}⚠${colors.reset} ${msg}`),
  info: (msg) => console.log(`${colors.blue}ℹ${colors.reset} ${msg}`),
  section: (msg) => console.log(`\n${colors.blue}━━━ ${msg} ━━━${colors.reset}`)
};

// Results tracking
const results = {
  passed: 0,
  failed: 0,
  warnings: 0,
  placeholders: []
};

// Check for placeholder values
function checkPlaceholders() {
  log.section('Checking for Placeholder Values');
  
  const placeholderPatterns = [
    { key: 'ETHERSCAN_API_KEY', value: process.env.ETHERSCAN_API_KEY, pattern: /^Your/ },
    { key: 'BSCSCAN_API_KEY', value: process.env.BSCSCAN_API_KEY, pattern: /^Your/ },
    { key: 'POLYGONSCAN_API_KEY', value: process.env.POLYGONSCAN_API_KEY, pattern: /^Your/ },
    { key: 'ARBISCAN_API_KEY', value: process.env.ARBISCAN_API_KEY, pattern: /^Your/ },
    { key: 'SNOWTRACE_API_KEY', value: process.env.SNOWTRACE_API_KEY, pattern: /^Your/ },
    { key: 'OPTIMISTIC_ETHERSCAN_API_KEY', value: process.env.OPTIMISTIC_ETHERSCAN_API_KEY, pattern: /^Your/ },
    { key: 'COINGECKO_API_KEY', value: process.env.COINGECKO_API_KEY, pattern: /^Your/ },
    { key: 'ONEINCH_API_KEY', value: process.env.ONEINCH_API_KEY, pattern: /^Your/ },
    { key: 'MORALIS_API_KEY', value: process.env.MORALIS_API_KEY, pattern: /^Your/ },
    { key: 'CHAINLINK_API_KEY', value: process.env.CHAINLINK_API_KEY, pattern: /^Your/ },
    { key: 'COINMARKETCAP_API_KEY', value: process.env.COINMARKETCAP_API_KEY, pattern: /^Your/ }
  ];

  placeholderPatterns.forEach(({ key, value, pattern }) => {
    if (!value || pattern.test(value)) {
      log.warning(`${key} is not set or is a placeholder`);
      results.placeholders.push(key);
      results.warnings++;
    } else {
      log.success(`${key} is configured`);
    }
  });
}

// Test Infura RPC endpoint
async function testInfuraRPC() {
  log.section('Testing Infura RPC (Ethereum)');
  
  if (!process.env.INFURA_PROJECT_ID) {
    log.error('INFURA_PROJECT_ID is not set');
    results.failed++;
    return;
  }

  try {
    const url = `${process.env.ETHEREUM_RPC_URL}${process.env.INFURA_PROJECT_ID}`;
    const response = await axios.post(url, {
      jsonrpc: '2.0',
      method: 'eth_blockNumber',
      params: [],
      id: 1
    }, { timeout: 10000 });

    if (response.data && response.data.result) {
      const blockNumber = parseInt(response.data.result, 16);
      log.success(`Ethereum RPC connected (Block: ${blockNumber})`);
      results.passed++;
    } else {
      log.error('Ethereum RPC returned invalid response');
      results.failed++;
    }
  } catch (error) {
    log.error(`Ethereum RPC failed: ${error.message}`);
    results.failed++;
  }
}

// Test BSC RPC endpoint
async function testBscRPC() {
  log.section('Testing BSC RPC');
  
  try {
    const response = await axios.post(process.env.BSC_RPC_URL, {
      jsonrpc: '2.0',
      method: 'eth_blockNumber',
      params: [],
      id: 1
    }, { timeout: 10000 });

    if (response.data && response.data.result) {
      const blockNumber = parseInt(response.data.result, 16);
      log.success(`BSC RPC connected (Block: ${blockNumber})`);
      results.passed++;
    } else {
      log.error('BSC RPC returned invalid response');
      results.failed++;
    }
  } catch (error) {
    log.error(`BSC RPC failed: ${error.message}`);
    results.failed++;
  }
}

// Test Etherscan API
async function testEtherscanAPI() {
  log.section('Testing Etherscan API');
  
  const apiKey = process.env.ETHERSCAN_API_KEY;
  if (!apiKey || /^Your/.test(apiKey)) {
    log.warning('ETHERSCAN_API_KEY is not configured (using placeholder)');
    results.warnings++;
    return;
  }

  try {
    const testAddress = '0x0000000000000000000000000000000000000000';
    const response = await axios.get('https://api.etherscan.io/api', {
      params: {
        module: 'account',
        action: 'balance',
        address: testAddress,
        tag: 'latest',
        apikey: apiKey
      },
      timeout: 10000
    });

    if (response.data && response.data.status === '1') {
      log.success('Etherscan API key is valid');
      results.passed++;
    } else {
      log.error(`Etherscan API error: ${response.data?.message || 'Unknown error'}`);
      results.failed++;
    }
  } catch (error) {
    log.error(`Etherscan API failed: ${error.message}`);
    results.failed++;
  }
}

// Test CoinGecko API
async function testCoinGeckoAPI() {
  log.section('Testing CoinGecko API');
  
  try {
    // First test ping endpoint
    const pingResponse = await axios.get('https://api.coingecko.com/api/v3/ping', {
      timeout: 10000
    });

    if (pingResponse.data && pingResponse.data.gecko_says) {
      log.success(`CoinGecko API is reachable: "${pingResponse.data.gecko_says}"`);
      results.passed++;
    }

    // Test actual price endpoint
    const apiKey = process.env.COINGECKO_API_KEY;
    const keyParam = apiKey && !/^Your/.test(apiKey) ? `&x_cg_pro_api_key=${apiKey}` : '';
    
    const priceResponse = await axios.get(
      `https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd${keyParam}`,
      { timeout: 10000 }
    );

    if (priceResponse.data && priceResponse.data.bitcoin) {
      log.success(`CoinGecko price API working (BTC: $${priceResponse.data.bitcoin.usd})`);
      
      if (apiKey && !/^Your/.test(apiKey)) {
        log.info('Using CoinGecko Pro API key for higher rate limits');
      } else {
        log.info('Using CoinGecko free tier (no API key)');
      }
      
      results.passed++;
    } else {
      log.error('CoinGecko price API returned invalid data');
      results.failed++;
    }
  } catch (error) {
    log.error(`CoinGecko API failed: ${error.message}`);
    results.failed++;
  }
}

// Test BlockCypher API (for LTC/DOGE)
async function testBlockCypherAPI() {
  log.section('Testing BlockCypher API');
  
  const apiKey = process.env.BLOCKCYPHER_API_KEY;
  if (!apiKey) {
    log.warning('BLOCKCYPHER_API_KEY is not set');
    results.warnings++;
    return;
  }

  try {
    const response = await axios.get(
      `https://api.blockcypher.com/v1/btc/main?token=${apiKey}`,
      { timeout: 10000 }
    );

    if (response.data && response.data.name) {
      log.success(`BlockCypher API key is valid (Chain: ${response.data.name})`);
      results.passed++;
    } else {
      log.error('BlockCypher API returned invalid response');
      results.failed++;
    }
  } catch (error) {
    if (error.response && error.response.status === 401) {
      log.error('BlockCypher API key is invalid');
    } else {
      log.error(`BlockCypher API failed: ${error.message}`);
    }
    results.failed++;
  }
}

// Test Database Connection
async function testDatabaseConnection() {
  log.section('Testing Database Connection');
  
  if (!process.env.DATABASE_URL) {
    log.error('DATABASE_URL is not set');
    results.failed++;
    return;
  }

  try {
    const mongoose = require('mongoose');
    await mongoose.connect(process.env.DATABASE_URL, {
      serverSelectionTimeoutMS: 5000
    });

    log.success(`MongoDB connected: ${process.env.DATABASE_URL}`);
    results.passed++;
    
    await mongoose.connection.close();
  } catch (error) {
    log.error(`MongoDB connection failed: ${error.message}`);
    log.info('Make sure MongoDB is running locally or update DATABASE_URL');
    results.failed++;
  }
}

// Test Redis Connection
async function testRedisConnection() {
  log.section('Testing Redis Connection');
  
  if (!process.env.REDIS_URL) {
    log.warning('REDIS_URL is not set (optional but recommended)');
    results.warnings++;
    return;
  }

  try {
    const redis = require('redis');
    const client = redis.createClient({ url: process.env.REDIS_URL });
    
    await client.connect();
    await client.ping();
    
    log.success('Redis connected successfully');
    results.passed++;
    
    await client.quit();
  } catch (error) {
    log.error(`Redis connection failed: ${error.message}`);
    log.info('Redis is optional but recommended for rate limiting and caching');
    results.warnings++;
  }
}

// Test Solana RPC
async function testSolanaRPC() {
  log.section('Testing Solana RPC');
  
  try {
    const response = await axios.post(process.env.SOLANA_RPC_URL, {
      jsonrpc: '2.0',
      method: 'getHealth',
      id: 1
    }, { timeout: 10000 });

    if (response.data && response.data.result === 'ok') {
      log.success('Solana RPC connected and healthy');
      results.passed++;
    } else {
      log.error('Solana RPC returned unhealthy status');
      results.failed++;
    }
  } catch (error) {
    log.error(`Solana RPC failed: ${error.message}`);
    results.failed++;
  }
}

// Print summary
function printSummary() {
  log.section('Test Summary');
  
  const total = results.passed + results.failed;
  const percentage = total > 0 ? ((results.passed / total) * 100).toFixed(1) : 0;
  
  console.log(`\nTotal Tests: ${total}`);
  console.log(`${colors.green}Passed: ${results.passed}${colors.reset}`);
  console.log(`${colors.red}Failed: ${results.failed}${colors.reset}`);
  console.log(`${colors.yellow}Warnings: ${results.warnings}${colors.reset}`);
  console.log(`\nSuccess Rate: ${percentage}%\n`);

  if (results.placeholders.length > 0) {
    log.section('Action Required: Replace Placeholder Values');
    console.log('\nThe following environment variables need real API keys:\n');
    results.placeholders.forEach(key => {
      console.log(`  ${colors.yellow}•${colors.reset} ${key}`);
    });
    console.log('');
  }

  if (results.failed > 0) {
    console.log(`${colors.red}Some tests failed. Review the errors above and fix configuration.${colors.reset}\n`);
    process.exit(1);
  } else if (results.warnings > 0) {
    console.log(`${colors.yellow}All critical tests passed, but some optional services are not configured.${colors.reset}\n`);
  } else {
    console.log(`${colors.green}All tests passed! Your environment is fully configured.${colors.reset}\n`);
  }
}

// Main test runner
async function runTests() {
  console.log(`\n${colors.blue}╔═══════════════════════════════════════════════════╗${colors.reset}`);
  console.log(`${colors.blue}║   Crypto Wallet Pro - Environment Tests          ║${colors.reset}`);
  console.log(`${colors.blue}╚═══════════════════════════════════════════════════╝${colors.reset}\n`);

  checkPlaceholders();
  await testInfuraRPC();
  await testBscRPC();
  await testSolanaRPC();
  await testEtherscanAPI();
  await testCoinGeckoAPI();
  await testBlockCypherAPI();
  await testDatabaseConnection();
  await testRedisConnection();
  
  printSummary();
}

// Run tests
runTests().catch(error => {
  console.error(`${colors.red}Fatal error: ${error.message}${colors.reset}`);
  process.exit(1);
});

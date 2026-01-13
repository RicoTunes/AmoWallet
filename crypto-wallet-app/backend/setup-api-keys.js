/**
 * Interactive API Key Setup Guide
 * Walks you through getting and setting up each API key
 */

const readline = require('readline');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[36m',
  magenta: '\x1b[35m',
  bold: '\x1b[1m'
};

function question(prompt) {
  return new Promise((resolve) => {
    rl.question(prompt, resolve);
  });
}

function log(msg, color = 'reset') {
  console.log(`${colors[color]}${msg}${colors.reset}`);
}

function openBrowser(url) {
  try {
    if (process.platform === 'win32') {
      execSync(`start ${url}`);
    } else if (process.platform === 'darwin') {
      execSync(`open ${url}`);
    } else {
      execSync(`xdg-open ${url}`);
    }
    return true;
  } catch (error) {
    return false;
  }
}

function updateEnvFile(key, value) {
  const envPath = path.join(__dirname, '.env');
  let envContent = fs.readFileSync(envPath, 'utf8');
  
  // Replace the placeholder or existing value
  const regex = new RegExp(`^${key}=.*$`, 'm');
  if (regex.test(envContent)) {
    envContent = envContent.replace(regex, `${key}=${value}`);
  } else {
    envContent += `\n${key}=${value}`;
  }
  
  fs.writeFileSync(envPath, envContent);
  log(`✓ Updated ${key} in .env file`, 'green');
}

const apiServices = [
  {
    name: 'Etherscan',
    key: 'ETHERSCAN_API_KEY',
    url: 'https://etherscan.io/apis',
    priority: 'CRITICAL',
    description: 'Ethereum transaction history, balance queries, gas prices',
    freeTeir: 'Yes (instant approval)',
    instructions: [
      '1. Click the link to open Etherscan API page',
      '2. Click "Sign Up" or "Login" (top right)',
      '3. Verify your email',
      '4. Go to "API-KEYs" in your account',
      '5. Click "Add" to create a new API key',
      '6. Copy the API key'
    ]
  },
  {
    name: 'BSCScan',
    key: 'BSCSCAN_API_KEY',
    url: 'https://bscscan.com/apis',
    priority: 'CRITICAL',
    description: 'BSC transaction history and balance queries',
    freeTier: 'Yes (instant approval)',
    instructions: [
      '1. Click the link to open BSCScan API page',
      '2. Click "Sign Up" or "Login"',
      '3. Verify your email',
      '4. Go to "API-KEYs" in your account',
      '5. Click "Add" to create a new API key',
      '6. Copy the API key'
    ]
  },
  {
    name: 'CoinGecko',
    key: 'COINGECKO_API_KEY',
    url: 'https://www.coingecko.com/en/api',
    priority: 'RECOMMENDED',
    description: 'Real-time cryptocurrency prices for swap quotes',
    freeTier: 'Yes (10,000 calls/month free)',
    instructions: [
      '1. Click the link to open CoinGecko API page',
      '2. Click "Get Your Free API Key"',
      '3. Sign up for a CoinGecko account',
      '4. Choose the "Demo" plan (free)',
      '5. Verify your email',
      '6. Copy your API key from the dashboard',
      '',
      'NOTE: Your app works without this (free tier), but this gives higher limits'
    ]
  },
  {
    name: 'CoinMarketCap',
    key: 'COINMARKETCAP_API_KEY',
    url: 'https://coinmarketcap.com/api/',
    priority: 'RECOMMENDED',
    description: 'Backup price feed (fallback when CoinGecko fails)',
    freeTier: 'Yes (333 calls/day)',
    instructions: [
      '1. Click the link to open CoinMarketCap API page',
      '2. Click "Get Your Free API Key Now"',
      '3. Sign up for an account',
      '4. Choose "Basic" plan (free)',
      '5. Verify your email',
      '6. Copy API key from dashboard'
    ]
  },
  {
    name: 'Polygonscan',
    key: 'POLYGONSCAN_API_KEY',
    url: 'https://polygonscan.com/apis',
    priority: 'OPTIONAL',
    description: 'Polygon network transaction history',
    freeTier: 'Yes',
    instructions: [
      'Same process as Etherscan:',
      '1. Sign up at polygonscan.com',
      '2. Go to API-KEYs section',
      '3. Create and copy key'
    ]
  },
  {
    name: 'Arbiscan',
    key: 'ARBISCAN_API_KEY',
    url: 'https://arbiscan.io/apis',
    priority: 'OPTIONAL',
    description: 'Arbitrum network data',
    freeTier: 'Yes',
    instructions: ['Same process as Etherscan']
  },
  {
    name: 'Snowtrace',
    key: 'SNOWTRACE_API_KEY',
    url: 'https://snowtrace.io/apis',
    priority: 'OPTIONAL',
    description: 'Avalanche network data',
    freeTier: 'Yes',
    instructions: ['Same process as Etherscan']
  },
  {
    name: 'Optimistic Etherscan',
    key: 'OPTIMISTIC_ETHERSCAN_API_KEY',
    url: 'https://optimistic.etherscan.io/apis',
    priority: 'OPTIONAL',
    description: 'Optimism network data',
    freeTier: 'Yes',
    instructions: ['Same process as Etherscan']
  },
  {
    name: 'OneInch',
    key: 'ONEINCH_API_KEY',
    url: 'https://portal.1inch.dev/',
    priority: 'OPTIONAL',
    description: 'DEX aggregation for best swap rates',
    freeTier: 'Yes',
    instructions: [
      '1. Visit portal.1inch.dev',
      '2. Sign up',
      '3. Create API key in dashboard'
    ]
  },
  {
    name: 'Moralis',
    key: 'MORALIS_API_KEY',
    url: 'https://moralis.io/',
    priority: 'OPTIONAL',
    description: 'Web3 APIs, NFTs, indexing',
    freeTier: 'Yes',
    instructions: [
      '1. Sign up at moralis.io',
      '2. Go to account settings',
      '3. Copy API key'
    ]
  },
  {
    name: 'Chainlink',
    key: 'CHAINLINK_API_KEY',
    url: 'https://chain.link/',
    priority: 'OPTIONAL',
    description: 'Oracle and price feed data',
    freeTier: 'Yes',
    instructions: [
      '1. Visit chain.link',
      '2. Sign up for services',
      '3. Get API credentials'
    ]
  }
];

async function setupApiKey(service) {
  console.log('\n' + '═'.repeat(70));
  log(`\n${service.name} API Key Setup`, 'bold');
  log(`Priority: ${service.priority}`, service.priority === 'CRITICAL' ? 'red' : service.priority === 'RECOMMENDED' ? 'yellow' : 'blue');
  log(`Purpose: ${service.description}`, 'reset');
  log(`Free Tier: ${service.freeTier}`, 'green');
  
  console.log('\n📋 Instructions:');
  service.instructions.forEach(instruction => {
    console.log(`   ${instruction}`);
  });
  
  console.log('');
  const openUrl = await question(`Open ${service.url} in browser? (y/n): `);
  
  if (openUrl.toLowerCase() === 'y' || openUrl.toLowerCase() === 'yes') {
    if (openBrowser(service.url)) {
      log('✓ Opened in browser', 'green');
    } else {
      log(`Please manually open: ${service.url}`, 'yellow');
    }
  }
  
  console.log('');
  const hasKey = await question(`Do you have the API key ready? (y/n/skip): `);
  
  if (hasKey.toLowerCase() === 'skip') {
    log('⊘ Skipped', 'yellow');
    return false;
  }
  
  if (hasKey.toLowerCase() === 'y' || hasKey.toLowerCase() === 'yes') {
    const apiKey = await question(`Enter your ${service.name} API key: `);
    
    if (apiKey && apiKey.trim() !== '' && !apiKey.startsWith('Your')) {
      updateEnvFile(service.key, apiKey.trim());
      log(`✓ ${service.name} API key saved!`, 'green');
      return true;
    } else {
      log('✗ Invalid key, skipping', 'red');
      return false;
    }
  }
  
  return false;
}

async function main() {
  console.log('\n' + '═'.repeat(70));
  log('  🔑 Crypto Wallet Pro - API Key Setup Assistant', 'bold');
  console.log('═'.repeat(70));
  
  log('\nThis tool will help you get and configure all API keys.', 'blue');
  log('You can skip optional keys and add them later.', 'blue');
  
  const startNow = await question('\nStart setup now? (y/n): ');
  
  if (startNow.toLowerCase() !== 'y' && startNow.toLowerCase() !== 'yes') {
    log('\nSetup cancelled. Run this script again when ready.', 'yellow');
    rl.close();
    return;
  }
  
  // Group by priority
  const critical = apiServices.filter(s => s.priority === 'CRITICAL');
  const recommended = apiServices.filter(s => s.priority === 'RECOMMENDED');
  const optional = apiServices.filter(s => s.priority === 'OPTIONAL');
  
  let keysAdded = 0;
  
  // Critical keys
  log('\n\n🔴 CRITICAL API KEYS (Required for core functionality)', 'red');
  for (const service of critical) {
    if (await setupApiKey(service)) keysAdded++;
  }
  
  // Recommended keys
  console.log('');
  const doContinue = await question('\nContinue to RECOMMENDED keys? (y/n): ');
  if (doContinue.toLowerCase() === 'y' || doContinue.toLowerCase() === 'yes') {
    log('\n\n🟡 RECOMMENDED API KEYS (Better performance & reliability)', 'yellow');
    for (const service of recommended) {
      if (await setupApiKey(service)) keysAdded++;
    }
  }
  
  // Optional keys
  console.log('');
  const doOptional = await question('\nContinue to OPTIONAL keys? (y/n): ');
  if (doOptional.toLowerCase() === 'y' || doOptional.toLowerCase() === 'yes') {
    log('\n\n🟢 OPTIONAL API KEYS (Advanced features)', 'blue');
    for (const service of optional) {
      if (await setupApiKey(service)) keysAdded++;
    }
  }
  
  // Summary
  console.log('\n' + '═'.repeat(70));
  log('\n✅ Setup Complete!', 'green');
  log(`\nTotal API keys configured: ${keysAdded}`, 'bold');
  
  console.log('\n📝 Next Steps:');
  console.log('   1. Run: node test-env.js');
  console.log('   2. Verify all keys are working');
  console.log('   3. Start your backend server');
  
  console.log('\n💡 Tips:');
  console.log('   • Keep your .env file secure (never commit to Git)');
  console.log('   • Free tier limits are usually enough for development');
  console.log('   • You can always add more keys later');
  
  const runTest = await question('\n\nRun test-env.js now to verify? (y/n): ');
  if (runTest.toLowerCase() === 'y' || runTest.toLowerCase() === 'yes') {
    log('\n🧪 Running tests...\n', 'blue');
    try {
      require('./test-env.js');
    } catch (error) {
      log(`Test script error: ${error.message}`, 'red');
    }
  }
  
  rl.close();
}

main().catch(error => {
  console.error(`Error: ${error.message}`);
  rl.close();
  process.exit(1);
});

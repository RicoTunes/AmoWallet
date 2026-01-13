# Fee Structure Customization Tool
# Interactive tool to set up tiered pricing and custom fees

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     FEE STRUCTURE CUSTOMIZATION WIZARD     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for existing configuration
$envFile = "c:\Users\RICO\ricoamos\crypto-wallet-app\backend\.env.production"
$configExists = Test-Path $envFile

if (!$configExists) {
    Write-Host "Creating new .env.production file..." -ForegroundColor Yellow
    "" | Out-File -FilePath $envFile -Encoding UTF8
}

Write-Host "Choose your fee structure type:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. SIMPLE FLAT FEE (Easiest)" -ForegroundColor White
Write-Host "   Same percentage for all transactions" -ForegroundColor Gray
Write-Host "   Example: 0.5% on every transaction" -ForegroundColor Gray
Write-Host ""
Write-Host "2. TIERED PRICING (Recommended)" -ForegroundColor White
Write-Host "   Different rates based on transaction size" -ForegroundColor Gray
Write-Host "   Example: 1% for small, 0.5% for large" -ForegroundColor Gray
Write-Host ""
Write-Host "3. CUSTOM PER-CHAIN (Advanced)" -ForegroundColor White
Write-Host "   Different fees for Ethereum, Bitcoin, BSC, etc." -ForegroundColor Gray
Write-Host "   Example: ETH 0.3%, BTC 0.5%, BSC 1%" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Enter your choice (1, 2, or 3)"

# Variables to store configuration
$config = @{
    transactionFee = ""
    swapFee = ""
    minFee = ""
    tieredEnabled = $false
    tiers = @()
    perChainEnabled = $false
    chainFees = @{}
}

switch ($choice) {
    "1" {
        # Simple Flat Fee
        Write-Host ""
        Write-Host "═══ SIMPLE FLAT FEE SETUP ═══" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Popular choices:" -ForegroundColor Yellow
        Write-Host "  0.3% - Very competitive (like major exchanges)" -ForegroundColor Gray
        Write-Host "  0.5% - Balanced (recommended for most apps)" -ForegroundColor Gray
        Write-Host "  1.0% - Premium service" -ForegroundColor Gray
        Write-Host "  1.5% - High margin" -ForegroundColor Gray
        Write-Host ""
        
        $config.transactionFee = Read-Host "Enter transaction fee percentage (default: 0.5)"
        if ([string]::IsNullOrWhiteSpace($config.transactionFee)) { $config.transactionFee = "0.5" }
        
        $config.swapFee = Read-Host "Enter swap fee percentage (default: 1.0)"
        if ([string]::IsNullOrWhiteSpace($config.swapFee)) { $config.swapFee = "1.0" }
        
        $config.minFee = Read-Host "Enter minimum fee in USD (default: 0.50)"
        if ([string]::IsNullOrWhiteSpace($config.minFee)) { $config.minFee = "0.50" }
        
        Write-Host ""
        Write-Host "✓ Simple flat fee configured!" -ForegroundColor Green
        Write-Host "  Transactions: $($config.transactionFee)%" -ForegroundColor White
        Write-Host "  Swaps: $($config.swapFee)%" -ForegroundColor White
        Write-Host "  Minimum: `$$($config.minFee) USD" -ForegroundColor White
    }
    
    "2" {
        # Tiered Pricing
        Write-Host ""
        Write-Host "═══ TIERED PRICING SETUP ═══" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Tiered pricing charges different rates based on transaction size" -ForegroundColor Yellow
        Write-Host "This is fair to users and encourages larger transactions!" -ForegroundColor Yellow
        Write-Host ""
        
        Write-Host "Recommended tier structure:" -ForegroundColor Cyan
        Write-Host "  Tier 1: `$0-`$100     → 1.0% (small transactions)" -ForegroundColor Gray
        Write-Host "  Tier 2: `$100-`$1,000  → 0.75% (medium)" -ForegroundColor Gray
        Write-Host "  Tier 3: `$1K-`$10K    → 0.5% (large)" -ForegroundColor Gray
        Write-Host "  Tier 4: `$10K+        → 0.25% (whale)" -ForegroundColor Gray
        Write-Host ""
        
        $useRecommended = Read-Host "Use recommended structure? (Y/N, default: Y)"
        
        if ($useRecommended -eq "N" -or $useRecommended -eq "n") {
            # Custom tiers
            Write-Host ""
            Write-Host "Let's set up your custom tiers:" -ForegroundColor Yellow
            Write-Host ""
            
            $tierCount = Read-Host "How many tiers? (2-6 recommended)"
            $tierCount = [int]$tierCount
            
            for ($i = 1; $i -le $tierCount; $i++) {
                Write-Host ""
                Write-Host "Tier $i:" -ForegroundColor Cyan
                $min = Read-Host "  Minimum amount (USD)"
                $max = Read-Host "  Maximum amount (USD, enter 0 for unlimited)"
                $fee = Read-Host "  Fee percentage"
                
                $config.tiers += @{
                    min = [decimal]$min
                    max = if ($max -eq "0") { [decimal]::MaxValue } else { [decimal]$max }
                    fee = [decimal]$fee
                }
            }
        } else {
            # Use recommended tiers
            $config.tiers = @(
                @{ min = 0; max = 100; fee = 1.0 },
                @{ min = 100; max = 1000; fee = 0.75 },
                @{ min = 1000; max = 10000; fee = 0.5 },
                @{ min = 10000; max = [decimal]::MaxValue; fee = 0.25 }
            )
        }
        
        $config.tieredEnabled = $true
        $config.transactionFee = "0.5"  # Default fallback
        
        Write-Host ""
        Write-Host "✓ Tiered pricing configured!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your tiers:" -ForegroundColor Cyan
        foreach ($tier in $config.tiers) {
            $maxDisplay = if ($tier.max -eq [decimal]::MaxValue) { "unlimited" } else { "`$$($tier.max)" }
            Write-Host "  `$$($tier.min) - $maxDisplay → $($tier.fee)%" -ForegroundColor White
        }
        
        # Swap fee for tiered
        Write-Host ""
        $config.swapFee = Read-Host "Enter swap fee percentage (default: 1.0)"
        if ([string]::IsNullOrWhiteSpace($config.swapFee)) { $config.swapFee = "1.0" }
        
        $config.minFee = Read-Host "Enter minimum fee in USD (default: 0.50)"
        if ([string]::IsNullOrWhiteSpace($config.minFee)) { $config.minFee = "0.50" }
    }
    
    "3" {
        # Per-Chain Fees
        Write-Host ""
        Write-Host "═══ CUSTOM PER-CHAIN FEES ═══" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Set different fees for each blockchain" -ForegroundColor Yellow
        Write-Host "Useful if gas costs vary significantly" -ForegroundColor Yellow
        Write-Host ""
        
        Write-Host "Recommended per-chain fees:" -ForegroundColor Cyan
        Write-Host "  Ethereum: 0.3% (high gas, competitive fee)" -ForegroundColor Gray
        Write-Host "  Bitcoin: 0.5% (standard)" -ForegroundColor Gray
        Write-Host "  Polygon: 0.8% (cheap gas, higher fee ok)" -ForegroundColor Gray
        Write-Host "  BSC: 1.0% (cheap gas, higher fee ok)" -ForegroundColor Gray
        Write-Host "  Solana: 0.4% (fast, competitive)" -ForegroundColor Gray
        Write-Host ""
        
        $useRecommended = Read-Host "Use recommended per-chain fees? (Y/N, default: Y)"
        
        if ($useRecommended -eq "N" -or $useRecommended -eq "n") {
            $chains = @("ethereum", "bitcoin", "polygon", "bsc", "solana")
            
            Write-Host ""
            foreach ($chain in $chains) {
                $fee = Read-Host "Fee for $chain (%, press Enter to skip)"
                if (![string]::IsNullOrWhiteSpace($fee)) {
                    $config.chainFees[$chain] = $fee
                }
            }
        } else {
            $config.chainFees = @{
                ethereum = "0.3"
                bitcoin = "0.5"
                polygon = "0.8"
                bsc = "1.0"
                solana = "0.4"
            }
        }
        
        $config.perChainEnabled = $true
        $config.transactionFee = "0.5"  # Default fallback
        
        Write-Host ""
        Write-Host "✓ Per-chain fees configured!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your chain fees:" -ForegroundColor Cyan
        foreach ($chain in $config.chainFees.Keys) {
            Write-Host "  $chain → $($config.chainFees[$chain])%" -ForegroundColor White
        }
        
        # Swap fee
        Write-Host ""
        $config.swapFee = Read-Host "Enter swap fee percentage (default: 1.0)"
        if ([string]::IsNullOrWhiteSpace($config.swapFee)) { $config.swapFee = "1.0" }
        
        $config.minFee = Read-Host "Enter minimum fee in USD (default: 0.50)"
        if ([string]::IsNullOrWhiteSpace($config.minFee)) { $config.minFee = "0.50" }
    }
    
    default {
        Write-Host ""
        Write-Host "❌ Invalid choice. Using default flat fee (0.5%)" -ForegroundColor Red
        $config.transactionFee = "0.5"
        $config.swapFee = "1.0"
        $config.minFee = "0.50"
    }
}

# Calculate example earnings
Write-Host ""
Write-Host "═══ REVENUE PROJECTIONS ═══" -ForegroundColor Cyan
Write-Host ""

$avgTxSize = 500
$exampleFee = if ($config.tieredEnabled) {
    # Use middle tier
    $tier = $config.tiers | Where-Object { $_.min -le $avgTxSize -and $_.max -ge $avgTxSize }
    if ($tier) { $tier[0].fee } else { [decimal]$config.transactionFee }
} elseif ($config.perChainEnabled) {
    [decimal]$config.chainFees["ethereum"]
} else {
    [decimal]$config.transactionFee
}

$exampleFeeAmount = $avgTxSize * ($exampleFee / 100)

Write-Host "Example transaction: `$500 USD" -ForegroundColor Yellow
Write-Host "Your fee: $exampleFee% = `$$exampleFeeAmount" -ForegroundColor White
Write-Host ""

$scenarios = @(
    @{ Users = 100; TxPerMonth = 200 },
    @{ Users = 1000; TxPerMonth = 2000 },
    @{ Users = 10000; TxPerMonth = 20000 },
    @{ Users = 100000; TxPerMonth = 200000 }
)

Write-Host "Monthly revenue at different scales:" -ForegroundColor Cyan
foreach ($scenario in $scenarios) {
    $monthlyRevenue = $scenario.TxPerMonth * $exampleFeeAmount
    Write-Host "  $($scenario.Users) users → `$$([math]::Round($monthlyRevenue, 2))/month" -ForegroundColor Green
}

# Write configuration to .env.production
Write-Host ""
Write-Host "═══ SAVING CONFIGURATION ═══" -ForegroundColor Cyan
Write-Host ""

$envContent = @"

# ===================================
# FEE STRUCTURE CONFIGURATION
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ===================================

# Base Fee Configuration
TRANSACTION_FEE_PERCENTAGE=$($config.transactionFee)
SWAP_FEE_PERCENTAGE=$($config.swapFee)
MIN_TRANSACTION_FEE_USD=$($config.minFee)

"@

if ($config.tieredEnabled) {
    $envContent += @"
# Tiered Pricing (ENABLED)
ENABLE_TIERED_PRICING=true
FEE_TIERS=$(($config.tiers | ForEach-Object { "$($_.min)-$($_.max):$($_.fee)" }) -join ",")

"@
} else {
    $envContent += "ENABLE_TIERED_PRICING=false`n`n"
}

if ($config.perChainEnabled) {
    $envContent += "# Per-Chain Fees (ENABLED)`nENABLE_PER_CHAIN_FEES=true`n"
    foreach ($chain in $config.chainFees.Keys) {
        $envContent += "FEE_$($chain.ToUpper())=$($config.chainFees[$chain])`n"
    }
    $envContent += "`n"
} else {
    $envContent += "ENABLE_PER_CHAIN_FEES=false`n`n"
}

# Check if file exists and append or create
if (Test-Path $envFile) {
    $existingContent = Get-Content $envFile -Raw
    if ($existingContent -notmatch "FEE STRUCTURE CONFIGURATION") {
        Add-Content -Path $envFile -Value $envContent
        Write-Host "✓ Configuration appended to .env.production" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Fee configuration already exists in .env.production" -ForegroundColor Yellow
        $overwrite = Read-Host "Overwrite existing fee config? (Y/N)"
        if ($overwrite -eq "Y" -or $overwrite -eq "y") {
            $existingContent -replace "(?s)# ===================================\s*# FEE STRUCTURE CONFIGURATION.*?(?=# ===================================|\z)", $envContent | Set-Content $envFile
            Write-Host "✓ Configuration updated" -ForegroundColor Green
        }
    }
} else {
    $envContent | Out-File -FilePath $envFile -Encoding UTF8
    Write-Host "✓ Configuration saved to .env.production" -ForegroundColor Green
}

# Create fee calculation helper file
Write-Host ""
Write-Host "Creating fee calculation helper..." -ForegroundColor Yellow

$helperContent = @"
// Fee Calculation Helper
// Auto-generated from customize-fees.ps1

class FeeCalculator {
  constructor() {
    this.transactionFeePercentage = parseFloat(process.env.TRANSACTION_FEE_PERCENTAGE || '0.5');
    this.swapFeePercentage = parseFloat(process.env.SWAP_FEE_PERCENTAGE || '1.0');
    this.minFeeUSD = parseFloat(process.env.MIN_TRANSACTION_FEE_USD || '0.50');
    this.tieredEnabled = process.env.ENABLE_TIERED_PRICING === 'true';
    this.perChainEnabled = process.env.ENABLE_PER_CHAIN_FEES === 'true';
    
    // Parse tiered pricing if enabled
    if (this.tieredEnabled && process.env.FEE_TIERS) {
      this.tiers = process.env.FEE_TIERS.split(',').map(tier => {
        const [range, fee] = tier.split(':');
        const [min, max] = range.split('-');
        return {
          min: parseFloat(min),
          max: max === 'Infinity' ? Infinity : parseFloat(max),
          fee: parseFloat(fee)
        };
      }).sort((a, b) => a.min - b.min);
    }
    
    // Parse per-chain fees if enabled
    if (this.perChainEnabled) {
      this.chainFees = {
        ethereum: parseFloat(process.env.FEE_ETHEREUM || this.transactionFeePercentage),
        bitcoin: parseFloat(process.env.FEE_BITCOIN || this.transactionFeePercentage),
        polygon: parseFloat(process.env.FEE_POLYGON || this.transactionFeePercentage),
        bsc: parseFloat(process.env.FEE_BSC || this.transactionFeePercentage),
        solana: parseFloat(process.env.FEE_SOLANA || this.transactionFeePercentage)
      };
    }
  }
  
  /**
   * Calculate fee for a transaction
   * @param {number} amountUSD - Transaction amount in USD
   * @param {string} type - 'transaction' or 'swap'
   * @param {string} chain - Blockchain name (optional, for per-chain fees)
   * @returns {object} Fee details
   */
  calculateFee(amountUSD, type = 'transaction', chain = null) {
    let feePercentage;
    
    // Determine base fee percentage
    if (type === 'swap') {
      feePercentage = this.swapFeePercentage;
    } else if (this.perChainEnabled && chain && this.chainFees[chain.toLowerCase()]) {
      feePercentage = this.chainFees[chain.toLowerCase()];
    } else if (this.tieredEnabled && this.tiers) {
      // Find appropriate tier
      const tier = this.tiers.find(t => amountUSD >= t.min && amountUSD < t.max);
      feePercentage = tier ? tier.fee : this.transactionFeePercentage;
    } else {
      feePercentage = this.transactionFeePercentage;
    }
    
    // Calculate fee amount
    let feeAmountUSD = amountUSD * (feePercentage / 100);
    
    // Apply minimum fee
    if (feeAmountUSD < this.minFeeUSD) {
      feeAmountUSD = this.minFeeUSD;
    }
    
    const netAmountUSD = amountUSD - feeAmountUSD;
    
    return {
      originalAmount: amountUSD,
      feePercentage: feePercentage,
      feeAmount: feeAmountUSD,
      netAmount: netAmountUSD,
      minFeeApplied: feeAmountUSD === this.minFeeUSD
    };
  }
  
  /**
   * Get fee details for display
   */
  getFeeStructure() {
    const structure = {
      type: 'simple',
      transactionFee: this.transactionFeePercentage,
      swapFee: this.swapFeePercentage,
      minFee: this.minFeeUSD
    };
    
    if (this.tieredEnabled) {
      structure.type = 'tiered';
      structure.tiers = this.tiers;
    }
    
    if (this.perChainEnabled) {
      structure.type = 'per-chain';
      structure.chainFees = this.chainFees;
    }
    
    return structure;
  }
}

module.exports = new FeeCalculator();
"@

$helperPath = "c:\Users\RICO\ricoamos\crypto-wallet-app\backend\src\lib\feeCalculator.js"
$helperContent | Out-File -FilePath $helperPath -Encoding UTF8
Write-Host "✓ Fee calculator created: src\lib\feeCalculator.js" -ForegroundColor Green

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎉 Fee structure customization complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Your configuration:" -ForegroundColor Yellow
if ($config.tieredEnabled) {
    Write-Host "  Type: Tiered Pricing" -ForegroundColor White
} elseif ($config.perChainEnabled) {
    Write-Host "  Type: Per-Chain Fees" -ForegroundColor White
} else {
    Write-Host "  Type: Simple Flat Fee" -ForegroundColor White
}
Write-Host "  Transaction Fee: $($config.transactionFee)%" -ForegroundColor White
Write-Host "  Swap Fee: $($config.swapFee)%" -ForegroundColor White
Write-Host "  Minimum Fee: `$$($config.minFee) USD" -ForegroundColor White
Write-Host ""
Write-Host "Files updated:" -ForegroundColor Cyan
Write-Host "  ✓ .env.production" -ForegroundColor Gray
Write-Host "  ✓ src\lib\feeCalculator.js" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: Set up Telegram bot for alerts!" -ForegroundColor Yellow
Write-Host "Run: .\setup-telegram-bot.ps1" -ForegroundColor White
Write-Host ""

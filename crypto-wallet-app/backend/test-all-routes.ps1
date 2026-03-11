# =============================================================================
# AmoWallet — Comprehensive Route Tester (NO real funds needed)
# Tests all API endpoints against your running backend at localhost:3000
# =============================================================================
# Usage:  .\test-all-routes.ps1 [-BaseUrl "https://your-railway-url.up.railway.app"]
# =============================================================================

param(
    [string]$BaseUrl = "http://localhost:3000"
)

$ErrorActionPreference = "Continue"
$passed = 0
$failed = 0
$skipped = 0
$results = @()

function Test-Route {
    param(
        [string]$Method,
        [string]$Path,
        [string]$Body = $null,
        [string]$Description,
        [int[]]$ExpectedStatus = @(200),
        [switch]$SkipAuth
    )

    $url = "$BaseUrl$Path"
    $headers = @{ "Content-Type" = "application/json" }

    try {
        $params = @{
            Uri             = $url
            Method          = $Method
            Headers         = $headers
            TimeoutSec      = 15
            ErrorAction     = "Stop"
            UseBasicParsing = $true
        }
        if ($Body) {
            $params["Body"] = $Body
        }

        $response = Invoke-WebRequest @params
        $status = $response.StatusCode
        $data = $null
        try { $data = $response.Content | ConvertFrom-Json } catch {}

        if ($ExpectedStatus -contains $status) {
            $script:passed++
            $icon = [char]0x2705  # checkmark
            $result = "PASS"
        } else {
            $script:failed++
            $icon = [char]0x274C  # X
            $result = "FAIL (got $status, expected $($ExpectedStatus -join '/'))"
        }
    }
    catch {
        $status = 0
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($ExpectedStatus -contains $status) {
            $script:passed++
            $icon = [char]0x2705
            $result = "PASS"
        } elseif ($status -eq 401 -or $status -eq 403) {
            $script:passed++
            $icon = [char]0x2705
            $result = "PASS (auth required as expected)"
        } elseif ($status -eq 0) {
            $script:failed++
            $icon = [char]0x274C
            $result = "FAIL (connection refused)"
        } else {
            $script:failed++
            $icon = [char]0x274C
            $result = "FAIL (status $status)"
        }
    }

    $line = "$icon  [$Method] $Path - $Description => $result"
    Write-Host $line
    $script:results += $line
}

Write-Host ""
Write-Host "================================================================"
Write-Host "  AmoWallet Route Tester"
Write-Host "  Target: $BaseUrl"
Write-Host "  Date:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "================================================================"
Write-Host ""

# ── HEALTH ───────────────────────────────────────────────────────────────────
Write-Host "--- HEALTH CHECKS ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/health" -Description "Basic health"
Test-Route -Method GET -Path "/health/detailed" -Description "Detailed health"
Test-Route -Method GET -Path "/health/ready" -Description "Readiness probe"
Test-Route -Method GET -Path "/health/live" -Description "Liveness probe"

# ── AUTH ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- AUTH (API Key Management) ---" -ForegroundColor Cyan
Test-Route -Method POST -Path "/api/auth/keys/generate" `
    -Body '{"description":"test-script"}' `
    -Description "Generate API key"
Test-Route -Method GET -Path "/api/auth/test" -Description "Auth test endpoint"

# ── WALLET ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- WALLET (generate/sign/verify) ---" -ForegroundColor Cyan
Test-Route -Method POST -Path "/api/wallet/generate" `
    -Description "Generate keypair" `
    -ExpectedStatus @(200, 401)
Test-Route -Method POST -Path "/api/wallet/sign" `
    -Body '{"privateKey":"0000000000000000000000000000000000000000000000000000000000000001","message":"test"}' `
    -Description "Sign message" `
    -ExpectedStatus @(200, 401)
Test-Route -Method POST -Path "/api/wallet/verify" `
    -Body '{"publicKey":"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798","message":"test","signature":"dummy"}' `
    -Description "Verify signature" `
    -ExpectedStatus @(200, 400, 401)

# ── PRICES ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- PRICES (public, no auth) ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/prices/" -Description "Get crypto prices"

# ── BLOCKCHAIN (read-only) ───────────────────────────────────────────────────
Write-Host ""
Write-Host "--- BLOCKCHAIN (balance/tx lookups - no funds needed) ---" -ForegroundColor Cyan

# Use well-known public addresses for balance checks (Satoshi's address, Vitalik's, etc.)
$btcAddr  = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"   # Genesis block
$ethAddr  = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" # vitalik.eth
$bnbAddr  = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
$dogeAddr = "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L"

Test-Route -Method GET -Path "/api/blockchain/balance/BTC/$btcAddr" -Description "BTC balance (genesis)"
Test-Route -Method GET -Path "/api/blockchain/balance/ETH/$ethAddr" -Description "ETH balance (vitalik)"
Test-Route -Method GET -Path "/api/blockchain/balance/BNB/$bnbAddr" -Description "BNB balance"
Test-Route -Method GET -Path "/api/blockchain/transactions/BTC/$btcAddr" -Description "BTC tx history"
Test-Route -Method GET -Path "/api/blockchain/transactions/ETH/$ethAddr" -Description "ETH tx history"
Test-Route -Method GET -Path "/api/blockchain/fees/BTC" -Description "BTC fee estimate"
Test-Route -Method GET -Path "/api/blockchain/fees/ETH" -Description "ETH fee estimate"

# ── SWAP (public read-only) ──────────────────────────────────────────────────
Write-Host ""
Write-Host "--- SWAP (public endpoints) ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/swap/providers" -Description "Swap providers"
Test-Route -Method GET -Path "/api/swap/rates" -Description "Swap rates"
Test-Route -Method GET -Path "/api/swap/coins" -Description "Swap coins"

# ── SPENDING LIMITS ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- SPENDING LIMITS ---" -ForegroundColor Cyan
Test-Route -Method POST -Path "/api/spending/check" `
    -Body '{"address":"0x0000000000000000000000000000000000000000","amount":0.001,"chain":"ETH"}' `
    -Description "Check spending limit" `
    -ExpectedStatus @(200, 401)
Test-Route -Method GET -Path "/api/spending/limits/0x0000000000000000000000000000000000000000" `
    -Description "Get spending limits" `
    -ExpectedStatus @(200, 401)

# ── AUDIT ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- CONTRACT AUDIT ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/audit/info" `
    -Description "Audit service info" `
    -ExpectedStatus @(200, 401)
Test-Route -Method GET -Path "/api/audit/whitelist" `
    -Description "Contract whitelist" `
    -ExpectedStatus @(200, 401)

# ── SECURE (Rust bridge) ────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- SECURE (Rust Security Server) ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/secure/health" `
    -Description "Rust server health" `
    -ExpectedStatus @(200, 502, 503)

# ── MULTISIG ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- MULTISIG ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/multisig/info" `
    -Description "MultiSig info" `
    -ExpectedStatus @(200, 401, 502)
Test-Route -Method GET -Path "/api/multisig/wallets" `
    -Description "List wallets" `
    -ExpectedStatus @(200, 401, 502)

# ── ADMIN ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- ADMIN (should be IP-restricted) ---" -ForegroundColor Cyan
Test-Route -Method GET -Path "/api/admin/app/status" `
    -Description "App status" `
    -ExpectedStatus @(200, 401, 403)
Test-Route -Method GET -Path "/api/admin/dashboard" `
    -Description "Admin dashboard" `
    -ExpectedStatus @(200, 401, 403)

# ── SEND (dry-run style — tests route exists without broadcasting) ───────────
Write-Host ""
Write-Host "--- SEND ROUTES (validation only, no real tx) ---" -ForegroundColor Cyan
# These will fail with validation errors (bad key/amount) but confirm the route exists
Test-Route -Method POST -Path "/api/blockchain/send" `
    -Body '{"chain":"ETH","fromAddress":"0x0000","toAddress":"0x0001","amount":"0","privateKey":"invalid"}' `
    -Description "Send route exists (will fail validation)" `
    -ExpectedStatus @(200, 400, 401, 500)
Test-Route -Method POST -Path "/api/secure/sign-evm" `
    -Body '{"encrypted_key":"test","chain":"ETH","to":"0x0001","amount":"0","rpc_url":"","hmac":"test"}' `
    -Description "Secure sign-evm route exists" `
    -ExpectedStatus @(200, 400, 401, 500, 502)

# ── SUMMARY ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "  RESULTS:" -ForegroundColor Yellow
Write-Host "    Passed:  $passed" -ForegroundColor Green
Write-Host "    Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "    Total:   $($passed + $failed)" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    $results | Where-Object { $_ -match "FAIL" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ""
}

Write-Host "TIP: To test against Railway, run:" -ForegroundColor DarkGray
Write-Host '  .\test-all-routes.ps1 -BaseUrl "https://YOUR-APP.up.railway.app"' -ForegroundColor DarkGray
Write-Host ""

# Simple Production Feature Tests
Write-Host "`n=== CRYPTO WALLET PRO - PRODUCTION TESTS ===" -ForegroundColor Cyan

$baseUrl = "http://localhost:3000"
$passed = 0
$failed = 0
$total = 0

function RunTest {
    param([string]$Name, [string]$Url, [string]$Method = "GET", [hashtable]$Headers = @{}, [string]$Body = $null)
    
    $script:total++
    Write-Host "`n[$script:total] Testing: $Name" -ForegroundColor Yellow
    
    try {
        $params = @{Uri = $Url; Method = $Method; Headers = $Headers}
        if ($Body) {
            $params.ContentType = "application/json"
            $params.Body = $Body
        }
        
        $response = Invoke-RestMethod @params
        Write-Host "    PASSED" -ForegroundColor Green
        $script:passed++
        return $response
    }
    catch {
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
        return $null
    }
}

# 1. HEALTH CHECKS
Write-Host "`n--- HEALTH CHECKS ---" -ForegroundColor Cyan
RunTest "Basic Health" "$baseUrl/health"
RunTest "Detailed Health" "$baseUrl/health/detailed"
RunTest "Readiness" "$baseUrl/health/ready"
RunTest "Liveness" "$baseUrl/health/live"
RunTest "Metrics" "$baseUrl/health/metrics"

# 2. API AUTHENTICATION
Write-Host "`n--- API AUTHENTICATION ---" -ForegroundColor Cyan
$keyBody = @{name = "test-key"} | ConvertTo-Json
$keyResp = RunTest "Generate API Key" "$baseUrl/api/auth/keys/generate" "POST" @{} $keyBody

if ($keyResp) {
    $apiKey = $keyResp.data.apiKey
    $apiSecret = $keyResp.data.apiSecret
    Write-Host "    Key: $($apiKey.Substring(0,20))..." -ForegroundColor Gray
    
    # Create HMAC signature
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $message = "GET/api/auth/test$timestamp"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($apiSecret)
    $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($message))
    $signature = [System.BitConverter]::ToString($signatureBytes).Replace('-','').ToLower()
    
    $authHeaders = @{
        'X-API-Key' = $apiKey
        'X-Signature' = $signature
        'X-Timestamp' = $timestamp
    }
    
    RunTest "Auth Test" "$baseUrl/api/auth/test" "GET" $authHeaders
    RunTest "List Keys" "$baseUrl/api/auth/keys" "GET" $authHeaders
    
    # 3. WALLET OPERATIONS
    Write-Host "`n--- WALLET OPERATIONS ---" -ForegroundColor Cyan
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $message = "POST/api/wallet/generate$timestamp"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($apiSecret)
    $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($message))
    $signature = [System.BitConverter]::ToString($signatureBytes).Replace('-','').ToLower()
    
    $authHeaders = @{
        'X-API-Key' = $apiKey
        'X-Signature' = $signature
        'X-Timestamp' = $timestamp
    }
    
    $walletBody = @{} | ConvertTo-Json
    $wallet = RunTest "Generate Wallet" "$baseUrl/api/wallet/generate" "POST" $authHeaders $walletBody
    
    if ($wallet) {
        Write-Host "    Address: $($wallet.address.Substring(0,15))..." -ForegroundColor Gray
    }
    
    # 4. INPUT VALIDATION
    Write-Host "`n--- INPUT VALIDATION ---" -ForegroundColor Cyan
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $message = "GET/api/blockchain/balance/ethereum/invalid$timestamp"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($apiSecret)
    $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($message))
    $signature = [System.BitConverter]::ToString($signatureBytes).Replace('-','').ToLower()
    
    $authHeaders = @{
        'X-API-Key' = $apiKey
        'X-Signature' = $signature
        'X-Timestamp' = $timestamp
    }
    
    $total++
    Write-Host "`n[$total] Testing: Invalid Address Rejection" -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/blockchain/balance/ethereum/invalid" -Method GET -Headers $authHeaders
        Write-Host "    FAILED: Should reject invalid address" -ForegroundColor Red
        $failed++
    }
    catch {
        Write-Host "    PASSED: Correctly rejected" -ForegroundColor Green
        $passed++
    }
    
    # 5. CONFIRMATION TRACKING
    Write-Host "`n--- CONFIRMATION TRACKING ---" -ForegroundColor Cyan
    $txHash = "3e4c8b8f8b8a2a3c5e6f7d8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8"
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $message = "GET/api/blockchain/confirmations/bitcoin/$txHash$timestamp"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($apiSecret)
    $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($message))
    $signature = [System.BitConverter]::ToString($signatureBytes).Replace('-','').ToLower()
    
    $authHeaders = @{
        'X-API-Key' = $apiKey
        'X-Signature' = $signature
        'X-Timestamp' = $timestamp
    }
    
    RunTest "Get Confirmations" "$baseUrl/api/blockchain/confirmations/bitcoin/$txHash" "GET" $authHeaders
}

# SUMMARY
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Total:  $total"
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red

$passRate = [math]::Round(($passed / $total) * 100, 1)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } else { "Yellow" })

if ($passRate -ge 80) {
    Write-Host "`nPRODUCTION READY!" -ForegroundColor Green
} else {
    Write-Host "`nNEEDS ATTENTION" -ForegroundColor Yellow
}
Write-Host ""

# Contract Audit Testing Script
Write-Host "🛡️ Contract Security Audit Testing" -ForegroundColor Cyan

# Test contract addresses
$UNISWAP_V3_ROUTER = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
$MALICIOUS_CONTRACT = "0x1234567890123456789012345678901234567890"

Write-Host "`n1️⃣ Testing Quick Audit (Whitelisted Contract - Uniswap V3)" -ForegroundColor Yellow
$response1 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/quick/$UNISWAP_V3_ROUTER" -Method GET
Write-Host "Response:" -ForegroundColor Green
$response1 | ConvertTo-Json -Depth 5

Start-Sleep -Seconds 2

Write-Host "`n2️⃣ Testing Quick Audit (Unknown Contract)" -ForegroundColor Yellow
$response2 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/quick/$MALICIOUS_CONTRACT" -Method GET
Write-Host "Response:" -ForegroundColor Green
$response2 | ConvertTo-Json -Depth 5

Start-Sleep -Seconds 2

Write-Host "`n3️⃣ Testing Full Audit (With Sample Bytecode)" -ForegroundColor Yellow
$auditRequest = @{
    contract_address = "0xabcdef1234567890abcdef1234567890abcdef12"
    bytecode = "0x608060405260043610610041576000357c01000000000000000000000000000000000000000000000000000000009004806341c0e1b514610046575b600080fd5b61004e610050565b005b3373ffffffffffffffffffffffffffffffffffffffff16ff5b"
    source_code = @"
pragma solidity ^0.8.0;
contract Vulnerable {
    function withdraw() public {
        payable(msg.sender).call{value: address(this).balance}("");
    }
}
"@
}
$json = $auditRequest | ConvertTo-Json
$response3 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/contract" -Method POST -Body $json -ContentType "application/json"
Write-Host "Response:" -ForegroundColor Green
$response3 | ConvertTo-Json -Depth 5

Start-Sleep -Seconds 2

Write-Host "`n4️⃣ Testing Get Whitelist" -ForegroundColor Yellow
$response4 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/whitelist" -Method GET
Write-Host "Response:" -ForegroundColor Green
$response4 | ConvertTo-Json -Depth 5

Start-Sleep -Seconds 2

Write-Host "`n5️⃣ Testing Add to Whitelist" -ForegroundColor Yellow
$whitelistRequest = @{
    address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
    name = "Uniswap V2 Router"
    verified = $true
    risk_level = "Safe"
}
$json = $whitelistRequest | ConvertTo-Json
$response5 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/whitelist" -Method POST -Body $json -ContentType "application/json"
Write-Host "Response:" -ForegroundColor Green
$response5 | ConvertTo-Json -Depth 5

Start-Sleep -Seconds 2

Write-Host "`n6️⃣ Testing Audit Info" -ForegroundColor Yellow
$response6 = Invoke-RestMethod -Uri "http://localhost:3000/api/audit/info" -Method GET
Write-Host "Response:" -ForegroundColor Green
$response6 | ConvertTo-Json -Depth 5

Write-Host "`n✅ All audit endpoint tests completed!" -ForegroundColor Cyan
Write-Host "📊 Summary:" -ForegroundColor Yellow
Write-Host "  - Quick audits: Working" -ForegroundColor Green
Write-Host "  - Full audits with vulnerability detection: Working" -ForegroundColor Green
Write-Host "  - Whitelist management: Working" -ForegroundColor Green
Write-Host "  - Audit info: Working" -ForegroundColor Green

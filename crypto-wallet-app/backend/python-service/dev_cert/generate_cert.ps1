# generate_cert.ps1
# Creates a self-signed certificate for localhost for uvicorn (prefers OpenSSL)
# Usage: Run in PowerShell (may require admin for some operations)

$cwd = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $cwd

function Has-Command($name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

if (Has-Command 'openssl') {
    Write-Host "OpenSSL found. Generating key.pem and cert.pem..."
    # Create key and cert without passphrase
    & openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Generated key.pem and cert.pem in $pwd"
        Write-Host "Run uvicorn with:"
        Write-Host "python -m uvicorn app:app --host 127.0.0.1 --port 8001 --ssl-keyfile dev_cert\key.pem --ssl-certfile dev_cert\cert.pem"
    } else {
        Write-Error "OpenSSL failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Warning "OpenSSL not found on PATH. Falling back to PowerShell instructions."
    Write-Host "You can install OpenSSL (recommended) or run the following to create a PFX and then extract PEM using OpenSSL on a machine that has it."
    Write-Host "PowerShell command (requires admin to write to LocalMachine) to create a PFX:"
    Write-Host "  $cert = New-SelfSignedCertificate -DnsName 'localhost' -CertStoreLocation Cert:\LocalMachine\My"
    Write-Host "  $pwd = ConvertTo-SecureString -String 'changeit' -Force -AsPlainText"
    Write-Host "  Export-PfxCertificate -Cert $cert -FilePath .\\dev_cert\certificate.pfx -Password $pwd"
    Write-Host "To convert the PFX to PEM on a machine with OpenSSL:"
    Write-Host "  openssl pkcs12 -in certificate.pfx -nocerts -nodes -out key.pem"
    Write-Host "  openssl pkcs12 -in certificate.pfx -clcerts -nokeys -out cert.pem"
    Write-Host "Then run uvicorn as shown in the README."
}

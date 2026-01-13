# Dev TLS for python-service

This folder contains a simple PowerShell helper to create a self-signed certificate (PEM key + cert) suitable for running the FastAPI `uvicorn` server locally with TLS.

Two methods are supported:

1) OpenSSL (recommended)

   - If you have `openssl` installed and on PATH, the script will use it to create `cert.pem` and `key.pem` in the current folder.
   - Command created by the script (example):

```powershell
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost"
```

2) PowerShell fallback

   - If `openssl` is not available, the script will print instructions to create a self-signed certificate via `New-SelfSignedCertificate` and export a PFX. Note: extracting a PEM private key from the Windows Certificate Store is non-trivial; OpenSSL is recommended.

How to run `uvicorn` with the generated files

- Once you have `key.pem` and `cert.pem` in `backend/python-service/dev_cert/`, run uvicorn with:

```powershell
cd C:\Users\RICO\ricoamos\crypto-wallet-app\backend\python-service
python -m uvicorn app:app --host 127.0.0.1 --port 8001 --ssl-keyfile dev_cert\key.pem --ssl-certfile dev_cert\cert.pem
```

Browser / mobile testing

- For browsers you may need to add a security exception for the self-signed cert. For mobile emulators, ensure the emulator trusts the cert or use the device's developer options.

Security note

- These certificates are for local development only. Do NOT use them in production.

Python-based certificate generator (no OpenSSL required)

If you don't want to install OpenSSL or run commands that require admin, a small Python script is provided that generates a self-signed PEM key & certificate using the `cryptography` package.

Steps:

1. Install the dependency (user install avoids needing admin):

```powershell
python -m pip install --user cryptography
```

2. Run the generator (the script writes `key.pem` and `cert.pem` into this folder):

```powershell
cd C:\Users\RICO\ricoamos\crypto-wallet-app\backend\python-service\dev_cert
python make_cert.py
```

3. Start uvicorn with the generated files (same as above):

```powershell
cd C:\Users\RICO\ricoamos\crypto-wallet-app\backend\python-service
python -m uvicorn app:app --host 127.0.0.1 --port 8001 --ssl-keyfile dev_cert\key.pem --ssl-certfile dev_cert\cert.pem
```

This method is convenient for local development and does not require elevated privileges. Remember to accept the self-signed certificate in your browser when testing.

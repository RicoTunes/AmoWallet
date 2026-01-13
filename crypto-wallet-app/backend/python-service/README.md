Python service for crypto helpers using the Rust worker binary.

Quick start (local, requires Rust binary built):

1. Build Rust binary (from backend):

   cargo build --release --manifest-path ./rust/Cargo.toml

2. Install dependencies and run:

   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   python app.py

Or with Docker (will not build Rust binary for you):

   docker build -t python-crypto-service .
   docker run --rm -p 8000:8000 python-crypto-service

Environment variables:
- RUST_BIN_PATH: optional path to the rust worker binary. Defaults to ../rust/target/release/crypto_wallet_cli(.exe)
- RUST_POOL_SIZE: number of worker processes to spawn (default 2)

Endpoints:
- GET /health
- POST /generate -> returns { privateKey, publicKey }
- POST /sign -> { privateKey, message } -> { signature }
- POST /verify -> { publicKey, message, signature } -> { valid }

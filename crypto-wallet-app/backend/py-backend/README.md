Python replacement backend for the crypto wallet app.

This service exposes the same API surface as the Node backend (health + /api/wallet endpoints) and delegates crypto operations to the Rust worker binary in `../rust/target/release/` by default.

Quick start (requires Rust binary built or set RUST_BIN_PATH):

1. Build Rust binary or set RUST_BIN_PATH environment variable.
2. Create venv and install deps:

   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt

3. Run:

   python app.py

Docker:

   docker build -t py-backend .
   docker run --rm -p 3000:3000 py-backend

Notes:
- If you want a pure-Python crypto implementation, tell me and I'll swap out the Rust worker pool for Python-native ECDSA.

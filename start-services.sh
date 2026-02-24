#!/bin/sh
# =============================================================================
# AmoWallet startup — launches Rust security server, then Node.js
# Both run inside the same container; Rust on 127.0.0.1:8443 (internal only)
# =============================================================================

set -e

RUST_PORT="${RUST_HTTPS_PORT:-8443}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AmoWallet — Starting services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Start Rust security server in background ────────────────────────────────
echo "[1/2] Starting Rust security server on 127.0.0.1:${RUST_PORT}..."
crypto_wallet_cli server &
RUST_PID=$!

# Wait for Rust to be ready (up to 10 seconds)
for i in $(seq 1 20); do
  if wget -q --spider "http://127.0.0.1:${RUST_PORT}/health" 2>/dev/null; then
    echo "  -> Rust server ready (PID ${RUST_PID})"
    break
  fi
  if ! kill -0 "$RUST_PID" 2>/dev/null; then
    echo "  -> WARNING: Rust server exited early, continuing with Node.js only"
    break
  fi
  sleep 0.5
done

# ── Start Node.js (foreground — Docker watches this process) ────────────────
echo "[2/2] Starting Node.js server on 0.0.0.0:${PORT:-3000}..."
exec node server.js

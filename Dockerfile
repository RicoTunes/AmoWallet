# =============================================================================
# AmoWallet Backend — Node.js + Rust Security Server (single container)
# Cache bust: v4 - 2026-02-23
# =============================================================================

# ── Stage 1: Build Rust binary ──────────────────────────────────────────────
FROM rust:1.83-bookworm AS rust-builder

WORKDIR /build

# Copy only Cargo manifests first for layer caching
COPY Cargo.toml rust-toolchain.toml ./
COPY crypto-wallet-app/backend/rust/ crypto-wallet-app/backend/rust/
COPY src/ src/

# Build release binary
RUN cargo build --release --bin crypto_wallet_cli \
    && strip target/release/crypto_wallet_cli

# ── Stage 2: Production image ──────────────────────────────────────────────
FROM node:20-bookworm-slim

# Install minimal runtime deps for the Rust binary (glibc already present)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Rust binary from builder
COPY --from=rust-builder /build/target/release/crypto_wallet_cli /usr/local/bin/crypto_wallet_cli
RUN chmod +x /usr/local/bin/crypto_wallet_cli

# Copy Node.js backend
COPY crypto-wallet-app/backend/package*.json ./
RUN rm -rf node_modules && npm install --legacy-peer-deps --production
COPY crypto-wallet-app/backend/ ./

# Copy startup script
COPY start-services.sh /app/start-services.sh
RUN chmod +x /app/start-services.sh

# Environment
ENV NODE_ENV=production
ENV PORT=3000
ENV RUST_HTTPS_PORT=8443

# Expose Node.js port (Rust listens on 127.0.0.1:8443 — internal only)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start both services
CMD ["/app/start-services.sh"]

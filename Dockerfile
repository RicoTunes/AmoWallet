# =============================================================================
# AmoWallet Backend — Node.js with built-in crypto signing
# Rust security server is optional; Node.js handles all signing natively.
# Cache bust: v5 - 2026-03-10
# =============================================================================

FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Node.js backend
COPY crypto-wallet-app/backend/package*.json ./
RUN rm -rf node_modules && npm install --legacy-peer-deps --production
COPY crypto-wallet-app/backend/ ./

# Environment
ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start Node.js directly
CMD ["node", "server.js"]

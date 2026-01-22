# AmoWallet Backend - Node.js Only
# Cache bust: v3 - 2026-01-22
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files from backend
COPY crypto-wallet-app/backend/package*.json ./

# Install dependencies - force fresh install
RUN rm -rf node_modules && npm install --legacy-peer-deps

# Copy backend source code
COPY crypto-wallet-app/backend/ ./

# Verify the fix is applied (will show in build logs)
RUN head -15 src/routes/blockchainRoutes.js

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the server
CMD ["node", "server.js"]

# AmoWallet Backend - Node.js Only
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files from backend
COPY crypto-wallet-app/backend/package*.json ./

# Install dependencies
RUN npm ci --legacy-peer-deps || npm install --legacy-peer-deps

# Copy backend source code
COPY crypto-wallet-app/backend/ ./

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

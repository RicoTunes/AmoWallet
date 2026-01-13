#!/bin/bash

# Production Deployment Script for Crypto Wallet Pro
# This script automates the deployment process

set -e  # Exit on error

echo "🚀 Crypto Wallet Pro - Production Deployment"
echo "============================================="

# Configuration
APP_DIR="/home/$(logname)/ricoamos/crypto-wallet-app/backend"
SERVICE_NAME="crypto-wallet-backend"
NODE_ENV="production"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if running in correct directory
if [ ! -f "$APP_DIR/package.json" ]; then
    log_error "Error: Backend directory not found at $APP_DIR"
    exit 1
fi

cd "$APP_DIR"

# Step 1: Pre-deployment checks
echo ""
echo "📋 Step 1: Pre-deployment checks..."

# Check Node.js
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed"
    exit 1
else
    NODE_VERSION=$(node -v)
    log_info "Node.js version: $NODE_VERSION"
fi

# Check npm
if ! command -v npm &> /dev/null; then
    log_error "npm is not installed"
    exit 1
else
    NPM_VERSION=$(npm -v)
    log_info "npm version: $NPM_VERSION"
fi

# Check .env.production
if [ ! -f "$APP_DIR/.env.production" ]; then
    log_warn ".env.production not found"
    if [ -f "$APP_DIR/.env.production.example" ]; then
        echo "   Copy .env.production.example to .env.production and configure it"
    fi
    exit 1
else
    log_info ".env.production exists"
fi

# Step 2: Backup current deployment
echo ""
echo "💾 Step 2: Creating backup..."
BACKUP_DIR="$HOME/crypto-wallet-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup .env file
if [ -f "$APP_DIR/.env.production" ]; then
    cp "$APP_DIR/.env.production" "$BACKUP_DIR/"
    log_info "Environment file backed up"
fi

# Backup database (if PostgreSQL is running)
if command -v pg_dump &> /dev/null; then
    source "$APP_DIR/.env.production"
    if [ ! -z "$DATABASE_URL" ]; then
        pg_dump "$DATABASE_URL" > "$BACKUP_DIR/database_backup.sql" 2>/dev/null || log_warn "Database backup skipped"
        log_info "Database backed up"
    fi
fi

log_info "Backup created at $BACKUP_DIR"

# Step 3: Pull latest code (if git is used)
echo ""
echo "📥 Step 3: Pulling latest code..."
if [ -d "$APP_DIR/.git" ]; then
    git pull origin main || git pull origin master
    log_info "Code updated from repository"
else
    log_warn "Not a git repository, skipping pull"
fi

# Step 4: Install dependencies
echo ""
echo "📦 Step 4: Installing dependencies..."
npm ci --production
log_info "Dependencies installed"

# Step 5: Run database migrations
echo ""
echo "🗄️  Step 5: Running database migrations..."
if [ -f "$APP_DIR/scripts/run-migrations.sh" ]; then
    bash "$APP_DIR/scripts/run-migrations.sh"
    log_info "Database migrations completed"
else
    log_warn "No migration script found, skipping"
fi

# Step 6: Build assets (if needed)
echo ""
echo "🔨 Step 6: Building application..."
if [ -f "$APP_DIR/package.json" ] && grep -q "\"build\":" "$APP_DIR/package.json"; then
    npm run build
    log_info "Application built"
else
    log_info "No build step required"
fi

# Step 7: Stop existing service
echo ""
echo "🛑 Step 7: Stopping existing service..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl stop "$SERVICE_NAME"
    log_info "Service stopped"
else
    log_warn "Service not running"
fi

# Step 8: Start service
echo ""
echo "▶️  Step 8: Starting service..."
sudo systemctl start "$SERVICE_NAME"
sleep 3

# Check if service started successfully
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_info "Service started successfully"
else
    log_error "Service failed to start"
    sudo systemctl status "$SERVICE_NAME"
    exit 1
fi

# Step 9: Health check
echo ""
echo "🏥 Step 9: Running health checks..."
sleep 5  # Wait for service to fully start

# Check health endpoint
HEALTH_URL="http://localhost:3000/health"
if [ -f "$APP_DIR/.env.production" ]; then
    source "$APP_DIR/.env.production"
    if [ "$ENABLE_HTTPS" = "true" ]; then
        HEALTH_URL="https://localhost:${HTTPS_PORT:-443}/health"
    fi
fi

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
    log_info "Health check passed"
else
    log_error "Health check failed (HTTP $HEALTH_STATUS)"
    exit 1
fi

# Step 10: Verify database connection
echo ""
echo "🗄️  Step 10: Verifying database connection..."
DB_HEALTH=$(curl -s "$HEALTH_URL/db" | grep -o '"status":"healthy"' || echo "")
if [ ! -z "$DB_HEALTH" ]; then
    log_info "Database connection verified"
else
    log_warn "Database connection check failed"
fi

# Step 11: Clean up old backups (keep last 7 days)
echo ""
echo "🧹 Step 11: Cleaning up old backups..."
find "$HOME/crypto-wallet-backups" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
log_info "Old backups cleaned"

# Summary
echo ""
echo "============================================="
echo "✅ Deployment Complete!"
echo "============================================="
echo ""
echo "📊 Deployment Summary:"
echo "   Service: $SERVICE_NAME"
echo "   Status: $(systemctl is-active $SERVICE_NAME)"
echo "   Health: $HEALTH_URL"
echo "   Backup: $BACKUP_DIR"
echo ""
echo "📋 Useful Commands:"
echo "   View logs:     sudo journalctl -u $SERVICE_NAME -f"
echo "   Restart:       sudo systemctl restart $SERVICE_NAME"
echo "   Stop:          sudo systemctl stop $SERVICE_NAME"
echo "   Status:        sudo systemctl status $SERVICE_NAME"
echo ""
echo "🔗 Endpoints:"
echo "   Health:        $HEALTH_URL"
echo "   API:           ${HEALTH_URL/\/health/\/api}"
echo ""

# Create deployment log
cat > "$APP_DIR/last-deployment.log" << EOF
Deployment Log
==============
Date: $(date)
User: $(whoami)
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
Node Version: $NODE_VERSION
Backup Location: $BACKUP_DIR
Health Status: $HEALTH_STATUS
EOF

log_info "Deployment log saved to last-deployment.log"

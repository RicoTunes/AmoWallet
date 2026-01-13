#!/bin/bash

# Database Migration Runner for Crypto Wallet Pro
# Applies SQL migrations to PostgreSQL database

set -e  # Exit on error

echo "🗄️  Database Migration Runner"
echo "============================"

# Configuration
MIGRATIONS_DIR="$(dirname "$0")/../migrations"
ENV_FILE="$(dirname "$0")/../.env.production"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    echo "✅ Loaded environment from .env.production"
else
    echo "❌ Error: .env.production not found"
    exit 1
fi

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "❌ Error: DATABASE_URL not set in .env.production"
    exit 1
fi

echo "📂 Migrations directory: $MIGRATIONS_DIR"
echo ""

# Check if PostgreSQL client is available
if ! command -v psql &> /dev/null; then
    echo "❌ Error: psql (PostgreSQL client) not found"
    echo "   Install it with: sudo apt-get install postgresql-client"
    exit 1
fi

# Function to run a migration
run_migration() {
    local migration_file="$1"
    local migration_name=$(basename "$migration_file")
    
    echo "📄 Running migration: $migration_name"
    
    # Execute migration
    if psql "$DATABASE_URL" -f "$migration_file"; then
        echo "   ✅ Migration completed successfully"
        return 0
    else
        echo "   ❌ Migration failed"
        return 1
    fi
}

# Get list of migration files (sorted)
migrations=($(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort))

if [ ${#migrations[@]} -eq 0 ]; then
    echo "⚠️  No migration files found in $MIGRATIONS_DIR"
    exit 0
fi

echo "Found ${#migrations[@]} migration(s)"
echo ""

# Create schema_migrations table if it doesn't exist
echo "🔧 Ensuring schema_migrations table exists..."
psql "$DATABASE_URL" -c "
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
" > /dev/null

echo "✅ Schema migrations table ready"
echo ""

# Run each migration
successful_migrations=0
failed_migrations=0

for migration_file in "${migrations[@]}"; do
    migration_name=$(basename "$migration_file")
    migration_version=$(echo "$migration_name" | grep -o '^[0-9]\+')
    
    # Check if migration already applied
    already_applied=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM schema_migrations WHERE version = $migration_version;" | xargs)
    
    if [ "$already_applied" -gt 0 ]; then
        echo "⏭️  Skipping $migration_name (already applied)"
        continue
    fi
    
    # Run migration
    if run_migration "$migration_file"; then
        ((successful_migrations++))
    else
        ((failed_migrations++))
        echo "❌ Stopping at failed migration: $migration_name"
        break
    fi
    
    echo ""
done

# Summary
echo "============================"
echo "📊 Migration Summary"
echo "============================"
echo "✅ Successful: $successful_migrations"
echo "❌ Failed: $failed_migrations"
echo ""

if [ $failed_migrations -eq 0 ]; then
    echo "✅ All migrations completed successfully!"
    
    # Show applied migrations
    echo ""
    echo "📋 Applied Migrations:"
    psql "$DATABASE_URL" -c "SELECT version, name, applied_at FROM schema_migrations ORDER BY version;"
    
    exit 0
else
    echo "❌ Some migrations failed. Please check the errors above."
    exit 1
fi

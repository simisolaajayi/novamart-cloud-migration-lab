#!/bin/bash
# ============================================================
# NovaMart Phase 2 — PostgreSQL Database Migration Script
# ============================================================
#
# PURPOSE:
#   Migrates the NovaMart inventory database schema from SQLite
#   (used in Phase 1) to PostgreSQL on Amazon RDS.
#
# KEY DIFFERENCES: SQLite vs PostgreSQL
# ---------------------------------------------------------------
# | Feature          | SQLite                | PostgreSQL         |
# |------------------|-----------------------|--------------------|
# | Auto-increment   | AUTOINCREMENT         | SERIAL             |
# | Decimal numbers  | REAL                  | NUMERIC(10,2)      |
# | Timestamps       | TEXT                  | TIMESTAMP          |
# | Default time     | datetime('now')       | CURRENT_TIMESTAMP  |
# | Boolean          | INTEGER (0/1)         | BOOLEAN            |
# | String types     | TEXT (no length)      | VARCHAR(n) / TEXT  |
# ---------------------------------------------------------------
#
# WHY POSTGRESQL OVER SQLITE FOR PRODUCTION?
#   - SQLite allows only ONE writer at a time (no concurrent writes)
#   - SQLite has no network access (must run on the same machine)
#   - SQLite has no user management or access control
#   - SQLite has no replication for high availability
#   - PostgreSQL solves ALL of these limitations
#
# USAGE:
#   Set the following environment variables before running:
#     PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
#   Or pass them on the command line:
#     PGHOST=mydb.xxx.rds.amazonaws.com PGUSER=admin ... ./migrate-database.sh
#
# ============================================================
set -euo pipefail

echo "============================================"
echo " NovaMart Database Migration (SQLite -> PostgreSQL)"
echo "============================================"
echo ""
echo "Connecting to: ${PGHOST:-not set}:${PGPORT:-5432}/${PGDATABASE:-not set}"
echo ""

# ----------------------------------------------------------
# Step 1: Create the products table (PostgreSQL syntax)
# ----------------------------------------------------------
# NOTES FOR STUDENTS:
#   - SERIAL replaces SQLite's INTEGER PRIMARY KEY AUTOINCREMENT
#     SERIAL automatically creates a sequence and sets the default
#   - NUMERIC(10,2) gives us exact decimal precision for prices
#     (SQLite's REAL is a floating point — bad for money!)
#   - TIMESTAMP WITH TIME ZONE replaces SQLite's TEXT for dates
#     PostgreSQL stores timezone-aware timestamps natively
#   - VARCHAR(n) enforces a max length, unlike SQLite's TEXT
#   - IF NOT EXISTS makes the script safe to run multiple times

echo ">>> Step 1: Creating products table..."

psql <<'SQL'
CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    category    VARCHAR(100) NOT NULL,
    price       NUMERIC(10, 2) NOT NULL,
    stock       INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
SQL

echo "    Products table created (or already exists)."
echo ""

# ----------------------------------------------------------
# Step 2: Insert the 15 NovaMart products
# ----------------------------------------------------------
# We use ON CONFLICT DO NOTHING so this script is idempotent —
# running it twice won't create duplicate products.

echo ">>> Step 2: Inserting NovaMart product catalog..."

psql <<'SQL'
INSERT INTO products (name, category, price, stock, description) VALUES
    ('Organic Whole Milk',        'Dairy',       4.99,  150, 'Farm-fresh organic whole milk, 1 gallon'),
    ('Free Range Eggs',           'Dairy',       5.49,  200, 'Free range large eggs, dozen'),
    ('Sourdough Bread',           'Bakery',      6.99,   75, 'Artisan sourdough bread, freshly baked'),
    ('Atlantic Salmon Fillet',    'Seafood',    12.99,   40, 'Fresh Atlantic salmon, per pound'),
    ('Baby Spinach',              'Produce',     3.49,  180, 'Organic baby spinach, 5oz container'),
    ('Greek Yogurt',              'Dairy',       1.99,  300, 'Plain Greek yogurt, 6oz cup'),
    ('Chicken Breast',            'Meat',        8.99,   90, 'Boneless skinless chicken breast, per pound'),
    ('Avocados',                  'Produce',     1.50,  200, 'Ripe Hass avocados, each'),
    ('Cheddar Cheese',            'Dairy',       5.99,  120, 'Aged sharp cheddar cheese, 8oz block'),
    ('Pasta Sauce',               'Pantry',      3.99,  250, 'Marinara pasta sauce, 24oz jar'),
    ('Brown Rice',                'Pantry',      4.49,  175, 'Long grain brown rice, 2lb bag'),
    ('Almond Butter',             'Pantry',      9.99,   60, 'Creamy almond butter, 16oz jar'),
    ('Mixed Berries',             'Produce',     5.99,   85, 'Fresh mixed berries, 12oz container'),
    ('Sparkling Water',           'Beverages',   4.99,  400, 'Sparkling mineral water, 12-pack'),
    ('Dark Chocolate Bar',        'Snacks',      3.49,  150, '72% cacao dark chocolate, 3.5oz bar')
ON CONFLICT DO NOTHING;
SQL

echo "    Product catalog inserted."
echo ""

# ----------------------------------------------------------
# Step 3: Verify the migration
# ----------------------------------------------------------
echo ">>> Step 3: Verifying migration..."
echo ""

PRODUCT_COUNT=$(psql -t -A -c "SELECT count(*) FROM products;")
echo "    Total products in database: ${PRODUCT_COUNT}"
echo ""

echo "    Sample products:"
psql -c "SELECT id, name, category, price, stock FROM products ORDER BY id LIMIT 5;"

echo ""
echo "============================================"
echo " Migration complete!"
echo " ${PRODUCT_COUNT} products loaded into RDS PostgreSQL"
echo "============================================"

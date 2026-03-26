-- ============================================================================
-- NovaMart Inventory Management System — Database Schema & Seed Data
-- ============================================================================
-- This file serves as a reference for the on-premises database schema.
-- The application creates the database programmatically on startup, but this
-- file documents the schema for migration planning purposes.
-- ============================================================================

CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    sku TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,
    price REAL NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    location TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------------
-- Seed Data — 15 products across 5 categories and 5 store locations
-- ---------------------------------------------------------------------------

-- Electronics
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Wireless Bluetooth Headphones', 'NM-ELEC-001', 'Electronics', 79.99, 45, 'NYC-001');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('4K Smart TV 55-inch', 'NM-ELEC-002', 'Electronics', 549.99, 12, 'LA-002');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('USB-C Laptop Charger', 'NM-ELEC-003', 'Electronics', 34.99, 150, 'CHI-003');

-- Clothing
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Men''s Classic Denim Jacket', 'NM-CLTH-001', 'Clothing', 89.99, 67, 'NYC-001');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Women''s Running Shoes', 'NM-CLTH-002', 'Clothing', 119.99, 23, 'MIA-005');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Cotton Crew Neck T-Shirt', 'NM-CLTH-003', 'Clothing', 24.99, 200, 'HOU-004');

-- Home & Kitchen
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Stainless Steel Cookware Set', 'NM-HOME-001', 'Home & Kitchen', 199.99, 8, 'LA-002');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Memory Foam Pillow', 'NM-HOME-002', 'Home & Kitchen', 39.99, 95, 'CHI-003');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Cordless Vacuum Cleaner', 'NM-HOME-003', 'Home & Kitchen', 249.99, 5, 'NYC-001');

-- Sports
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Yoga Mat Premium', 'NM-SPRT-001', 'Sports', 29.99, 180, 'MIA-005');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Adjustable Dumbbells Set', 'NM-SPRT-002', 'Sports', 159.99, 3, 'HOU-004');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Basketball Indoor/Outdoor', 'NM-SPRT-003', 'Sports', 34.99, 72, 'LA-002');

-- Grocery
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Organic Coffee Beans 1lb', 'NM-GROC-001', 'Grocery', 14.99, 300, 'CHI-003');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Extra Virgin Olive Oil', 'NM-GROC-002', 'Grocery', 12.99, 88, 'HOU-004');
INSERT INTO products (name, sku, category, price, quantity, location) VALUES
    ('Mixed Nuts Trail Mix', 'NM-GROC-003', 'Grocery', 8.99, 250, 'MIA-005');

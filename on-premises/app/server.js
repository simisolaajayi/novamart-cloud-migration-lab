const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'on-premises';

// Middleware
app.use(cors());
app.use(helmet());
app.use(express.json());

// ---------------------------------------------------------------------------
// Database Setup
// ---------------------------------------------------------------------------
const dbPath = process.env.DB_PATH || path.join(__dirname, 'data', 'inventory.db');

function initializeDatabase(dbInstance) {
  dbInstance.exec(`
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
    )
  `);

  const count = dbInstance.prepare('SELECT COUNT(*) as cnt FROM products').get();
  if (count.cnt === 0) {
    const insert = dbInstance.prepare(
      'INSERT INTO products (name, sku, category, price, quantity, location) VALUES (?, ?, ?, ?, ?, ?)'
    );

    const seedData = [
      ['Wireless Bluetooth Headphones', 'NM-ELEC-001', 'Electronics', 79.99, 45, 'NYC-001'],
      ['4K Smart TV 55-inch', 'NM-ELEC-002', 'Electronics', 549.99, 12, 'LA-002'],
      ['USB-C Laptop Charger', 'NM-ELEC-003', 'Electronics', 34.99, 150, 'CHI-003'],
      ["Men's Classic Denim Jacket", 'NM-CLTH-001', 'Clothing', 89.99, 67, 'NYC-001'],
      ["Women's Running Shoes", 'NM-CLTH-002', 'Clothing', 119.99, 23, 'MIA-005'],
      ['Cotton Crew Neck T-Shirt', 'NM-CLTH-003', 'Clothing', 24.99, 200, 'HOU-004'],
      ['Stainless Steel Cookware Set', 'NM-HOME-001', 'Home & Kitchen', 199.99, 8, 'LA-002'],
      ['Memory Foam Pillow', 'NM-HOME-002', 'Home & Kitchen', 39.99, 95, 'CHI-003'],
      ['Cordless Vacuum Cleaner', 'NM-HOME-003', 'Home & Kitchen', 249.99, 5, 'NYC-001'],
      ['Yoga Mat Premium', 'NM-SPRT-001', 'Sports', 29.99, 180, 'MIA-005'],
      ['Adjustable Dumbbells Set', 'NM-SPRT-002', 'Sports', 159.99, 3, 'HOU-004'],
      ['Basketball Indoor/Outdoor', 'NM-SPRT-003', 'Sports', 34.99, 72, 'LA-002'],
      ['Organic Coffee Beans 1lb', 'NM-GROC-001', 'Grocery', 14.99, 300, 'CHI-003'],
      ['Extra Virgin Olive Oil', 'NM-GROC-002', 'Grocery', 12.99, 88, 'HOU-004'],
      ['Mixed Nuts Trail Mix', 'NM-GROC-003', 'Grocery', 8.99, 250, 'MIA-005'],
    ];

    const insertMany = dbInstance.transaction((rows) => {
      for (const row of rows) {
        insert.run(...row);
      }
    });
    insertMany(seedData);
  }

  return dbInstance;
}

let db;
if (process.env.NODE_ENV === 'test') {
  db = new Database(':memory:');
} else {
  const fs = require('fs');
  const dataDir = path.dirname(dbPath);
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
  db = new Database(dbPath);
}

initializeDatabase(db);

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Health check
app.get('/health', (req, res) => {
  let dbStatus = 'disconnected';
  try {
    db.prepare('SELECT 1').get();
    dbStatus = 'connected';
  } catch (err) {
    dbStatus = 'disconnected';
  }

  res.json({
    service: 'NovaMart Inventory System',
    version: '1.0.0',
    environment: ENVIRONMENT,
    database: dbStatus,
    uptime: process.uptime(),
  });
});

// GET /api/products — list all products with optional filters
app.get('/api/products', (req, res) => {
  const { category, location } = req.query;
  let sql = 'SELECT * FROM products WHERE 1=1';
  const params = [];

  if (category) {
    sql += ' AND category = ?';
    params.push(category);
  }
  if (location) {
    sql += ' AND location = ?';
    params.push(location);
  }

  sql += ' ORDER BY id';
  const products = db.prepare(sql).all(...params);
  res.json({ products, count: products.length });
});

// GET /api/products/:id — single product
app.get('/api/products/:id', (req, res) => {
  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!product) {
    return res.status(404).json({ error: 'Product not found' });
  }
  res.json({ product });
});

// POST /api/products — create product
app.post('/api/products', (req, res) => {
  const { name, sku, category, price, quantity, location } = req.body;

  const missing = [];
  if (!name) missing.push('name');
  if (!sku) missing.push('sku');
  if (!category) missing.push('category');
  if (price === undefined || price === null) missing.push('price');
  if (quantity === undefined || quantity === null) missing.push('quantity');
  if (!location) missing.push('location');

  if (missing.length > 0) {
    return res.status(400).json({ error: 'Missing required fields', fields: missing });
  }

  try {
    const result = db.prepare(
      'INSERT INTO products (name, sku, category, price, quantity, location) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(name, sku, category, price, quantity, location);

    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json({ product });
  } catch (err) {
    if (err.message.includes('UNIQUE constraint')) {
      return res.status(409).json({ error: 'Product with this SKU already exists' });
    }
    res.status(500).json({ error: 'Failed to create product' });
  }
});

// PUT /api/products/:id — update product (partial updates OK)
app.put('/api/products/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!existing) {
    return res.status(404).json({ error: 'Product not found' });
  }

  const fields = ['name', 'sku', 'category', 'price', 'quantity', 'location'];
  const updates = [];
  const values = [];

  for (const field of fields) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }

  if (updates.length === 0) {
    return res.status(400).json({ error: 'No fields to update' });
  }

  updates.push("updated_at = datetime('now')");
  values.push(req.params.id);

  db.prepare(`UPDATE products SET ${updates.join(', ')} WHERE id = ?`).run(...values);

  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  res.json({ product });
});

// DELETE /api/products/:id — delete product
app.delete('/api/products/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!existing) {
    return res.status(404).json({ error: 'Product not found' });
  }

  db.prepare('DELETE FROM products WHERE id = ?').run(req.params.id);
  res.json({ message: 'Product deleted', product: existing });
});

// GET /api/inventory — inventory summary
app.get('/api/inventory', (req, res) => {
  const totalProducts = db.prepare('SELECT COUNT(*) as count FROM products').get().count;
  const totalValue = db.prepare('SELECT SUM(price * quantity) as value FROM products').get().value;
  const lowStockItems = db.prepare('SELECT * FROM products WHERE quantity < 10 ORDER BY quantity ASC').all();
  const byCategory = db.prepare(
    'SELECT category, COUNT(*) as product_count, SUM(quantity) as total_quantity, SUM(price * quantity) as total_value FROM products GROUP BY category ORDER BY category'
  ).all();

  res.json({
    summary: {
      total_products: totalProducts,
      total_value: totalValue,
      low_stock_count: lowStockItems.length,
    },
    low_stock_items: lowStockItems,
    by_category: byCategory,
  });
});

// POST /api/inventory/restock — restock a product
app.post('/api/inventory/restock', (req, res) => {
  const { product_id, quantity } = req.body;

  if (!product_id) {
    return res.status(400).json({ error: 'product_id is required' });
  }
  if (!quantity || quantity <= 0) {
    return res.status(400).json({ error: 'quantity must be a positive number' });
  }

  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(product_id);
  if (!product) {
    return res.status(404).json({ error: 'Product not found' });
  }

  db.prepare("UPDATE products SET quantity = quantity + ?, updated_at = datetime('now') WHERE id = ?").run(quantity, product_id);

  const updated = db.prepare('SELECT * FROM products WHERE id = ?').get(product_id);
  res.json({
    message: 'Product restocked successfully',
    product: updated,
    added: quantity,
    previous_quantity: product.quantity,
    new_quantity: updated.quantity,
  });
});

// GET /api/locations — list all store locations with product counts
app.get('/api/locations', (req, res) => {
  const locations = db.prepare(
    'SELECT location, COUNT(*) as product_count, SUM(quantity) as total_quantity FROM products GROUP BY location ORDER BY location'
  ).all();
  res.json({ locations, count: locations.length });
});

// GET /api/locations/:id/products — products at a specific location
app.get('/api/locations/:id/products', (req, res) => {
  const products = db.prepare('SELECT * FROM products WHERE location = ? ORDER BY id').all(req.params.id);
  res.json({ location: req.params.id, products, count: products.length });
});

// ---------------------------------------------------------------------------
// Start server (only when not imported for testing)
// ---------------------------------------------------------------------------
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`NovaMart Inventory System running on port ${PORT}`);
    console.log(`Environment: ${ENVIRONMENT}`);
  });
}

module.exports = { app, db, initializeDatabase };

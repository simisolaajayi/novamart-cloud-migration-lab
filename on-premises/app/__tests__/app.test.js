const request = require('supertest');

// Force test environment before loading the app
process.env.NODE_ENV = 'test';
process.env.ENVIRONMENT = 'test';

const { app, db } = require('../server');

afterAll(() => {
  db.close();
});

describe('NovaMart Inventory API', () => {
  // -----------------------------------------------------------------------
  // 1. Health check
  // -----------------------------------------------------------------------
  test('GET /health — returns 200 with service name and database connected', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.service).toBe('NovaMart Inventory System');
    expect(res.body.database).toBe('connected');
    expect(res.body.version).toBe('1.0.0');
  });

  // -----------------------------------------------------------------------
  // 2. List all products
  // -----------------------------------------------------------------------
  test('GET /api/products — returns all 15 products', async () => {
    const res = await request(app).get('/api/products');
    expect(res.status).toBe(200);
    expect(res.body.products).toHaveLength(15);
    expect(res.body.count).toBe(15);
  });

  // -----------------------------------------------------------------------
  // 3. Filter by category
  // -----------------------------------------------------------------------
  test('GET /api/products?category=Electronics — filters by category (3 products)', async () => {
    const res = await request(app).get('/api/products?category=Electronics');
    expect(res.status).toBe(200);
    expect(res.body.products).toHaveLength(3);
    res.body.products.forEach((p) => {
      expect(p.category).toBe('Electronics');
    });
  });

  // -----------------------------------------------------------------------
  // 4. Filter by location
  // -----------------------------------------------------------------------
  test('GET /api/products?location=NYC-001 — filters by location', async () => {
    const res = await request(app).get('/api/products?location=NYC-001');
    expect(res.status).toBe(200);
    expect(res.body.products.length).toBeGreaterThan(0);
    res.body.products.forEach((p) => {
      expect(p.location).toBe('NYC-001');
    });
  });

  // -----------------------------------------------------------------------
  // 5. Get single product
  // -----------------------------------------------------------------------
  test('GET /api/products/1 — returns single product', async () => {
    const res = await request(app).get('/api/products/1');
    expect(res.status).toBe(200);
    expect(res.body.product).toBeDefined();
    expect(res.body.product.id).toBe(1);
    expect(res.body.product.name).toBe('Wireless Bluetooth Headphones');
  });

  // -----------------------------------------------------------------------
  // 6. Product not found
  // -----------------------------------------------------------------------
  test('GET /api/products/999 — returns 404', async () => {
    const res = await request(app).get('/api/products/999');
    expect(res.status).toBe(404);
    expect(res.body.error).toBe('Product not found');
  });

  // -----------------------------------------------------------------------
  // 7. Create product
  // -----------------------------------------------------------------------
  test('POST /api/products — creates new product successfully', async () => {
    const newProduct = {
      name: 'Test Widget',
      sku: 'NM-TEST-001',
      category: 'Electronics',
      price: 19.99,
      quantity: 50,
      location: 'NYC-001',
    };

    const res = await request(app).post('/api/products').send(newProduct);
    expect(res.status).toBe(201);
    expect(res.body.product).toBeDefined();
    expect(res.body.product.name).toBe('Test Widget');
    expect(res.body.product.sku).toBe('NM-TEST-001');
  });

  // -----------------------------------------------------------------------
  // 8. Create product — missing fields
  // -----------------------------------------------------------------------
  test('POST /api/products — returns 400 for missing required fields', async () => {
    const res = await request(app).post('/api/products').send({ name: 'Incomplete' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Missing required fields');
    expect(res.body.fields).toContain('sku');
  });

  // -----------------------------------------------------------------------
  // 9. Update product
  // -----------------------------------------------------------------------
  test('PUT /api/products/1 — updates product', async () => {
    const res = await request(app).put('/api/products/1').send({ price: 69.99 });
    expect(res.status).toBe(200);
    expect(res.body.product.price).toBe(69.99);
    expect(res.body.product.id).toBe(1);
  });

  // -----------------------------------------------------------------------
  // 10. Inventory summary
  // -----------------------------------------------------------------------
  test('GET /api/inventory — returns summary with low stock items', async () => {
    const res = await request(app).get('/api/inventory');
    expect(res.status).toBe(200);
    expect(res.body.summary).toBeDefined();
    expect(res.body.summary.total_products).toBeGreaterThanOrEqual(15);
    expect(res.body.summary.total_value).toBeGreaterThan(0);
    expect(res.body.low_stock_items).toBeDefined();
    expect(res.body.low_stock_items.length).toBeGreaterThanOrEqual(3);
    expect(res.body.by_category).toBeDefined();
  });

  // -----------------------------------------------------------------------
  // 11. Restock product
  // -----------------------------------------------------------------------
  test('POST /api/inventory/restock — restocks a product and increases quantity', async () => {
    // Get current quantity first
    const before = await request(app).get('/api/products/1');
    const previousQty = before.body.product.quantity;

    const res = await request(app)
      .post('/api/inventory/restock')
      .send({ product_id: 1, quantity: 25 });

    expect(res.status).toBe(200);
    expect(res.body.message).toBe('Product restocked successfully');
    expect(res.body.added).toBe(25);
    expect(res.body.new_quantity).toBe(previousQty + 25);
  });

  // -----------------------------------------------------------------------
  // 12. List locations
  // -----------------------------------------------------------------------
  test('GET /api/locations — returns list of locations with counts', async () => {
    const res = await request(app).get('/api/locations');
    expect(res.status).toBe(200);
    expect(res.body.locations).toBeDefined();
    expect(res.body.locations.length).toBeGreaterThanOrEqual(5);
    res.body.locations.forEach((loc) => {
      expect(loc.location).toBeDefined();
      expect(loc.product_count).toBeGreaterThan(0);
    });
  });
});

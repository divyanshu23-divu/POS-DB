-- =====================================================================
-- AuraPOS database  |  MySQL 8.0+  |  01_schema.sql
-- Designed from the AuraPOS React site (products, inventory, staff,
-- transactions, reports, settings, checkout).
-- DBMS topics: ER->relational, PK/FK, weak entity, 1:1, M:N resolution,
-- self-reference, CHECK/UNIQUE/DEFAULT, generated columns, indexes, 3NF.
-- =====================================================================
DROP DATABASE IF EXISTS pos;
CREATE DATABASE pos CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE pos;

-- ---------- Locations (multi-mall / multi-shop) ----------------------
CREATE TABLE Mall (
  mall_id   INT AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(100) NOT NULL,
  city      VARCHAR(60)  NOT NULL,
  CONSTRAINT uq_mall UNIQUE (name, city)
);

CREATE TABLE Shop (
  shop_id   INT AUTO_INCREMENT PRIMARY KEY,
  mall_id   INT NOT NULL,
  shop_name VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_shop_mall FOREIGN KEY (mall_id) REFERENCES Mall(mall_id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT uq_shop UNIQUE (mall_id, shop_name)
);

-- 1:1 with Shop -> everything on the site's "Settings" page
CREATE TABLE ShopSettings (
  shop_id               INT PRIMARY KEY,
  tagline               VARCHAR(150),
  address               VARCHAR(255),
  phone                 VARCHAR(20),
  email                 VARCHAR(100),
  gstin                 VARCHAR(20),
  currency              VARCHAR(5)   NOT NULL DEFAULT '₹',
  tax_rate_percent      DECIMAL(5,2) NOT NULL DEFAULT 5.00,
  low_stock_threshold   INT          NOT NULL DEFAULT 10,
  receipt_footer        VARCHAR(255) DEFAULT 'Thank you for shopping with us!',
  auto_print_receipt    BOOLEAN      NOT NULL DEFAULT FALSE,
  barcode_sound_enabled BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_settings_shop FOREIGN KEY (shop_id) REFERENCES Shop(shop_id) ON DELETE CASCADE,
  CONSTRAINT ck_tax   CHECK (tax_rate_percent BETWEEN 0 AND 100),
  CONSTRAINT ck_lowst CHECK (low_stock_threshold >= 0)
);

-- ---------- People ---------------------------------------------------
-- Roles come from the site: Staff page (Admin/Manager/Cashier/Staff)
CREATE TABLE Users (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(100) NOT NULL UNIQUE,
  phone         VARCHAR(20)  NOT NULL,
  password_hash VARCHAR(255) NOT NULL,          -- bcrypt/argon2, never plaintext
  role          ENUM('ADMIN','MANAGER','CASHIER','STAFF') NOT NULL DEFAULT 'CASHIER',
  status        ENUM('Active','Inactive') NOT NULL DEFAULT 'Active',
  last_active   DATETIME NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ck_phone CHECK (CHAR_LENGTH(phone) >= 10)
);

-- M:N resolution: which staff work in which shop
CREATE TABLE StaffAssignment (
  user_id INT NOT NULL,
  shop_id INT NOT NULL,
  PRIMARY KEY (user_id, shop_id),
  CONSTRAINT fk_sa_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_sa_shop FOREIGN KEY (shop_id) REFERENCES Shop(shop_id) ON DELETE CASCADE
);

-- Optional: the site has no customer login yet; kept for the "user" role / loyalty
CREATE TABLE Customer (
  customer_id INT AUTO_INCREMENT PRIMARY KEY,
  full_name   VARCHAR(100) NOT NULL,
  phone       VARCHAR(20)  NOT NULL UNIQUE,
  email       VARCHAR(100) NULL UNIQUE
);

-- ---------- Catalogue ------------------------------------------------
-- Self-referencing (parent_id) so categories can be grouped (recursive CTE demo)
CREATE TABLE Category (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  code        VARCHAR(30) NOT NULL UNIQUE,      -- 'dairy', 'bakery' ... (ids used by the site)
  name        VARCHAR(60) NOT NULL,
  icon        VARCHAR(30),
  parent_id   INT NULL,
  CONSTRAINT fk_cat_parent FOREIGN KEY (parent_id) REFERENCES Category(category_id) ON DELETE SET NULL
);

CREATE TABLE Product (
  product_id   INT AUTO_INCREMENT PRIMARY KEY,
  sku          VARCHAR(30)  NOT NULL UNIQUE,
  barcode      VARCHAR(20)  NOT NULL UNIQUE,
  name         VARCHAR(150) NOT NULL,
  category_id  INT NOT NULL,
  retail_price DECIMAL(10,2) NOT NULL,
  cost_price   DECIMAL(10,2) NOT NULL,
  image_url    VARCHAR(500),
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,   -- soft delete
  CONSTRAINT fk_prod_cat FOREIGN KEY (category_id) REFERENCES Category(category_id),
  CONSTRAINT ck_price CHECK (retail_price >= 0 AND cost_price >= 0),
  CONSTRAINT ck_margin CHECK (retail_price >= cost_price)
);

-- Per-shop stock. Composite PK = Shop x Product (M:N resolution).
-- stock_status is a DERIVED attribute (the site shows In/Low/Out of Stock),
-- so it is computed, not stored by hand -> no update anomaly.
CREATE TABLE Inventory (
  shop_id         INT NOT NULL,
  product_id      INT NOT NULL,
  stock_qty       INT NOT NULL DEFAULT 0,
  min_stock_alert INT NOT NULL DEFAULT 10,
  stock_status    VARCHAR(12) GENERATED ALWAYS AS (
      CASE WHEN stock_qty = 0 THEN 'Out of Stock'
           WHEN stock_qty <= min_stock_alert THEN 'Low Stock'
           ELSE 'In Stock' END) STORED,
  PRIMARY KEY (shop_id, product_id),
  CONSTRAINT fk_inv_shop FOREIGN KEY (shop_id)    REFERENCES Shop(shop_id)       ON DELETE CASCADE,
  CONSTRAINT fk_inv_prod FOREIGN KEY (product_id) REFERENCES Product(product_id) ON DELETE RESTRICT,
  CONSTRAINT ck_stock CHECK (stock_qty >= 0),
  CONSTRAINT ck_minal CHECK (min_stock_alert >= 0)
);

-- ---------- Sales ----------------------------------------------------
-- Site shows ids like TXN-98421, so we start numbering at 98000.
CREATE TABLE Sale (
  sale_id          INT AUTO_INCREMENT PRIMARY KEY,
  shop_id          INT NOT NULL,
  cashier_id       INT NOT NULL,
  customer_id      INT NULL,
  sale_time        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  subtotal         DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_percent DECIMAL(5,2)  NOT NULL DEFAULT 0,   -- cart offers 0/5/10/15
  discount_amount  DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_amount       DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
  status           ENUM('Completed','Refunded') NOT NULL DEFAULT 'Completed',
  CONSTRAINT fk_sale_shop FOREIGN KEY (shop_id)     REFERENCES Shop(shop_id),
  CONSTRAINT fk_sale_cash FOREIGN KEY (cashier_id)  REFERENCES Users(user_id),
  CONSTRAINT fk_sale_cust FOREIGN KEY (customer_id) REFERENCES Customer(customer_id) ON DELETE SET NULL,
  CONSTRAINT ck_disc CHECK (discount_percent BETWEEN 0 AND 100)
) AUTO_INCREMENT = 98000;

-- Weak entity: a line item cannot exist without its Sale (composite PK).
-- unit_price / unit_cost are SNAPSHOTS so old bills never change if prices change later.
CREATE TABLE SaleItem (
  sale_id    INT NOT NULL,
  product_id INT NOT NULL,
  qty        INT NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  unit_cost  DECIMAL(10,2) NOT NULL,
  line_total DECIMAL(12,2) GENERATED ALWAYS AS (qty * unit_price) STORED,
  PRIMARY KEY (sale_id, product_id),
  CONSTRAINT fk_si_sale FOREIGN KEY (sale_id)    REFERENCES Sale(sale_id)       ON DELETE CASCADE,
  CONSTRAINT fk_si_prod FOREIGN KEY (product_id) REFERENCES Product(product_id),
  CONSTRAINT ck_qty CHECK (qty > 0)
);

-- 1:1 with Sale. Split out so cash-only / card-only columns don't pollute Sale.
CREATE TABLE Payment (
  sale_id         INT PRIMARY KEY,
  method          ENUM('Cash','Card','UPI') NOT NULL,
  amount_tendered DECIMAL(12,2) NULL,        -- cash received
  change_due      DECIMAL(12,2) NULL,
  card_last4      CHAR(4) NULL,
  CONSTRAINT fk_pay_sale FOREIGN KEY (sale_id) REFERENCES Sale(sale_id) ON DELETE CASCADE
);

-- ---------- Audit / logs (filled by triggers & procedures) ----------
CREATE TABLE StockMovement (
  movement_id INT AUTO_INCREMENT PRIMARY KEY,
  shop_id     INT NOT NULL,
  product_id  INT NOT NULL,
  change_qty  INT NOT NULL,                  -- + restock/refund, - sale
  reason      ENUM('SALE','RESTOCK','ADJUSTMENT','REFUND') NOT NULL,
  ref_sale_id INT NULL,
  user_id     INT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_sm_inv  FOREIGN KEY (shop_id, product_id) REFERENCES Inventory(shop_id, product_id),
  CONSTRAINT fk_sm_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE SET NULL
);

CREATE TABLE PriceHistory (
  history_id INT AUTO_INCREMENT PRIMARY KEY,
  product_id INT NOT NULL,
  old_price  DECIMAL(10,2) NOT NULL,
  new_price  DECIMAL(10,2) NOT NULL,
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ph_prod FOREIGN KEY (product_id) REFERENCES Product(product_id) ON DELETE CASCADE
);

-- ---------- Indexes (beyond PK/UNIQUE) -------------------------------
CREATE INDEX idx_sale_shop_time   ON Sale(shop_id, sale_time);   -- reports, date filters
CREATE INDEX idx_sale_cashier     ON Sale(cashier_id, sale_time);
CREATE INDEX idx_product_name     ON Product(name);              -- search bar
CREATE INDEX idx_product_category ON Product(category_id);       -- category tabs
CREATE INDEX idx_si_product       ON SaleItem(product_id);
CREATE INDEX idx_sm_product_time  ON StockMovement(product_id, created_at);

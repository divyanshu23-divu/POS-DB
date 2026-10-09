-- =====================================================================
-- 04_views.sql  (run after 03_procedures.sql)
-- One view per screen of the website, so the backend just does SELECT.
-- Topics: views, joins, GROUP BY/HAVING, window functions, CTEs.
-- =====================================================================
USE pos;

-- Cashier screen: product grid + category tabs (filter by shop_id and category_code)
CREATE OR REPLACE VIEW v_product_catalog AS
SELECT i.shop_id, p.product_id, p.sku, p.barcode, p.name, c.code AS category_code,
       c.name AS category_name, p.retail_price AS price, p.cost_price,
       i.stock_qty AS stock, i.min_stock_alert, i.stock_status AS status, p.image_url
  FROM Inventory i
  JOIN Product p  ON p.product_id  = i.product_id
  JOIN Category c ON c.category_id = p.category_id
 WHERE p.is_active = TRUE;

-- Admin > Inventory: the three counter cards (In / Low / Out of stock)
CREATE OR REPLACE VIEW v_inventory_summary AS
SELECT shop_id,
       SUM(stock_status = 'In Stock')     AS in_stock,
       SUM(stock_status = 'Low Stock')    AS low_stock,
       SUM(stock_status = 'Out of Stock') AS out_of_stock
  FROM Inventory GROUP BY shop_id;

-- Admin > Transactions table
CREATE OR REPLACE VIEW v_transactions AS
SELECT s.sale_id, fn_invoice_no(s.sale_id) AS txn_id, s.shop_id, s.sale_time AS date,
       u.full_name AS cashier,
       (SELECT SUM(qty) FROM SaleItem si WHERE si.sale_id = s.sale_id) AS items_count,
       pay.method AS payment_method, s.subtotal, s.tax_amount AS tax,
       s.discount_amount AS discount, s.total_amount AS amount, s.status
  FROM Sale s
  JOIN Users u   ON u.user_id = s.cashier_id
  JOIN Payment pay ON pay.sale_id = s.sale_id;

-- Transaction detail pop-up and receipt
CREATE OR REPLACE VIEW v_transaction_items AS
SELECT si.sale_id, fn_invoice_no(si.sale_id) AS txn_id, p.name, si.qty AS quantity,
       si.unit_price AS price, si.line_total
  FROM SaleItem si JOIN Product p ON p.product_id = si.product_id;

-- Reports: Revenue (daily totals). Backend adds WHERE sale_day >= CURDATE() - INTERVAL 6 DAY
CREATE OR REPLACE VIEW v_daily_sales AS
SELECT shop_id, DATE(sale_time) AS sale_day, SUM(total_amount) AS sales, COUNT(*) AS orders
  FROM Sale WHERE status = 'Completed'
 GROUP BY shop_id, DATE(sale_time);

-- Reports: Payment distribution
CREATE OR REPLACE VIEW v_payment_distribution AS
SELECT s.shop_id, pay.method, COUNT(*) AS bills, SUM(s.total_amount) AS amount,
       ROUND(100 * SUM(s.total_amount) / SUM(SUM(s.total_amount)) OVER (PARTITION BY s.shop_id), 1) AS pct
  FROM Sale s JOIN Payment pay ON pay.sale_id = s.sale_id
 WHERE s.status = 'Completed'
 GROUP BY s.shop_id, pay.method;

-- Reports: Category sales ranking (window function RANK)
CREATE OR REPLACE VIEW v_category_sales AS
SELECT x.*, RANK() OVER (PARTITION BY shop_id ORDER BY revenue DESC) AS rank_in_shop
  FROM (SELECT s.shop_id, c.name AS category, SUM(si.line_total) AS revenue, SUM(si.qty) AS units
          FROM Sale s JOIN SaleItem si ON si.sale_id = s.sale_id
          JOIN Product p ON p.product_id = si.product_id
          JOIN Category c ON c.category_id = p.category_id
         WHERE s.status = 'Completed'
         GROUP BY s.shop_id, c.name) x;

-- Reports: Staff billing performance
CREATE OR REPLACE VIEW v_staff_performance AS
SELECT s.shop_id, u.user_id, u.full_name, u.role, COUNT(*) AS bills, SUM(s.total_amount) AS revenue,
       ROUND(AVG(s.total_amount), 2) AS avg_bill,
       DENSE_RANK() OVER (PARTITION BY s.shop_id ORDER BY SUM(s.total_amount) DESC) AS rnk
  FROM Sale s JOIN Users u ON u.user_id = s.cashier_id
 WHERE s.status = 'Completed'
 GROUP BY s.shop_id, u.user_id, u.full_name, u.role;

-- Dashboard KPI cards (today)
CREATE OR REPLACE VIEW v_dashboard_today AS
SELECT sh.shop_id,
       IFNULL(SUM(CASE WHEN s.status='Completed' THEN s.total_amount END), 0)   AS revenue_today,
       COUNT(CASE WHEN s.status='Completed' THEN 1 END)                         AS orders_today,
       IFNULL(SUM(CASE WHEN s.status='Refunded' THEN 1 END), 0)                 AS refunds_today
  FROM Shop sh LEFT JOIN Sale s ON s.shop_id = sh.shop_id AND DATE(s.sale_time) = CURDATE()
 GROUP BY sh.shop_id;

-- Gross profit per product (uses the cost snapshot stored in SaleItem)
CREATE OR REPLACE VIEW v_product_profit AS
SELECT s.shop_id, p.product_id, p.name, SUM(si.qty) AS units,
       SUM(si.line_total) AS revenue, SUM(si.qty * (si.unit_price - si.unit_cost)) AS profit
  FROM Sale s JOIN SaleItem si ON si.sale_id = s.sale_id
  JOIN Product p ON p.product_id = si.product_id
 WHERE s.status = 'Completed'
 GROUP BY s.shop_id, p.product_id, p.name;

-- Staff page (never exposes password_hash)
CREATE OR REPLACE VIEW v_staff AS
SELECT u.user_id, u.full_name, u.email, u.phone, u.role, u.status, u.last_active,
       sa.shop_id
  FROM Users u LEFT JOIN StaffAssignment sa ON sa.user_id = u.user_id;

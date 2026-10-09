-- =====================================================================
-- 07_demo_queries.sql   Every query is tagged with the DBMS topic it shows.
-- Run them one by one in Workbench (Ctrl+Enter) and screenshot for the report.
-- =====================================================================
USE pos;

-- [JOIN: inner, 4 tables] Bill details of every sale
SELECT fn_invoice_no(s.sale_id) AS txn, s.sale_time, u.full_name AS cashier, p.name AS product,
       si.qty, si.unit_price, si.line_total
  FROM Sale s JOIN Users u ON u.user_id = s.cashier_id
  JOIN SaleItem si ON si.sale_id = s.sale_id
  JOIN Product p   ON p.product_id = si.product_id
 ORDER BY s.sale_time DESC, p.name;

-- [LEFT JOIN] Products that have NEVER been sold
SELECT p.name FROM Product p LEFT JOIN SaleItem si ON si.product_id = p.product_id
 WHERE si.product_id IS NULL;

-- [SELF JOIN / hierarchy] Category with its parent group
SELECT c.name AS category, parent.name AS group_name
  FROM Category c JOIN Category parent ON parent.category_id = c.parent_id;

-- [GROUP BY + HAVING] Payment methods used in more than 1 bill
SELECT pay.method, COUNT(*) AS bills, SUM(s.total_amount) AS amount
  FROM Payment pay JOIN Sale s ON s.sale_id = pay.sale_id
 GROUP BY pay.method HAVING COUNT(*) > 1;

-- [Subquery] Products priced above the average price
SELECT name, retail_price FROM Product
 WHERE retail_price > (SELECT AVG(retail_price) FROM Product) ORDER BY retail_price DESC;

-- [Correlated subquery] Products priced above the average of THEIR OWN category
SELECT p.name, p.retail_price FROM Product p
 WHERE p.retail_price > (SELECT AVG(p2.retail_price) FROM Product p2
                          WHERE p2.category_id = p.category_id);

-- [EXISTS] Customers/cashiers who made at least one sale over Rs 500
SELECT u.full_name FROM Users u
 WHERE EXISTS (SELECT 1 FROM Sale s WHERE s.cashier_id = u.user_id AND s.total_amount > 500);

-- [Set operations] (INTERSECT / EXCEPT need MySQL 8.0.31+; otherwise use UNION or NOT IN)
SELECT product_id FROM Inventory WHERE shop_id = 1
EXCEPT
SELECT product_id FROM Inventory WHERE shop_id = 2;          -- stocked in shop 1 only
SELECT product_id FROM Inventory WHERE shop_id = 1
INTERSECT
SELECT product_id FROM Inventory WHERE shop_id = 2;          -- stocked in both
SELECT name FROM Product WHERE retail_price < 50
UNION
SELECT name FROM Product WHERE category_id = (SELECT category_id FROM Category WHERE code='dairy');

-- [Window function: RANK] Top-selling product inside each category
SELECT * FROM (
  SELECT c.name AS category, p.name AS product, SUM(si.qty) AS units,
         RANK() OVER (PARTITION BY c.category_id ORDER BY SUM(si.qty) DESC) AS rnk
    FROM SaleItem si JOIN Product p ON p.product_id = si.product_id
    JOIN Category c ON c.category_id = p.category_id
   GROUP BY c.category_id, c.name, p.product_id, p.name) t
 WHERE rnk = 1;

-- [Window function: running total] Revenue building up day by day
SELECT sale_day, sales, SUM(sales) OVER (ORDER BY sale_day) AS running_total FROM v_daily_sales;

-- [Window function: LAG] Day-over-day change
SELECT sale_day, sales, sales - LAG(sales) OVER (ORDER BY sale_day) AS change_vs_prev_day FROM v_daily_sales;

-- [CTE] Staff who billed more than the average staff member
WITH per_staff AS (
  SELECT cashier_id, SUM(total_amount) AS revenue FROM Sale WHERE status = 'Completed' GROUP BY cashier_id)
SELECT u.full_name, ps.revenue FROM per_staff ps JOIN Users u ON u.user_id = ps.cashier_id
 WHERE ps.revenue > (SELECT AVG(revenue) FROM per_staff);

-- [Recursive CTE] Category tree
WITH RECURSIVE tree AS (
  SELECT category_id, name, parent_id, 0 AS depth, CAST(name AS CHAR(200)) AS path
    FROM Category WHERE parent_id IS NULL
  UNION ALL
  SELECT c.category_id, c.name, c.parent_id, t.depth + 1, CONCAT(t.path, ' > ', c.name)
    FROM Category c JOIN tree t ON c.parent_id = t.category_id)
SELECT path FROM tree ORDER BY path;

-- [CASE + aggregate] Low-stock value that must be re-ordered
SELECT i.shop_id, SUM(CASE WHEN i.stock_status <> 'In Stock' THEN 1 ELSE 0 END) AS items_to_reorder
  FROM Inventory i GROUP BY i.shop_id;

-- [Views in use]
SELECT * FROM v_inventory_summary;
SELECT * FROM v_payment_distribution;
SELECT * FROM v_category_sales ORDER BY shop_id, rank_in_shop;
SELECT * FROM v_staff_performance ORDER BY shop_id, rnk;
SELECT * FROM v_product_profit ORDER BY profit DESC;

-- [Stored procedures / functions in use]
CALL sp_low_stock_report(1);
SET @items = '[{"product_id":1,"qty":2},{"product_id":10,"qty":3}]';
CALL sp_make_sale(1, 2, NULL, 5, 'UPI', 0, NULL, @items, @new_sale_id);
SELECT @new_sale_id AS created_sale, fn_invoice_no(@new_sale_id) AS txn;

-- [Trigger demos] (each should FAIL with the message shown as a comment)
-- CALL sp_make_sale(1, 2, NULL, 0, 'Cash', 5000, NULL, '[{"product_id":9,"qty":1}]', @x);  -- Insufficient stock (soda is out)
-- DELETE FROM Sale WHERE sale_id = 98421;                                                -- Sales cannot be deleted
-- UPDATE Users SET status='Inactive' WHERE role='ADMIN';                                  -- Cannot remove the last active admin
UPDATE Product SET retail_price = retail_price + 2 WHERE sku = 'DRY-MLK-01';              -- logs to PriceHistory
SELECT * FROM PriceHistory;
SELECT * FROM StockMovement ORDER BY movement_id DESC LIMIT 10;                           -- audit log

-- ---------------------------------------------------------------------
-- [TRANSACTIONS / CONCURRENCY]  Open TWO Workbench query tabs (two sessions).
-- Session A:                                    Session B:
--   START TRANSACTION;
--   SELECT stock_qty FROM Inventory
--    WHERE shop_id=1 AND product_id=5 FOR UPDATE;
--                                                START TRANSACTION;
--                                                SELECT stock_qty FROM Inventory
--                                                 WHERE shop_id=1 AND product_id=5 FOR UPDATE;  -- WAITS (row locked by A)
--   UPDATE Inventory SET stock_qty = stock_qty - 6
--    WHERE shop_id=1 AND product_id=5;
--   COMMIT;                                      -- B now continues and sees stock = 0 -> must refuse the sale
--
-- Isolation levels (run in each session before START TRANSACTION):
--   SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- try REPEATABLE READ (MySQL default), SERIALIZABLE
--   A: START TRANSACTION; SELECT stock_qty FROM Inventory WHERE shop_id=1 AND product_id=1;
--   B: UPDATE Inventory SET stock_qty = stock_qty - 1 WHERE shop_id=1 AND product_id=1; COMMIT;
--   A: SELECT stock_qty FROM Inventory WHERE shop_id=1 AND product_id=1;
--      READ COMMITTED -> value changed (non-repeatable read);  REPEATABLE READ -> same value.
--
-- ROLLBACK / SAVEPOINT demo:
START TRANSACTION;
  UPDATE Inventory SET stock_qty = stock_qty - 1 WHERE shop_id=1 AND product_id=1;
  SAVEPOINT after_first;
  UPDATE Inventory SET stock_qty = stock_qty - 1 WHERE shop_id=1 AND product_id=2;
  ROLLBACK TO after_first;      -- undo only the second update
ROLLBACK;                       -- undo everything
-- ---------------------------------------------------------------------

-- [INDEXING] needs 08_bulk_sales_for_index_demo.sql first (about 100,000 sales).
-- 1) Composite index (shop_id, sale_time) is used: type = range, a few hundred rows read.
EXPLAIN SELECT * FROM Sale WHERE shop_id = 1 AND sale_time BETWEEN '2025-12-01' AND '2025-12-07';
-- 2) Leftmost-prefix rule: same index CANNOT help a query on sale_time alone -> type = ALL (full scan of ~100,000 rows).
EXPLAIN SELECT * FROM Sale WHERE sale_time BETWEEN '2025-12-01' AND '2025-12-07';
-- 3) Add an index for that query and compare: type = range, far fewer rows.
CREATE INDEX idx_sale_time ON Sale(sale_time);
EXPLAIN SELECT * FROM Sale WHERE sale_time BETWEEN '2025-12-01' AND '2025-12-07';
DROP INDEX idx_sale_time ON Sale;      -- clean up (idx_sale_shop_time must stay: the shop_id foreign key uses it)
-- 4) Prefix search uses idx_product_name; a leading wildcard cannot:
EXPLAIN SELECT * FROM Product WHERE name LIKE 'Fresh%';
EXPLAIN SELECT * FROM Product WHERE name LIKE '%Fresh%';

-- [DCL] try as the limited login:  mysql -u demo_cashier -p pos
--   SELECT * FROM v_product_catalog;     -- allowed
--   SELECT * FROM Users;                 -- ERROR 1142: SELECT command denied
--   DELETE FROM Sale;                    -- ERROR 1142: DELETE command denied

-- =====================================================================
-- 08_bulk_sales_for_index_demo.sql   (OPTIONAL - only for the indexing demo)
-- Adds ~100,000 fake sales so EXPLAIN shows a real difference with/without indexes.
-- Run once. Takes a few seconds. Safe to skip for normal development.
-- =====================================================================
USE pos;
SET SESSION cte_max_recursion_depth = 100000;
SET @skip_stock_trigger = 1;

INSERT INTO Sale(shop_id, cashier_id, sale_time, subtotal, discount_percent, discount_amount, tax_amount, total_amount, status)
WITH RECURSIVE n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 100000)
SELECT 1 + (i MOD 2),                                       -- shop 1 or 2
       CASE WHEN i MOD 2 = 0 THEN 4 ELSE 2 END,             -- cashier staffed at both shops
       TIMESTAMP('2026-10-08') - INTERVAL (i * 5) MINUTE,    -- one sale every 5 minutes, going back ~11 months
       a.amt, 0, 0, ROUND(a.amt * 0.05, 2), ROUND(a.amt * 1.05, 2), 'Completed'
  FROM n JOIN (SELECT 1 AS k) z
  JOIN LATERAL (SELECT 50 + (n.i * 7919) MOD 900 AS amt) a ON TRUE;
SET @skip_stock_trigger = 0;
SELECT COUNT(*) AS sales_now FROM Sale;

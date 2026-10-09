-- =====================================================================
-- 03_procedures.sql  (run after 02_triggers.sql)
-- The web backend should CALL these instead of writing business logic in SQL strings.
-- Topics: stored procedures, functions, transactions, error handlers,
--         JSON_TABLE, cursor, row locking.
-- =====================================================================
USE pos;
DROP FUNCTION  IF EXISTS fn_invoice_no;
DROP FUNCTION  IF EXISTS fn_tax;
DROP PROCEDURE IF EXISTS sp_make_sale;
DROP PROCEDURE IF EXISTS sp_refund_sale;
DROP PROCEDURE IF EXISTS sp_add_product;
DROP PROCEDURE IF EXISTS sp_adjust_stock;
DROP PROCEDURE IF EXISTS sp_low_stock_report;

DELIMITER //

CREATE FUNCTION fn_invoice_no(p_sale_id INT) RETURNS VARCHAR(20) DETERMINISTIC
BEGIN
  RETURN CONCAT('TXN-', p_sale_id);          -- site shows ids like TXN-98421
END//

CREATE FUNCTION fn_tax(p_amount DECIMAL(12,2), p_rate DECIMAL(5,2)) RETURNS DECIMAL(12,2) DETERMINISTIC
BEGIN
  RETURN ROUND(p_amount * p_rate / 100, 2);
END//

-- ---------------------------------------------------------------------
-- Checkout button.   p_items example:
--   '[{"product_id":1,"qty":2},{"product_id":5,"qty":1}]'
-- Whole sale is ONE transaction: any error -> ROLLBACK, nothing is saved.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_make_sale(
  IN  p_shop_id          INT,
  IN  p_cashier_id       INT,
  IN  p_customer_id      INT,            -- NULL for walk-in
  IN  p_discount_percent DECIMAL(5,2),   -- 0, 5, 10, 15 on the cart screen
  IN  p_method           VARCHAR(10),    -- 'Cash' | 'Card' | 'UPI'
  IN  p_tendered         DECIMAL(12,2),  -- cash received (ignored for Card/UPI)
  IN  p_card_last4       CHAR(4),
  IN  p_items            JSON,
  OUT p_sale_id          INT)
BEGIN
  DECLARE v_ok INT DEFAULT 0;
  DECLARE v_rate DECIMAL(5,2);
  DECLARE v_subtotal, v_discount, v_tax, v_total DECIMAL(12,2);
  DECLARE v_lines INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  -- who is allowed to bill in this shop?
  SELECT COUNT(*) INTO v_ok
    FROM Users u JOIN StaffAssignment sa ON sa.user_id = u.user_id
   WHERE u.user_id = p_cashier_id AND sa.shop_id = p_shop_id
     AND u.status = 'Active' AND u.role IN ('CASHIER','MANAGER');
  IF v_ok = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User is not an active cashier/manager of this shop';
  END IF;
  IF p_method NOT IN ('Cash','Card','UPI') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid payment method';
  END IF;
  IF p_items IS NULL OR JSON_LENGTH(p_items) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cart is empty';
  END IF;

  SELECT tax_rate_percent INTO v_rate FROM ShopSettings WHERE shop_id = p_shop_id;

  START TRANSACTION;

  INSERT INTO Sale(shop_id, cashier_id, customer_id, discount_percent)
  VALUES (p_shop_id, p_cashier_id, p_customer_id, IFNULL(p_discount_percent, 0));
  SET p_sale_id = LAST_INSERT_ID();

  -- ORDER BY product_id => every cashier locks rows in the same order => no deadlocks
  INSERT INTO SaleItem(sale_id, product_id, qty, unit_price, unit_cost)
  SELECT p_sale_id, p.product_id, j.qty, p.retail_price, p.cost_price
    FROM (SELECT product_id, SUM(qty) AS qty
            FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
                   product_id INT PATH '$.product_id',
                   qty        INT PATH '$.qty')) AS jt
           GROUP BY product_id) AS j
    JOIN Product p ON p.product_id = j.product_id AND p.is_active = TRUE
   ORDER BY j.product_id;

  SELECT COUNT(*) INTO v_lines FROM SaleItem WHERE sale_id = p_sale_id;
  IF v_lines = 0 OR v_lines <> (SELECT COUNT(DISTINCT product_id)
        FROM JSON_TABLE(p_items, '$[*]' COLUMNS (product_id INT PATH '$.product_id')) AS x) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cart contains an unknown or inactive product';
  END IF;

  -- totals, same maths as the cart panel: discount first, then GST on the rest
  SELECT SUM(line_total) INTO v_subtotal FROM SaleItem WHERE sale_id = p_sale_id;
  SET v_discount = ROUND(v_subtotal * IFNULL(p_discount_percent,0) / 100, 2);
  SET v_tax      = fn_tax(v_subtotal - v_discount, v_rate);
  SET v_total    = v_subtotal - v_discount + v_tax;

  UPDATE Sale
     SET subtotal = v_subtotal, discount_amount = v_discount,
         tax_amount = v_tax, total_amount = v_total
   WHERE sale_id = p_sale_id;

  IF p_method = 'Cash' THEN
    IF p_tendered IS NULL OR p_tendered < v_total THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cash received is less than the total';
    END IF;
    INSERT INTO Payment(sale_id, method, amount_tendered, change_due)
    VALUES (p_sale_id, 'Cash', p_tendered, p_tendered - v_total);
  ELSE
    INSERT INTO Payment(sale_id, method, amount_tendered, change_due, card_last4)
    VALUES (p_sale_id, p_method, v_total, 0, IF(p_method = 'Card', p_card_last4, NULL));
  END IF;

  COMMIT;
END//

-- ---------------------------------------------------------------------
-- Refund: marks the bill Refunded and puts the stock back.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_refund_sale(IN p_sale_id INT, IN p_user_id INT)
BEGIN
  DECLARE v_status VARCHAR(10);
  DECLARE v_shop INT;
  DECLARE v_ok INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SELECT COUNT(*) INTO v_ok FROM Users
   WHERE user_id = p_user_id AND status = 'Active' AND role IN ('ADMIN','MANAGER');
  IF v_ok = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an admin or manager can refund';
  END IF;

  START TRANSACTION;
  SELECT status, shop_id INTO v_status, v_shop FROM Sale WHERE sale_id = p_sale_id FOR UPDATE;
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale not found';
  ELSEIF v_status = 'Refunded' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale is already refunded';
  END IF;

  UPDATE Inventory i JOIN SaleItem si ON si.product_id = i.product_id
     SET i.stock_qty = i.stock_qty + si.qty
   WHERE si.sale_id = p_sale_id AND i.shop_id = v_shop;

  INSERT INTO StockMovement(shop_id, product_id, change_qty, reason, ref_sale_id, user_id)
  SELECT v_shop, product_id, qty, 'REFUND', p_sale_id, p_user_id
    FROM SaleItem WHERE sale_id = p_sale_id;

  UPDATE Sale SET status = 'Refunded' WHERE sale_id = p_sale_id;
  COMMIT;
END//

-- ---------------------------------------------------------------------
-- Admin > Products > "Add product" form (also creates the stock row).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_add_product(
  IN  p_shop_id INT, IN p_sku VARCHAR(30), IN p_barcode VARCHAR(20), IN p_name VARCHAR(150),
  IN  p_category_code VARCHAR(30), IN p_price DECIMAL(10,2), IN p_cost DECIMAL(10,2),
  IN  p_initial_stock INT, IN p_min_alert INT, IN p_image VARCHAR(500),
  OUT p_product_id INT)
BEGIN
  DECLARE v_cat INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SELECT category_id INTO v_cat FROM Category WHERE code = p_category_code;
  IF v_cat IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown category';
  END IF;

  START TRANSACTION;
  INSERT INTO Product(sku, barcode, name, category_id, retail_price, cost_price, image_url)
  VALUES (p_sku, p_barcode, p_name, v_cat, p_price, IFNULL(p_cost, 0), p_image);
  SET p_product_id = LAST_INSERT_ID();

  INSERT INTO Inventory(shop_id, product_id, stock_qty, min_stock_alert)
  VALUES (p_shop_id, p_product_id, IFNULL(p_initial_stock, 0),
          IFNULL(p_min_alert, (SELECT low_stock_threshold FROM ShopSettings WHERE shop_id = p_shop_id)));
  IF IFNULL(p_initial_stock, 0) > 0 THEN
    INSERT INTO StockMovement(shop_id, product_id, change_qty, reason)
    VALUES (p_shop_id, p_product_id, p_initial_stock, 'RESTOCK');
  END IF;
  COMMIT;
END//

-- ---------------------------------------------------------------------
-- Inventory page: the +/- buttons and the "Restock" dialog.
-- p_delta may be negative (damaged / expired goods).
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_adjust_stock(
  IN p_shop_id INT, IN p_product_id INT, IN p_delta INT,
  IN p_reason VARCHAR(12), IN p_user_id INT)
BEGIN
  DECLARE v_stock INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  IF p_reason NOT IN ('RESTOCK','ADJUSTMENT') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reason must be RESTOCK or ADJUSTMENT';
  END IF;

  START TRANSACTION;
  SELECT stock_qty INTO v_stock FROM Inventory
   WHERE shop_id = p_shop_id AND product_id = p_product_id FOR UPDATE;
  IF v_stock IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product is not stocked in this shop';
  ELSEIF v_stock + p_delta < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock cannot go below zero';
  END IF;
  UPDATE Inventory SET stock_qty = stock_qty + p_delta
   WHERE shop_id = p_shop_id AND product_id = p_product_id;
  INSERT INTO StockMovement(shop_id, product_id, change_qty, reason, user_id)
  VALUES (p_shop_id, p_product_id, p_delta, p_reason, p_user_id);
  COMMIT;
END//

-- ---------------------------------------------------------------------
-- CURSOR demo: builds a plain-text low-stock alert list for one shop.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_low_stock_report(IN p_shop_id INT)
BEGIN
  DECLARE v_done BOOLEAN DEFAULT FALSE;
  DECLARE v_name VARCHAR(150);
  DECLARE v_stock, v_min INT;
  DECLARE cur CURSOR FOR
    SELECT p.name, i.stock_qty, i.min_stock_alert
      FROM Inventory i JOIN Product p ON p.product_id = i.product_id
     WHERE i.shop_id = p_shop_id AND i.stock_status <> 'In Stock'
     ORDER BY i.stock_qty, p.name;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

  DROP TEMPORARY TABLE IF EXISTS tmp_alerts;
  CREATE TEMPORARY TABLE tmp_alerts (line VARCHAR(300));

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_name, v_stock, v_min;
    IF v_done THEN LEAVE read_loop; END IF;
    INSERT INTO tmp_alerts VALUES (CONCAT(v_name, ': ', v_stock, ' left (alert at ', v_min, ')'));
  END LOOP;
  CLOSE cur;

  SELECT line AS alert FROM tmp_alerts;
  DROP TEMPORARY TABLE tmp_alerts;
END//

DELIMITER ;

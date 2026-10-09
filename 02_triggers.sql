-- =====================================================================
-- 02_triggers.sql   (run after 01_schema.sql)
-- Topics: BEFORE/AFTER triggers, SIGNAL, business-rule enforcement, audit.
-- =====================================================================
USE pos;
DROP TRIGGER IF EXISTS trg_saleitem_bi;
DROP TRIGGER IF EXISTS trg_saleitem_ai;
DROP TRIGGER IF EXISTS trg_product_bu;
DROP TRIGGER IF EXISTS trg_users_bu;
DROP TRIGGER IF EXISTS trg_sale_bd;

DELIMITER //

-- 1) Refuse a line item when the shop does not have enough stock.
--    FOR UPDATE locks the stock row so two cashiers can't sell the last unit.
--    (@skip_stock_trigger = 1 is only used by 06_seed.sql to load history.)
CREATE TRIGGER trg_saleitem_bi BEFORE INSERT ON SaleItem
FOR EACH ROW
BEGIN
  DECLARE v_shop INT;
  DECLARE v_stock INT;
  IF IFNULL(@skip_stock_trigger, 0) = 0 THEN
    SELECT shop_id INTO v_shop FROM Sale WHERE sale_id = NEW.sale_id;
    SELECT stock_qty INTO v_stock FROM Inventory
     WHERE shop_id = v_shop AND product_id = NEW.product_id FOR UPDATE;
    IF v_stock IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product is not stocked in this shop';
    ELSEIF v_stock < NEW.qty THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock';
    END IF;
  END IF;
END//

-- 2) After a line item is saved: reduce stock and log the movement.
CREATE TRIGGER trg_saleitem_ai AFTER INSERT ON SaleItem
FOR EACH ROW
BEGIN
  DECLARE v_shop INT;
  DECLARE v_cashier INT;
  IF IFNULL(@skip_stock_trigger, 0) = 0 THEN
    SELECT shop_id, cashier_id INTO v_shop, v_cashier FROM Sale WHERE sale_id = NEW.sale_id;
    UPDATE Inventory SET stock_qty = stock_qty - NEW.qty
     WHERE shop_id = v_shop AND product_id = NEW.product_id;
    INSERT INTO StockMovement(shop_id, product_id, change_qty, reason, ref_sale_id, user_id)
    VALUES (v_shop, NEW.product_id, -NEW.qty, 'SALE', NEW.sale_id, v_cashier);
  END IF;
END//

-- 3) Audit trail: remember every retail price change.
CREATE TRIGGER trg_product_bu BEFORE UPDATE ON Product
FOR EACH ROW
BEGIN
  IF NEW.retail_price <> OLD.retail_price THEN
    INSERT INTO PriceHistory(product_id, old_price, new_price)
    VALUES (OLD.product_id, OLD.retail_price, NEW.retail_price);
  END IF;
END//

-- 4) Never lock the business out: the last active ADMIN cannot be demoted/deactivated.
CREATE TRIGGER trg_users_bu BEFORE UPDATE ON Users
FOR EACH ROW
BEGIN
  DECLARE v_other_admins INT;
  IF OLD.role = 'ADMIN' AND OLD.status = 'Active'
     AND (NEW.role <> 'ADMIN' OR NEW.status <> 'Active') THEN
    SELECT COUNT(*) INTO v_other_admins FROM Users
     WHERE role = 'ADMIN' AND status = 'Active' AND user_id <> OLD.user_id;
    IF v_other_admins = 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot remove the last active admin';
    END IF;
  END IF;
END//

-- 5) Bills are legal records: they can be marked Refunded but never deleted.
CREATE TRIGGER trg_sale_bd BEFORE DELETE ON Sale
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sales cannot be deleted; refund them instead';
END//

DELIMITER ;

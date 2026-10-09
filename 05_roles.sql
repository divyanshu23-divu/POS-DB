-- =====================================================================
-- 05_roles.sql   (run as root/admin)   Topics: DCL, GRANT/REVOKE, roles, least privilege
-- The WEBSITE decides who is logged in (Users.role). The DATABASE decides what the
-- connection used by the website may touch. Give the backend ONE limited account.
-- =====================================================================
USE pos;
DROP ROLE IF EXISTS r_pos_admin, r_pos_manager, r_pos_cashier;
CREATE ROLE r_pos_admin, r_pos_manager, r_pos_cashier;

-- Admin: everything inside the pos database (but no server-level rights)
GRANT ALL PRIVILEGES ON pos.* TO r_pos_admin;

-- Manager: day-to-day management, no schema changes, cannot delete sales
GRANT SELECT ON pos.* TO r_pos_manager;
GRANT INSERT, UPDATE ON pos.Product   TO r_pos_manager;
GRANT INSERT, UPDATE ON pos.Inventory TO r_pos_manager;
GRANT INSERT, UPDATE ON pos.Customer  TO r_pos_manager;
GRANT EXECUTE ON pos.* TO r_pos_manager;

-- Cashier: sell, search, view stock. Only through the checkout procedure.
GRANT SELECT ON pos.v_product_catalog     TO r_pos_cashier;
GRANT SELECT ON pos.v_transactions        TO r_pos_cashier;
GRANT SELECT ON pos.v_transaction_items   TO r_pos_cashier;
GRANT SELECT ON pos.ShopSettings          TO r_pos_cashier;
GRANT SELECT, INSERT ON pos.Customer      TO r_pos_cashier;
GRANT EXECUTE ON PROCEDURE pos.sp_make_sale TO r_pos_cashier;

-- Account used by the website backend (change the password!).
-- It can read, call procedures and edit master data, but cannot DROP/ALTER or delete bills.
DROP USER IF EXISTS 'pos_app'@'localhost';
CREATE USER 'pos_app'@'localhost' IDENTIFIED BY 'ChangeMe#2026';
GRANT SELECT, EXECUTE ON pos.* TO 'pos_app'@'localhost';
-- Direct writes only on master-data tables. Sale, SaleItem, Payment, StockMovement
-- get NO direct INSERT/UPDATE: they change only through sp_make_sale / sp_refund_sale / sp_adjust_stock.
GRANT INSERT, UPDATE ON pos.Users           TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.StaffAssignment TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.Product         TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.Inventory       TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.Category        TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.Customer        TO 'pos_app'@'localhost';
GRANT INSERT, UPDATE ON pos.ShopSettings    TO 'pos_app'@'localhost';
-- (a demo login for each role, to show the difference in class)
DROP USER IF EXISTS 'demo_cashier'@'localhost';
CREATE USER 'demo_cashier'@'localhost' IDENTIFIED BY 'Cashier#123';
GRANT r_pos_cashier TO 'demo_cashier'@'localhost';
SET DEFAULT ROLE r_pos_cashier TO 'demo_cashier'@'localhost';
FLUSH PRIVILEGES;

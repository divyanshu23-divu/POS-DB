# AuraPOS database (MySQL 8.0+)

Run in MySQL Workbench, in this order (each file: **File > Open SQL Script**, then **Ctrl+Shift+Enter**):

| File | Purpose |
|---|---|
| 01_schema.sql | Creates database `pos`, 14 tables, constraints, indexes (**drops and recreates `pos`**) |
| 02_triggers.sql | Stock check/reduce, price history, last-admin guard, no-delete bills |
| 03_procedures.sql | `sp_make_sale`, `sp_refund_sale`, `sp_add_product`, `sp_adjust_stock`, `sp_low_stock_report`, 2 functions |
| 04_views.sql | One view per website screen |
| 05_roles.sql | DB roles + limited `pos_app` login for the backend (**change its password**) |
| 06_seed.sql | Sample data from the site's `mockData.js` |
| 07_demo_queries.sql | Queries/demos tagged by DBMS topic (for your report) |
| 08_bulk_sales_for_index_demo.sql | Optional, 100k fake sales for the indexing demo |

## Website screen -> database object (for the web team)

| Screen | Use |
|---|---|
| Login / Sign up / Staff page | `Users` (hash password in backend), `v_staff`; role values ADMIN, MANAGER, CASHIER, STAFF |
| Cashier: product grid + categories | `v_product_catalog` (filter `shop_id`, `category_code`) |
| Cashier: checkout | `CALL sp_make_sale(shop, cashier, customer_or_NULL, discount_pct, 'Cash'/'Card'/'UPI', cash_received, card_last4, items_json, @sale_id)`; items_json = `[{"product_id":1,"qty":2}]` |
| Receipt | `v_transactions`, `v_transaction_items`, `ShopSettings` |
| Admin: Products add/edit | `sp_add_product(...)`; edit = `UPDATE Product` |
| Admin: Inventory +/- and Restock | `sp_adjust_stock(shop, product, delta, 'RESTOCK'/'ADJUSTMENT', user)`; counters: `v_inventory_summary` |
| Admin: Transactions / refund | `v_transactions`; `sp_refund_sale(sale_id, user)` (admin/manager only) |
| Admin: Dashboard / Reports | `v_dashboard_today`, `v_daily_sales`, `v_payment_distribution`, `v_category_sales`, `v_staff_performance`, `v_product_profit` |
| Admin: Settings | `ShopSettings` (tax %, GSTIN, low-stock default, receipt footer ...) |

## Things the site should change (found while reading its code)
- Data is mock/in-memory now; amounts, discount and tax are computed in the browser. Let `sp_make_sale` do the maths and return the saved bill.
- The sign-up/login forms accept anything. Real login must check `Users.password_hash` in the backend.
- The Add Product form has no **cost price** field (stored as 0 if not sent; profit reports need it).
- The sample bills in `mockData.js` don't add up (e.g. TXN-98421 lists 3 items but says 4, subtotal 510 vs 471), so the seed recomputes totals.
- Site discount is a fixed amount in the sample data but a percentage (0/5/10/15) in the cart; the DB stores the percentage and the computed amount.
- There is no customer login yet; the `Customer` table is ready for the "user" role.

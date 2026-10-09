-- =====================================================================
-- 06_seed.sql  (run after 05_roles.sql)  Sample data taken from the AuraPOS site (mockData.js)
-- Passwords below are PLACEHOLDERS. The backend must store real bcrypt/argon2 hashes.
-- =====================================================================
USE pos;
SET @skip_stock_trigger = 1;   -- history is loaded directly, so stock is not reduced twice

INSERT INTO Mall(name, city) VALUES ('Prime Avenue Commercial Plaza','Bangalore'),('City Centre Mall','Indore');
INSERT INTO Shop(mall_id, shop_name) VALUES (1,'Aura Market & Deli'),(2,'Aura Express');
INSERT INTO ShopSettings(shop_id,tagline,address,phone,email,gstin,currency,tax_rate_percent,low_stock_threshold,receipt_footer,auto_print_receipt,barcode_sound_enabled) VALUES
  (1,'Fresh Groceries & Everyday Essentials','104, Prime Avenue, Commercial Plaza, Bangalore 560001','+91 80 4123 4567','store@auramarket.com','29ABCDE1234F1Z5','₹',5,10,'Thank you for shopping with us! Please visit again.',0,1),
  (2,'Quick groceries','Ground Floor, City Centre Mall, Indore','+91 731 400 1000','express@auramarket.com','23ABCDE1234F1Z9','₹',5,10,'Thank you! Visit again.',0,1);

-- Staff (Priya is Inactive, as on the site). Hash = placeholder.
INSERT INTO Users(full_name,email,phone,password_hash,role,status) VALUES
  ('David Sharma','david.sharma@aurapos.io','+91 98765 43210','$2b$10$REPLACE_WITH_REAL_BCRYPT_HASH','ADMIN','Active'),
  ('John Doe','john.doe@aurapos.io','+91 98765 12345','$2b$10$REPLACE_WITH_REAL_BCRYPT_HASH','CASHIER','Active'),
  ('Sarah Jenkins','sarah.j@aurapos.io','+91 98765 67890','$2b$10$REPLACE_WITH_REAL_BCRYPT_HASH','MANAGER','Active'),
  ('Alex Rivera','alex.rivera@aurapos.io','+91 98765 24680','$2b$10$REPLACE_WITH_REAL_BCRYPT_HASH','CASHIER','Active'),
  ('Priya Verma','priya.v@aurapos.io','+91 98765 13579','$2b$10$REPLACE_WITH_REAL_BCRYPT_HASH','STAFF','Inactive');
INSERT INTO StaffAssignment(user_id, shop_id) VALUES (1,1),(1,2),(2,1),(3,1),(3,2),(4,1),(4,2),(5,1);
INSERT INTO Customer(full_name, phone, email) VALUES ('Ravi Patel','+91 99000 11111','ravi@example.com'),('Meera Nair','+91 99000 22222',NULL);

-- Categories: two parent groups (for the recursive-CTE demo) + the 9 site categories
INSERT INTO Category(code,name,icon,parent_id) VALUES ('grocery','Food & Grocery',NULL,NULL),('home_care','Home & Personal',NULL,NULL);
INSERT INTO Category(code,name,icon,parent_id) VALUES
  ('beverages','Beverages','Coffee',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('snacks','Snacks','Cookie',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('dairy','Dairy & Eggs','Milk',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('bakery','Bakery','Croissant',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('fruits','Fruits','Apple',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('vegetables','Vegetables','Carrot',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('staples','Staples & Grains','Wheat',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='grocery') t)),
  ('personal_care','Personal Care','Sparkles',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='home_care') t)),
  ('household','Household','Home',(SELECT category_id FROM (SELECT category_id FROM Category WHERE code='home_care') t));

INSERT INTO Product(sku,barcode,name,category_id,retail_price,cost_price,image_url) VALUES
  ('DRY-MLK-01','890103000101','Fresh Cow Milk 1L',(SELECT category_id FROM Category WHERE code='dairy'),68,52,'https://images.unsplash.com/photo-1550583724-b2692b85b150?auto=format&fit=crop&w=400&q=80'),
  ('BKR-BRD-02','890103000102','Whole Wheat Brown Bread',(SELECT category_id FROM Category WHERE code='bakery'),45,32,'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=400&q=80'),
  ('BEV-COF-03','890103000103','Arabica Roast Coffee Beans 250g',(SELECT category_id FROM Category WHERE code='beverages'),340,240,'https://images.unsplash.com/photo-1559056199-641a0ac8b55e?auto=format&fit=crop&w=400&q=80'),
  ('BEV-TEA-04','890103000104','Assam Premium CTC Tea 500g',(SELECT category_id FROM Category WHERE code='beverages'),220,160,'https://images.unsplash.com/photo-1576092768241-dec231879fc3?auto=format&fit=crop&w=400&q=80'),
  ('SNK-BSK-05','890103000105','Butter Cookies Tin 400g',(SELECT category_id FROM Category WHERE code='snacks'),185,130,'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=400&q=80'),
  ('SNK-CHP-06','890103000106','Artisan Potato Sea Salt Chips',(SELECT category_id FROM Category WHERE code='snacks'),60,40,'https://images.unsplash.com/photo-1566478989037-eec170784d0b?auto=format&fit=crop&w=400&q=80'),
  ('SNK-CHO-07','890103000107','Dark Chocolate 70% Cocoa 100g',(SELECT category_id FROM Category WHERE code='snacks'),150,105,'https://images.unsplash.com/photo-1549007994-cb92caebd54b?auto=format&fit=crop&w=400&q=80'),
  ('BEV-JUC-08','890103000108','Cold Pressed Orange Juice 1L',(SELECT category_id FROM Category WHERE code='beverages'),130,90,'https://images.unsplash.com/photo-1621506289937-a8e4df240d0b?auto=format&fit=crop&w=400&q=80'),
  ('BEV-SDA-09','890103000109','Sparkling Lemon Soda 330ml',(SELECT category_id FROM Category WHERE code='beverages'),45,28,'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=400&q=80'),
  ('BEV-WTR-10','890103000110','Natural Mineral Water 1L',(SELECT category_id FROM Category WHERE code='beverages'),25,14,'https://images.unsplash.com/photo-1548839140-29a749e1bc4e?auto=format&fit=crop&w=400&q=80'),
  ('STP-RCE-11','890103000111','Aged Basmati Rice 5kg',(SELECT category_id FROM Category WHERE code='staples'),490,380,'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=400&q=80'),
  ('STP-PST-12','890103000112','Durum Wheat Penne Pasta 500g',(SELECT category_id FROM Category WHERE code='staples'),110,75,'https://images.unsplash.com/photo-1551462147-ff29053bfc14?auto=format&fit=crop&w=400&q=80'),
  ('PER-SOP-13','890103000113','Organic Shea Butter Soap Bar',(SELECT category_id FROM Category WHERE code='personal_care'),75,48,'https://images.unsplash.com/photo-1607006314144-8cb385ff218b?auto=format&fit=crop&w=400&q=80'),
  ('PER-SHP-14','890103000114','Nourishing Herbal Shampoo 400ml',(SELECT category_id FROM Category WHERE code='personal_care'),260,180,'https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?auto=format&fit=crop&w=400&q=80'),
  ('PER-TPT-15','890103000115','Herbal Complete Toothpaste 150g',(SELECT category_id FROM Category WHERE code='personal_care'),95,65,'https://images.unsplash.com/photo-1559567244-471253457595?auto=format&fit=crop&w=400&q=80'),
  ('HSD-DET-16','890103000116','Eco Dishwashing Liquid 750ml',(SELECT category_id FROM Category WHERE code='household'),140,95,'https://images.unsplash.com/photo-1585421514284-efb74c2b69ba?auto=format&fit=crop&w=400&q=80'),
  ('FRT-APL-17','890103000117','Fresh Washington Red Apples 1kg',(SELECT category_id FROM Category WHERE code='fruits'),180,130,'https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?auto=format&fit=crop&w=400&q=80'),
  ('FRT-BAN-18','890103000118','Ripe Cavendish Bananas 1 Dozen',(SELECT category_id FROM Category WHERE code='fruits'),60,42,'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?auto=format&fit=crop&w=400&q=80'),
  ('VEG-CUC-19','890103000119','Hydroponic English Cucumbers 500g',(SELECT category_id FROM Category WHERE code='vegetables'),40,24,'https://images.unsplash.com/photo-1449339854873-750e6913301b?auto=format&fit=crop&w=400&q=80'),
  ('VEG-TOM-20','890103000120','Fresh Cherry Tomatoes 250g',(SELECT category_id FROM Category WHERE code='vegetables'),55,35,'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=400&q=80'),
  ('BKR-CRS-21','890103000121','Artisan Butter Croissant (2-Pack)',(SELECT category_id FROM Category WHERE code='bakery'),120,75,'https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=400&q=80'),
  ('DRY-EGG-22','890103000122','Farm Fresh Organic Eggs (6-Pack)',(SELECT category_id FROM Category WHERE code='dairy'),70,50,'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?auto=format&fit=crop&w=400&q=80');

-- Shop 1 stocks every product with the quantities shown on the site
INSERT INTO Inventory(shop_id,product_id,stock_qty,min_stock_alert)
SELECT 1, product_id, CASE sku WHEN 'DRY-MLK-01' THEN 45 WHEN 'BKR-BRD-02' THEN 22 WHEN 'BEV-COF-03' THEN 18 WHEN 'BEV-TEA-04' THEN 35 WHEN 'SNK-BSK-05' THEN 6 WHEN 'SNK-CHP-06' THEN 54 WHEN 'SNK-CHO-07' THEN 4 WHEN 'BEV-JUC-08' THEN 15 WHEN 'BEV-SDA-09' THEN 0 WHEN 'BEV-WTR-10' THEN 80 WHEN 'STP-RCE-11' THEN 25 WHEN 'STP-PST-12' THEN 30 WHEN 'PER-SOP-13' THEN 42 WHEN 'PER-SHP-14' THEN 14 WHEN 'PER-TPT-15' THEN 5 WHEN 'HSD-DET-16' THEN 28 WHEN 'FRT-APL-17' THEN 35 WHEN 'FRT-BAN-18' THEN 3 WHEN 'VEG-CUC-19' THEN 20 WHEN 'VEG-TOM-20' THEN 0 WHEN 'BKR-CRS-21' THEN 16 WHEN 'DRY-EGG-22' THEN 40 END, CASE sku WHEN 'DRY-MLK-01' THEN 15 WHEN 'BKR-BRD-02' THEN 10 WHEN 'BEV-COF-03' THEN 8 WHEN 'BEV-TEA-04' THEN 12 WHEN 'SNK-BSK-05' THEN 10 WHEN 'SNK-CHP-06' THEN 20 WHEN 'SNK-CHO-07' THEN 10 WHEN 'BEV-JUC-08' THEN 8 WHEN 'BEV-SDA-09' THEN 15 WHEN 'BEV-WTR-10' THEN 25 WHEN 'STP-RCE-11' THEN 10 WHEN 'STP-PST-12' THEN 10 WHEN 'PER-SOP-13' THEN 15 WHEN 'PER-SHP-14' THEN 8 WHEN 'PER-TPT-15' THEN 10 WHEN 'HSD-DET-16' THEN 10 WHEN 'FRT-APL-17' THEN 12 WHEN 'FRT-BAN-18' THEN 8 WHEN 'VEG-CUC-19' THEN 8 WHEN 'VEG-TOM-20' THEN 10 WHEN 'BKR-CRS-21' THEN 6 WHEN 'DRY-EGG-22' THEN 15 END FROM Product;
-- Shop 2 (Indore) stocks only a few products
INSERT INTO Inventory(shop_id,product_id,stock_qty,min_stock_alert) SELECT 2, product_id, 30, 10 FROM Product WHERE category_id IN (SELECT category_id FROM Category WHERE code IN ('beverages','snacks'));

-- Sales: same bills as the site. The site's mock totals do not add up, so totals are RECOMPUTED from the items.
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98415,1,4,'2026-10-07 18:22:00',0,'Refunded');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98415, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 12 AS pid, 1 AS qty UNION ALL
  SELECT 21 AS pid, 1 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98415,'UPI',0,0,NULL);
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98416,1,2,'2026-10-08 10:45:00',3,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98416, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 6 AS pid, 3 AS qty UNION ALL
  SELECT 8 AS pid, 2 AS qty UNION ALL
  SELECT 10 AS pid, 4 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98416,'Card',0,0,'4242');
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98417,1,3,'2026-10-08 11:20:00',0,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98417, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 5 AS pid, 1 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98417,'Cash',0,0,NULL);
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98418,1,4,'2026-10-08 12:35:00',0,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98418, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 2 AS pid, 1 AS qty UNION ALL
  SELECT 22 AS pid, 2 AS qty UNION ALL
  SELECT 17 AS pid, 1 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98418,'UPI',0,0,NULL);
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98419,1,2,'2026-10-08 13:50:00',5,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98419, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 14 AS pid, 2 AS qty UNION ALL
  SELECT 16 AS pid, 2 AS qty UNION ALL
  SELECT 13 AS pid, 2 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98419,'Card',0,0,'4242');
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98420,1,3,'2026-10-08 14:15:00',6,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98420, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 11 AS pid, 1 AS qty UNION ALL
  SELECT 3 AS pid, 1 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98420,'Cash',0,0,NULL);
INSERT INTO Sale(sale_id,shop_id,cashier_id,sale_time,discount_percent,status) VALUES (98421,1,2,'2026-10-08 14:48:00',0,'Completed');
INSERT INTO SaleItem(sale_id,product_id,qty,unit_price,unit_cost) SELECT 98421, product_id, q.qty, retail_price, cost_price FROM Product JOIN (
  SELECT 1 AS pid, 2 AS qty UNION ALL
  SELECT 5 AS pid, 1 AS qty UNION ALL
  SELECT 7 AS pid, 1 AS qty) q ON q.pid = Product.product_id;
INSERT INTO Payment(sale_id,method,amount_tendered,change_due,card_last4) VALUES (98421,'UPI',0,0,NULL);

-- Fill in totals for the seeded sales (discount first, then tax)
UPDATE Sale s JOIN (SELECT sale_id, SUM(line_total) st FROM SaleItem GROUP BY sale_id) x ON x.sale_id=s.sale_id
  JOIN ShopSettings ss ON ss.shop_id=s.shop_id
   SET s.subtotal=x.st, s.discount_amount=ROUND(x.st*s.discount_percent/100,2),
       s.tax_amount=ROUND((x.st-ROUND(x.st*s.discount_percent/100,2))*ss.tax_rate_percent/100,2),
       s.total_amount=x.st-ROUND(x.st*s.discount_percent/100,2)+ROUND((x.st-ROUND(x.st*s.discount_percent/100,2))*ss.tax_rate_percent/100,2)
 WHERE s.sale_id BETWEEN 98415 AND 98421;
UPDATE Payment p JOIN Sale s ON s.sale_id=p.sale_id SET p.amount_tendered=s.total_amount WHERE p.sale_id BETWEEN 98415 AND 98421;
SET @skip_stock_trigger = 0;
ALTER TABLE Sale AUTO_INCREMENT = 98422;

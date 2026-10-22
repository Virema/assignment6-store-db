-- Assignment 6 - Set Operations, Grouping Sets, Views, Indexes, ACID
-- Part A - Set operations
-- Task 1. UK contact list
SELECT
    'Customer' AS contact_type,
    c.company_name AS organization,
    c.contact_name AS person,
    c.city
FROM customers AS c
WHERE c.country = 'UK'
UNION ALL
SELECT
    'Supplier' AS contact_type,
    s.company_name AS organization,
    s.contact_name AS person,
    s.city
FROM suppliers AS s
WHERE s.country = 'UK'
UNION ALL
SELECT
    'Employee' AS contact_type,
    'Northwind Traders' AS organization,
    e.first_name || ' ' || e.last_name AS person,
    e.city
FROM employees AS e
WHERE e.country = 'UK'
ORDER BY contact_type, city, person;

-- Task 2a. Countries with both customers and suppliers
SELECT country
FROM customers
INTERSECT
SELECT country
FROM suppliers
ORDER BY country;

-- Task 2b. Countries with customers but no suppliers
SELECT country
FROM customers
EXCEPT
SELECT country
FROM suppliers
ORDER BY country;

-- Task 2c. All cities, with duplicates removed
SELECT city
FROM customers
UNION
SELECT city
FROM suppliers
ORDER BY city;

-- Task 2d. All cities, keeping duplicates
SELECT city
FROM customers
UNION ALL
SELECT city
FROM suppliers
ORDER BY city;

-- Task 3. Customers lost in 1998
SELECT
    c.customer_id,
    c.company_name,
    c.country,
    c.phone
FROM customers AS c
WHERE c.customer_id IN (
    SELECT o1997.customer_id
    FROM orders AS o1997
    WHERE o1997.order_date >= DATE '1997-01-01'
      AND o1997.order_date < DATE '1998-01-01'
    EXCEPT
    SELECT o1998.customer_id
    FROM orders AS o1998
    WHERE o1998.order_date >= DATE '1998-01-01'
      AND o1998.order_date < DATE '1999-01-01'
)
ORDER BY c.company_name;

-- Part B - GROUPING SETS, ROLLUP, CUBE
-- Task 4. Orders by year and quarter with ROLLUP
SELECT
    EXTRACT(YEAR FROM o.order_date)::int AS order_year,
    EXTRACT(QUARTER FROM o.order_date)::int AS order_quarter,
    COUNT(*) AS orders_cnt,
    ROUND(SUM(o.freight)::numeric, 2) AS total_freight
FROM orders AS o
GROUP BY ROLLUP (
    EXTRACT(YEAR FROM o.order_date),
    EXTRACT(QUARTER FROM o.order_date)
)
ORDER BY order_year NULLS LAST, order_quarter NULLS LAST;

-- Task 5. Revenue by category and year with CUBE
SELECT
    CASE WHEN GROUPING(c.category_name) = 1 THEN 'All categories'
         ELSE c.category_name END AS category,
    CASE WHEN GROUPING(EXTRACT(YEAR FROM o.order_date)) = 1 THEN 'All years'
         ELSE EXTRACT(YEAR FROM o.order_date)::int::text END AS order_year,
    ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) AS revenue
FROM orders AS o
JOIN order_details AS od ON od.order_id = o.order_id
JOIN products AS p ON p.product_id = od.product_id
JOIN categories AS c ON c.category_id = p.category_id
GROUP BY CUBE (c.category_name, EXTRACT(YEAR FROM o.order_date))
ORDER BY
    GROUPING(c.category_name),
    c.category_name,
    GROUPING(EXTRACT(YEAR FROM o.order_date)),
    EXTRACT(YEAR FROM o.order_date);

-- Task 6. Product counts with GROUPING SETS
SELECT
    c.category_name,
    s.country AS supplier_country,
    COUNT(*) AS products_cnt,
    ROUND(AVG(p.unit_price)::numeric, 2) AS avg_price
FROM products AS p
JOIN categories AS c ON c.category_id = p.category_id
JOIN suppliers AS s ON s.supplier_id = p.supplier_id
GROUP BY GROUPING SETS (
    (c.category_name),
    (s.country),
    ()
)
ORDER BY c.category_name NULLS LAST, s.country NULLS LAST;

-- Part C - Views
-- Task 7a. Reusable view of order totals
DROP VIEW IF EXISTS v_order_totals;
CREATE VIEW v_order_totals AS
SELECT
    o.order_id,
    o.customer_id,
    o.employee_id,
    o.order_date,
    ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) AS order_total
FROM orders AS o
JOIN order_details AS od ON od.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.employee_id, o.order_date;

-- Task 7b. Top five customers by revenue in 1997
SELECT
    c.company_name,
    COUNT(v.order_id) AS orders_1997,
    ROUND(SUM(v.order_total)::numeric, 2) AS revenue_1997
FROM customers AS c
JOIN v_order_totals AS v ON v.customer_id = c.customer_id
WHERE v.order_date >= DATE '1997-01-01'
  AND v.order_date < DATE '1998-01-01'
GROUP BY c.customer_id, c.company_name
ORDER BY revenue_1997 DESC, c.company_name
LIMIT 5;

-- Task 8a. Updatable UK customer view
DROP VIEW IF EXISTS v_uk_customers;
CREATE VIEW v_uk_customers AS
SELECT
    customer_id,
    company_name,
    contact_name,
    city,
    country,
    phone
FROM customers
WHERE country = 'UK'
WITH CHECK OPTION;

-- Task 8b. Update through the view
UPDATE v_uk_customers
SET phone = '(171) 555-0000'
WHERE customer_id = 'AROUT';

SELECT customer_id, company_name, phone
FROM customers
WHERE customer_id = 'AROUT';

-- Task 8c. Insert a UK customer through the view
INSERT INTO v_uk_customers (customer_id, company_name, city, country)
VALUES ('AITU1', 'AITU Test Ltd', 'London', 'UK');

-- Expected error: new row violates check option for view "v_uk_customers"
INSERT INTO v_uk_customers (customer_id, company_name, city, country)
VALUES ('AITU2', 'AITU Paris', 'Paris', 'France'); -- expected error

-- Task 8d. Move a view row outside the view predicate
-- Expected error: new row violates check option for view "v_uk_customers"
UPDATE v_uk_customers
SET country = 'Kazakhstan'
WHERE customer_id = 'AITU1'; -- expected error

-- Task 9a. Materialized category sales view
DROP MATERIALIZED VIEW IF EXISTS mv_category_sales;
CREATE MATERIALIZED VIEW mv_category_sales AS
SELECT
    c.category_name,
    COUNT(DISTINCT od.order_id) AS orders_cnt,
    SUM(od.quantity) AS units_sold,
    ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) AS revenue
FROM categories AS c
JOIN products AS p ON p.category_id = c.category_id
JOIN order_details AS od ON od.product_id = p.product_id
GROUP BY c.category_id, c.category_name;

SELECT category_name, orders_cnt, units_sold, revenue
FROM mv_category_sales
ORDER BY revenue DESC;

-- Task 9b. Refreshing the materialized view
BEGIN;
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (10248, 1, 18, 100, 0);

SELECT units_sold AS beverages_units_before_refresh
FROM mv_category_sales
WHERE category_name = 'Beverages';

REFRESH MATERIALIZED VIEW mv_category_sales;

SELECT units_sold AS beverages_units_after_refresh
FROM mv_category_sales
WHERE category_name = 'Beverages';
COMMIT;

-- Part D - Indexes
-- Preparation for Tasks 10 and 11
DROP TABLE IF EXISTS orders_big;
CREATE TABLE orders_big AS
SELECT
    g.n * 100000 + o.order_id AS order_id,
    o.customer_id,
    o.employee_id,
    o.order_date + (g.n % 365) AS order_date,
    o.ship_country,
    o.ship_city,
    o.freight
FROM orders AS o
CROSS JOIN generate_series(1, 1000) AS g(n);

ANALYZE orders_big;

-- Task 10a. B-tree index before and after
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE customer_id = 'ALFKI';

CREATE INDEX idx_orders_big_customer
ON orders_big (customer_id);

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE customer_id = 'ALFKI';

-- Task 10c. Selectivity of a broad condition
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE customer_id >= 'B';

SELECT
    COUNT(*) AS matching_rows,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders_big), 2) AS table_share_pct
FROM orders_big
WHERE customer_id >= 'B';

-- Task 11a. Composite index
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE ship_country = 'Germany'
  AND order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';

CREATE INDEX idx_orders_big_country_date
ON orders_big (ship_country, order_date);

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE ship_country = 'Germany'
  AND order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE order_date BETWEEN DATE '1997-01-01' AND DATE '1997-01-31';

-- Task 11b. Partial index
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE freight > 500;

CREATE INDEX idx_orders_big_heavy
ON orders_big (freight)
WHERE freight > 500;

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE freight > 500;

-- Task 11c. Expression index
EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE LOWER(ship_city) = 'london';

CREATE INDEX idx_orders_big_city_lower
ON orders_big (LOWER(ship_city));

EXPLAIN ANALYZE
SELECT *
FROM orders_big
WHERE LOWER(ship_city) = 'london';

-- Task 11d. Index and table sizes
SELECT
    'index' AS object_type,
    indexname AS object_name,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS object_size
FROM pg_indexes
WHERE tablename = 'orders_big'
UNION ALL
SELECT
    'table' AS object_type,
    'orders_big' AS object_name,
    pg_size_pretty(pg_relation_size('orders_big'::regclass)) AS object_size
ORDER BY object_type, object_name;

-- Part E - Transactions and ACID
-- Task 12a. Initial stock values
SELECT product_id, units_in_stock
FROM products
WHERE product_id IN (11, 42)
ORDER BY product_id;

-- Task 12b. Failed transaction and atomicity
BEGIN;
INSERT INTO orders (
    order_id, customer_id, employee_id, order_date, required_date,
    ship_via, freight, ship_country
)
VALUES (11078, 'ALFKI', 1, DATE '1998-05-07', DATE '1998-06-04', 1, 25.00, 'Germany');

INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 11, 21.00, 5, 0);

UPDATE products
SET units_in_stock = units_in_stock - 5
WHERE product_id = 11;

-- Expected error: insert or update on table "order_details" violates foreign key constraint
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 999, 10.00, 1, 0); -- expected error

-- Expected error: current transaction is aborted
UPDATE products
SET units_in_stock = units_in_stock - 1
WHERE product_id = 42; -- expected error

-- Expected error: current transaction is aborted; COMMIT rolls back the failed transaction
COMMIT;

SELECT EXISTS (SELECT 1 FROM orders WHERE order_id = 11078) AS order_11078_exists;
SELECT product_id, units_in_stock
FROM products
WHERE product_id = 11;

-- Task 12c. Partial rollback with SAVEPOINT
BEGIN;
INSERT INTO orders (
    order_id, customer_id, employee_id, order_date, required_date,
    ship_via, freight, ship_country
)
VALUES (11078, 'ALFKI', 1, DATE '1998-05-07', DATE '1998-06-04', 1, 25.00, 'Germany');

INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 11, 21.00, 5, 0);

UPDATE products
SET units_in_stock = units_in_stock - 5
WHERE product_id = 11;

SAVEPOINT before_second_item;

-- Expected error: insert or update on table "order_details" violates foreign key constraint
INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 999, 10.00, 1, 0); -- expected error

ROLLBACK TO SAVEPOINT before_second_item;

INSERT INTO order_details (order_id, product_id, unit_price, quantity, discount)
VALUES (11078, 42, 14.00, 1, 0);

UPDATE products
SET units_in_stock = units_in_stock - 1
WHERE product_id = 42;
COMMIT;

SELECT order_id, product_id, unit_price, quantity, discount
FROM order_details
WHERE order_id = 11078
ORDER BY product_id;

SELECT product_id, units_in_stock
FROM products
WHERE product_id IN (11, 42)
ORDER BY product_id;

-- Task 13a. Consistency constraint
ALTER TABLE products
ADD CONSTRAINT chk_units_in_stock CHECK (units_in_stock >= 0);

BEGIN;
-- Expected error: new row for relation "products" violates check constraint
UPDATE products
SET units_in_stock = units_in_stock - 100
WHERE product_id = 42; -- expected error
ROLLBACK;

-- Clean-up
DELETE FROM order_details WHERE order_id = 11078;
DELETE FROM orders WHERE order_id = 11078;
UPDATE products SET units_in_stock = units_in_stock + 5 WHERE product_id = 11;
UPDATE products SET units_in_stock = units_in_stock + 1 WHERE product_id = 42;
DELETE FROM customers WHERE customer_id = 'AITU1';
UPDATE customers
SET phone = '(171) 555-7788'
WHERE customer_id = 'AROUT';
ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_units_in_stock;
DROP MATERIALIZED VIEW IF EXISTS mv_category_sales;
DROP VIEW IF EXISTS v_uk_customers, v_order_totals;
DROP INDEX IF EXISTS idx_orders_big_customer;
DROP INDEX IF EXISTS idx_orders_big_country_date;
DROP INDEX IF EXISTS idx_orders_big_heavy;
DROP INDEX IF EXISTS idx_orders_big_city_lower;
DROP TABLE IF EXISTS orders_big;

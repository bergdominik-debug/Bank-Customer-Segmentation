-- List of primary keys
SELECT 
    t.name AS table_name,
    c.name AS column_name
FROM sys.key_constraints k
JOIN sys.tables t ON k.parent_object_id = t.object_id
JOIN sys.index_columns ic ON ic.object_id = t.object_id AND ic.index_id = k.unique_index_id
JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = ic.column_id
WHERE k.type = 'PK'
ORDER BY table_name, column_name
;

-- Are primary keys unique?
SELECT *
FROM (
	SELECT
	*,
	ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY account_id) AS rn
	FROM accounts
) t
WHERE rn > 1
;

SELECT *
FROM (
	SELECT
	*,
	ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_id) AS rn
	FROM customers
) t
WHERE rn > 1
;

SELECT *
FROM (
	SELECT
	*,
	ROW_NUMBER() OVER (PARTITION BY region ORDER BY region) AS rn
	FROM regions
) t
WHERE rn > 1
;

SELECT *
FROM (
	SELECT
	*,
	ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_id) AS rn
	FROM transactions
) t
WHERE rn > 1
;
-- No duplicates in primary key columns.

-- Verification of referential integrity
SELECT *
FROM accounts AS a
WHERE NOT EXISTS (
	SELECT 1
	FROM customers AS c
	WHERE c.customer_id = a.customer_id
	)
;

SELECT *
FROM customers AS c
WHERE NOT EXISTS (
	SELECT 1
	FROM regions AS r
	WHERE r.region = c.region
	)
;

SELECT *
FROM transactions AS t
WHERE NOT EXISTS (
	SELECT 1
	FROM accounts AS a
	WHERE a.account_id = t.account_id
	)
;
-- Referential integrity checks passed. 
-- Foreign key constraints could be added to enforce these relationships at the database level.

-- NULL value check
DECLARE @sql nvarchar(max);
DECLARE @tabulka nvarchar(128) = 'customers';

SELECT @sql = 
    'SELECT * FROM ' + QUOTENAME(@tabulka) + ' WHERE ' +
    STRING_AGG(QUOTENAME(COLUMN_NAME) + ' IS NULL', ' OR ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @tabulka;

EXEC sp_executesql @sql
;

DECLARE @sql nvarchar(max);
DECLARE @tabulka nvarchar(128) = 'regions';

SELECT @sql = 
    'SELECT * FROM ' + QUOTENAME(@tabulka) + ' WHERE ' +
    STRING_AGG(QUOTENAME(COLUMN_NAME) + ' IS NULL', ' OR ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @tabulka;

EXEC sp_executesql @sql
;

DECLARE @sql nvarchar(max);
DECLARE @tabulka nvarchar(128) = 'regions';

SELECT @sql = 
    'SELECT * FROM ' + QUOTENAME(@tabulka) + ' WHERE ' +
    STRING_AGG(QUOTENAME(COLUMN_NAME) + ' IS NULL', ' OR ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @tabulka;

EXEC sp_executesql @sql
;

DECLARE @sql nvarchar(max);
DECLARE @tabulka nvarchar(128) = 'transactions';

SELECT @sql = 
    'SELECT * FROM ' + QUOTENAME(@tabulka) + ' WHERE ' +
    STRING_AGG(QUOTENAME(COLUMN_NAME) + ' IS NULL', ' OR ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @tabulka;

EXEC sp_executesql @sql
;
--There are no NULL values in any table.

-- Verification of transactions with negative or zero amounts
SELECT 
    transaction_type,
    CASE
        WHEN amount < 0 THEN 'negative'
        WHEN amount = 0 THEN 'zero'
        WHEN amount > 0 THEN 'positive'
    END AS amount_category,
    COUNT(transaction_id) AS total_count
FROM transactions
GROUP BY 
    transaction_type,
    CASE
        WHEN amount < 0 THEN 'negative'
        WHEN amount = 0 THEN 'zero'
        WHEN amount > 0 THEN 'positive'
    END
;

-- Control that all transactions were included
SELECT 
    (SELECT COUNT(*) 
     FROM transactions) AS total_transactions,
    (SELECT SUM(total_count)
     FROM (
         SELECT 
             transaction_type,
             CASE
                 WHEN amount < 0 THEN 'negative'
                 WHEN amount = 0 THEN 'zero'
                 ELSE 'positive'
             END AS amount_category,
             COUNT(*) AS total_count
         FROM transactions
         GROUP BY 
             transaction_type,
             CASE
                 WHEN amount < 0 THEN 'negative'
                 WHEN amount = 0 THEN 'zero'
                 ELSE 'positive'
             END
     ) AS x) AS aggregated_total
;
--The dataset consistently associates each transaction type with a single sign of the transaction amount. 
-- No zero-amount transactions were identified.

-- Are there any transactions before the account opening date?
SELECT t.*, a.open_date
FROM transactions AS t
LEFT JOIN accounts AS a ON t.account_id=a.account_id
WHERE t.date < CAST(a.open_date AS date)
ORDER BY t.date
;

WITH it AS (
	SELECT t.*, a.open_date
	FROM transactions AS t
	LEFT JOIN accounts AS a ON t.account_id=a.account_id
	WHERE t.date < CAST(a.open_date AS date)
)
SELECT YEAR(it.date) AS t_year, MONTH(it.date) AS t_month, COUNT(transaction_id) AS t_count
FROM it
GROUP BY YEAR(it.date), MONTH(it.date) WITH ROLLUP
;

WITH total_transactions AS (
	SELECT COUNT(*) AS total_count
	FROM transactions
),
it AS (
	SELECT COUNT(*) AS invalid_count
	FROM transactions AS t
	LEFT JOIN accounts AS a ON t.account_id=a.account_id
	WHERE t.date < CAST(a.open_date AS date)
)
SELECT total_transactions.total_count,
		it.invalid_count,
		it.invalid_count*100.0 /total_transactions.total_count AS ratio
FROM total_transactions
CROSS JOIN it
;
-- We identified 273,427 transactions occurring before the recorded account open_date., i.e. 28.38 % of all transactions.
-- The highest number of transactions preceding the recorded account opening date occurs in 2022, 
-- followed by a decreasing trend.
-- This is very important for the quality of data.

-- Are there any transaction after closing date of an account?
-- This check cannot be performed because close_date is missing
-- from the supplied accounts dataset, although it is specified
-- in the project documentation.


-- Are there any accounts without customer?
-- No accounts without a customer were identified. 
-- This is supported by the NULL-value and referential-integrity checks above.

-- Are there any customers without an account?
SELECT *, a.Customer_id
FROM customers AS c
LEFT JOIN accounts AS a ON c.customer_id = a.customer_id
WHERE a.customer_id IS NULL
;

-- No customers without an account were identified

-- Are there any extreme values?
-- Stats for age of customers
SELECT DISTINCT
	MIN(age) OVER () AS minimum,
	MAX(age) OVER () AS maximum,
	AVG(age) OVER () AS average,
	STDEV(age) OVER () AS standard_deviation,
	PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY age) OVER () as p25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER () as p50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY age) OVER () as p75
FROM customers
;

-- List of the outliers in customers table from the perspective of the age
WITH stats AS (
    SELECT TOP 1
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY age) OVER () AS p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY age) OVER () AS p75
    FROM customers
)
SELECT c.*
FROM customers c
CROSS JOIN stats s
WHERE c.age < s.p25 - 1.5 * (s.p75 - s.p25)
   OR c.age > s.p75 + 1.5 * (s.p75 - s.p25)
ORDER BY c.age
;
-- We have 76 statistical outliers. These are customers older than 82 years.

-- Stats for the population column in the regions table
SELECT DISTINCT
	MIN(r.population) OVER () AS minimum,
	MAX(r.population) OVER () AS maximum,
	AVG(r.population) OVER () AS average,
	STDEV(r.population) OVER () AS standard_deviation,
	PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY r.population) OVER () as p25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.population) OVER () as p50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY r.population) OVER () as p75
FROM regions as r
;

-- List of the outliers in regions table from the perspective of the population column
WITH stats AS (
    SELECT TOP 1
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY r.population) OVER () AS p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY r.population) OVER () AS p75
    FROM regions as r
)
SELECT r.*
FROM regions r
CROSS JOIN stats s
WHERE r.population < s.p25 - 1.5 * (s.p75 - s.p25)
   OR r.population > s.p75 + 1.5 * (s.p75 - s.p25)
ORDER BY r.population
;
-- Only one statistical outlier was identified in the population distribution.
-- It is Metro region with 1500000 people living there.

-- Stats for the transactions table and the amount column
SELECT DISTINCT
	MIN(t.amount) OVER () AS minimum,
	MAX(t.amount) OVER () AS maximum,
	AVG(t.amount) OVER () AS average,
	STDEV(t.amount) OVER () AS standard_deviation,
	PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY t.amount) OVER () as p25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.amount) OVER () as p50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY t.amount) OVER () as p75
FROM transactions as t
;

-- List of the outliers in transactions table from the perspective of the amount column
WITH stats AS (
    SELECT TOP 1
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY t.amount) OVER () AS p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY t.amount) OVER () AS p75
    FROM transactions as t
)
SELECT t.*
FROM transactions as t
CROSS JOIN stats s
WHERE t.amount < s.p25 - 1.5 * (s.p75 - s.p25)
   OR t.amount > s.p75 + 1.5 * (s.p75 - s.p25)
ORDER BY t.amount
;

-- Limits of amount for statistical outliers
WITH stats AS (
	SELECT TOP 1
			PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY t.amount) OVER () AS p25,
			PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY t.amount) OVER () AS p75
	FROM transactions as t
)
SELECT s.p25 - 1.5 * (s.p75 - s.p25) AS lower_limit,
		s.p75 + 1.5 * (s.p75 - s.p25) AS upper_limit
FROM stats as s

-- We identified 79,583 statistical outliers. in the transactions table from the perspective of amount.
-- The statistical outliers are transactions with the amount lower than -135.91 or higher than 127.45.
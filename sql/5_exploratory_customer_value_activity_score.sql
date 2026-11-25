-- 5 - Metrics definitions - Customer activity

/*
Exploratory analysis.

This metric was developed to evaluate one possible interpretation
of the customer activity concept described in the project specification.

The resulting score was not selected as the primary segmentation
framework because its interpretation depends on business-specific
assumptions regarding transaction value, transaction type weighting,
and the relative importance of activity versus volume.
*/

-- Customer Value-Activity Score
-- Verifying whether any customers have more than one open account.
-- We cannot involve closed accounts because we don't know the date when they were closed, i.e. we don't know how long they were active.
SELECT c.customer_id,
	c.name,
	COUNT(*) AS active_accounts,
	MIN(a.open_date) AS opendate
FROM customers AS c
INNER JOIN accounts AS a ON c.customer_id = a.customer_id
WHERE a.status != 'closed'
GROUP BY c.customer_id, c.name
ORDER BY active_accounts DESC
;

SELECT c.customer_id,
	c.name,
	MIN(a.open_date) AS first_open_date,
	COUNT(t.transaction_id) AS number_of_transactions,
	COALESCE(SUM(ABS(t.amount)),0) AS transactions_volume,
	MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31'))+1 AS months_of_activity
FROM customers AS c
INNER JOIN accounts AS a ON c.customer_id = a.customer_id
LEFT JOIN transactions AS t ON a.account_id = t.account_id
WHERE a.status != 'closed'
GROUP BY c.customer_id, c.name
ORDER BY c.customer_id
;


-- Customer Value-Activity Score - combination of frequency and amount of transactions
WITH stats AS (
    SELECT 
        c.customer_id,
		c.name,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        COALESCE(SUM(ABS(t.amount)),0) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(COALESCE(SUM(ABS(t.amount)),0) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status != 'closed'
    GROUP BY c.customer_id, c.name
)
SELECT
    s.customer_id,
	s.name,
    CAST(ROUND(s.transactions_monthly_raw, 2) AS decimal(10,2)) AS transactions_monthly,
    CAST(ROUND(s.volume_monthly_raw, 2) AS decimal(18,2)) AS volume_monthly
FROM stats AS s;

-- EDA to determine normalization method
-- The metrics must be normalized before they can be combined into a single composite score.
WITH stats AS (
    SELECT 
        c.customer_id,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        COALESCE(SUM(ABS(t.amount)),0) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(COALESCE(SUM(ABS(t.amount)),0) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status != 'closed'
    GROUP BY c.customer_id
)
SELECT DISTINCT
	MIN(s.transactions_monthly_raw) OVER () AS minimum,
	MAX(s.transactions_monthly_raw) OVER () AS maximum,
	AVG(s.transactions_monthly_raw) OVER () AS average,
	STDEV(s.transactions_monthly_raw) OVER () AS standard_deviation,
	PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY s.transactions_monthly_raw) OVER () as p25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.transactions_monthly_raw) OVER () as p50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY s.transactions_monthly_raw) OVER () as p75
FROM stats AS s
;

WITH stats AS (
    SELECT 
        c.customer_id,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        COALESCE(SUM(ABS(t.amount)),0) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(COALESCE(SUM(ABS(t.amount)),0) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status != 'closed'
    GROUP BY c.customer_id
)
SELECT DISTINCT
	MIN(s.volume_monthly_raw) OVER () AS minimum,
	MAX(s.volume_monthly_raw) OVER () AS maximum,
	AVG(s.volume_monthly_raw) OVER () AS average,
	STDEV(s.volume_monthly_raw) OVER () AS standard_deviation,
	PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY s.volume_monthly_raw) OVER () as p25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.volume_monthly_raw) OVER () as p50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY s.volume_monthly_raw) OVER () as p75
FROM stats AS s
;
-- The distributions indicate that median and IQR-based scaling is more appropriate than mean and standard-deviation scaling because both metrics are strongly right-skewed and contain extreme values.

-- Overview of customers by their Value-Activity Score
WITH stats AS (
    SELECT 
        c.customer_id,
		c.name,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        COALESCE(SUM(ABS(t.amount)),0) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(COALESCE(SUM(ABS(t.amount)),0) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status != 'closed'
    GROUP BY c.customer_id, c.name
),
percentiles AS (
    SELECT TOP 1
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p75,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p75
    FROM stats
)
SELECT
    s.customer_id,
	s.name,
    CAST(s.transactions_monthly_raw AS decimal(18,2)) AS transactions_monthly,
    CAST(s.volume_monthly_raw AS decimal(18,2)) As volume_monthly,
    ROUND((s.transactions_monthly_raw - p.t_p50) / NULLIF(p.t_p75 - p.t_p25, 0),2) AS transactions_monthly_iqr_norm,
    ROUND((s.volume_monthly_raw - p.v_p50) / NULLIF(p.v_p75 - p.v_p25, 0),2) AS volume_monthly_iqr_norm,
	ROUND(((s.transactions_monthly_raw - p.t_p50) / NULLIF(p.t_p75 - p.t_p25, 0)) + ((s.volume_monthly_raw - p.v_p50) / NULLIF(p.v_p75 - p.v_p25, 0)),2) AS customer_value_activity_score

FROM stats AS s
CROSS JOIN percentiles AS p
ORDER BY customer_value_activity_score DESC
;

--6. Customer segmentation

-- 6.1 High-value active
-- Identification of the top 10% of customers, i.e. customers with the highest volume and frequency of transactions in the last six months

-- Ranked overview of the customers by their activity and volume of transactions
WITH base AS (
	SELECT c.customer_id,
		c.name,
		COUNT(t.transaction_id) AS tx_freq,
		SUM(ABS(t.amount)) AS tx_volume
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE a.open_date < '2025-07-01' AND a.status = 'active'
		AND t.date BETWEEN '2025-07-01' AND '2025-12-31'
	GROUP BY c.customer_id, c.name
	HAVING COUNT(t.transaction_id) > 0
)
SELECT TOP 10 PERCENT *,
	RANK() OVER(ORDER BY tx_freq DESC) AS freq_rank,
	RANK() OVER(ORDER BY tx_volume DESC) AS volume_rank,
	RANK() OVER(ORDER BY tx_freq DESC) + RANK() OVER(ORDER BY tx_volume DESC) AS total_rank
FROM base
ORDER BY total_rank, customer_id
;

-- Basic check for anomalies, such as customers with an unusually high transaction count but low transaction volume, or vice versa.
WITH base AS (
	SELECT c.customer_id,
		c.name,
		COUNT(t.transaction_id) AS tx_freq,
		SUM(ABS(t.amount)) AS tx_volume
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE a.open_date < '2025-07-01' AND a.status = 'active'
		AND t.date BETWEEN '2025-07-01' AND '2025-12-31'
	GROUP BY c.customer_id, c.name
	HAVING COUNT(t.transaction_id) > 0
),
ranked AS (
	SELECT TOP 10 PERCENT *,
	RANK() OVER(ORDER BY tx_freq DESC) AS freq_rank,
	RANK() OVER(ORDER BY tx_volume DESC) AS volume_rank,
	RANK() OVER(ORDER BY tx_freq DESC) + RANK() OVER(ORDER BY tx_volume DESC) AS total_rank
	FROM base
	ORDER BY total_rank
)
SELECT
	MAX(r.freq_rank) AS freq_max_rank,
	MAX(r.volume_rank) AS volume_max_rank,
	MAX(r.total_rank) AS max_total_rank,
	COUNT(r.customer_id) AS count_of_rows,
	MAX(ABS(r.freq_rank - r.volume_rank)) AS max_diff
FROM ranked AS r
;

-- Overview of customers ordered from the biggest difference between their rank in relation to the activity and transaction volume to the lowest difference
WITH base AS (
	SELECT c.customer_id,
		c.name,
		COUNT(t.transaction_id) AS tx_freq,
		SUM(ABS(t.amount)) AS tx_volume
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE a.open_date < '2025-07-01' AND a.status = 'active'
		AND t.date BETWEEN '2025-07-01' AND '2025-12-31'
	GROUP BY c.customer_id, c.name
	HAVING COUNT(t.transaction_id) > 0
),
ranked AS (
	SELECT TOP 10 PERCENT *,
	RANK() OVER(ORDER BY tx_freq DESC) AS freq_rank,
	RANK() OVER(ORDER BY tx_volume DESC) AS volume_rank,
	RANK() OVER(ORDER BY tx_freq DESC) + RANK() OVER(ORDER BY tx_volume DESC) AS total_rank
	FROM base
	ORDER BY total_rank
)
SELECT
	r.customer_id,
	r.name,
	r.tx_freq,
	r.tx_volume,
	MAX(ABS(r.freq_rank - r.volume_rank)) AS max_rank_diff
FROM ranked AS r
GROUP BY r.customer_id, r.name, r.tx_freq, r.tx_volume
ORDER BY max_rank_diff DESC
;


--6.2 High-value low activity
-- Overview of customers with declining activity and at least one account opened six months before the end of the observation period

WITH customer_account_monthly AS (
	SELECT c.customer_id,
		c.name,
		a.account_id,
		a.open_date,
		DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1) AS tx_month,
		COUNT(*) AS tx_count,
		COUNT(*) OVER (PARTITION BY a.account_id) AS month_count
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY c.customer_id, c.name, a.account_id, a.open_date, DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1)
),
customer_monthly AS (
	SELECT
		cam.customer_id,
		cam.name,
		cam.tx_month,
		MIN(cam.open_date) AS first_account_open_date,
		SUM(cam.tx_count) AS tx_count
	FROM customer_account_monthly AS cam
	GROUP BY cam.customer_id, cam.name, cam.tx_month
	HAVING MIN(cam.open_date) <= '2025-07-01'
),
indexed AS (
	SELECT *,
		ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY tx_month) AS idx,
		COUNT(*) OVER (PARTITION BY customer_id) AS customer_month_count
	FROM customer_monthly
),
trend AS (
	SELECT 
		customer_id,
		(
			SUM(idx*tx_count)
			- SUM(idx) * SUM(tx_count) *1.0/ COUNT(*)
		)
		/
		(
			SUM(idx*idx)
			- SUM(idx)*SUM(idx)*1.0/COUNT(*)
		) AS slope
	FROM indexed
	WHERE indexed.customer_month_count >= 3
	GROUP BY customer_id
)
SELECT *
FROM trend
WHERE slope < 0
;

-- Overview of customers with high-value and low/declining activity
;WITH stats AS (
    SELECT 
        c.customer_id,
        c.name,
        CAST(MIN(a.open_date) AS date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        SUM(ABS(t.amount)) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(
            CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
            CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4))
        AS decimal(18,2)) AS transactions_monthly,
        CAST(
            CAST(SUM(ABS(t.amount)) AS decimal(18,4)) /
            CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4))
        AS decimal(18,2)) AS volume_monthly

    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status = 'active'
    GROUP BY c.customer_id, c.name
),
customer_account_monthly AS (
	SELECT c.customer_id,
		c.name,
		a.account_id,
		a.open_date,
		DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1) AS tx_month,
		COUNT(*) AS tx_count,
		COUNT(*) OVER (PARTITION BY a.account_id) AS month_count
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY c.customer_id, c.name, a.account_id, a.open_date, DATEFROMPARTS(YEAR(t.date), MONTH(t.date), 1)
),
customer_monthly AS (
	SELECT
		cam.customer_id,
		cam.name,
		cam.tx_month,
		MIN(cam.open_date) AS first_account_open_date,
		SUM(cam.tx_count) AS tx_count
	FROM customer_account_monthly AS cam
	GROUP BY cam.customer_id, cam.name, cam.tx_month
	HAVING MIN(cam.open_date) <= '2025-07-01'
),
indexed AS (
	SELECT *,
		ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY tx_month) AS idx,
		COUNT(*) OVER (PARTITION BY customer_id) AS customer_month_count
	FROM customer_monthly
),
trend AS (
	SELECT 
		customer_id,
		(
			SUM(idx*tx_count)
			- SUM(idx) * SUM(tx_count) *1.0/ COUNT(*)
		)
		/
		(
			SUM(idx*idx)
			- SUM(idx)*SUM(idx)*1.0/COUNT(*)
		) AS slope
	FROM indexed
	WHERE indexed.customer_month_count >= 3
	GROUP BY customer_id
),
declining_customers AS (
    SELECT customer_id
    FROM trend
    WHERE slope < 0
),
percentiles AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transactions_monthly) OVER () AS t_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY volume_monthly) OVER () AS v_p75
    FROM stats
)
SELECT *
FROM stats
LEFT JOIN declining_customers AS dc ON stats.customer_id=dc.customer_id
CROSS JOIN percentiles AS p
WHERE 
    stats.volume_monthly >= p.v_p75
    AND (
        stats.transactions_monthly <= p.t_p25
		OR dc.customer_id IS NOT NULL
    )
;



-- 6.3 Active mass customers
-- The specification does not define what “standard” means.
-- We defined standard activity and value as falling between the 25th and 75th percentiles.

WITH stats AS (
    SELECT 
        c.customer_id,
        c.name,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        SUM(ABS(t.amount)) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(SUM(ABS(t.amount)) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, '2025-12-31')) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status = 'active'
    GROUP BY c.customer_id, c.name
),
percentiles AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p75,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p75
    FROM stats
)
SELECT 
    s.customer_id,
    s.name,
    CAST(ROUND(s.transactions_monthly_raw,2) AS decimal(18,2)) AS transactions_monthly,
    CAST(ROUND(s.volume_monthly_raw,2) AS decimal(18,2)) AS volume_monthly
FROM stats AS s
CROSS JOIN percentiles AS p
WHERE (s.transactions_monthly_raw BETWEEN p.t_p25 AND p.t_p75)
AND (s.volume_monthly_raw BETWEEN p.v_p25 AND p.v_p75)
;


--6.4 Low-value / low-activity (with exclusion of dormant accounts)
WITH
base AS (
	SELECT c.customer_id,
		c.name,
		COUNT(t.transaction_id) AS tx_freq,
		SUM(ABS(t.amount)) AS tx_volume
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE a.open_date < '2025-07-01' AND a.status = 'active'
		AND t.date BETWEEN '2025-07-01' AND '2025-12-31'
	GROUP BY c.customer_id, c.name
	HAVING COUNT(t.transaction_id) > 0
)
SELECT TOP 10 PERCENT *,
	RANK() OVER(ORDER BY tx_freq DESC) AS freq_rank,
	RANK() OVER(ORDER BY tx_volume DESC) AS volume_rank,
	RANK() OVER(ORDER BY tx_freq DESC) + RANK() OVER(ORDER BY tx_volume DESC) AS total_rank
FROM base
ORDER BY 
	total_rank DESC,
	customer_id
;


--6.5 Dormant Customers/Accounts
SELECT c.customer_id,
	a.account_id,
	MAX(t.date) AS last_transaction_date
FROM customers AS c
INNER JOIN accounts AS a ON c.customer_id=a.customer_id
LEFT JOIN transactions AS t ON a.account_id=t.account_id
WHERE a.status <> 'closed'
	AND DATEDIFF(DAY,a.open_date,'2025-12-31') >= 180
GROUP BY c.customer_id,a.account_id
HAVING MAX(t.date) IS NULL
	OR MAX(t.date) < DATEADD(day, -180, '2025-12-31')
ORDER BY c.customer_id ASC
;
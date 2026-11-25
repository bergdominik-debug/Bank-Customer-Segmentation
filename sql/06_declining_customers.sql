-- 9.6 Declining customers
DECLARE @period_end DATE = '2025-12-31';
DECLARE @period_start DATE = DATEFROMPARTS(
        YEAR(@period_end),
        MONTH(@period_end) - 5,
        1
    );


WITH calendar AS (
	SELECT CAST('2025-07-01' AS DATE) AS month_start
		UNION ALL SELECT '2025-08-01'
		UNION ALL SELECT '2025-09-01'
		UNION ALL SELECT '2025-10-01'
		UNION ALL SELECT '2025-11-01'
		UNION ALL SELECT '2025-12-01'
),
customer_ids AS (
	SELECT DISTINCT
		c.customer_id
	FROM customers AS C
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	WHERE a.status IN ('active', 'dormant')
		AND a.open_date < DATEFROMPARTS(
			YEAR(@period_end),
			MONTH(@period_end) - 2,
			1
		)
),
customers_calendar_base AS (
	SELECT *
	FROM customer_ids AS ci
	CROSS JOIN calendar
),
customers_monthly_activity AS (
	SELECT
		ccb.customer_id,
		ccb.month_start,
		COUNT(t.transaction_id) AS count_transactions
	FROM customers_calendar_base AS ccb
	INNER JOIN accounts AS a ON ccb.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
		AND t.date BETWEEN @period_start AND @period_end
		AND ccb.month_start=DATEFROMPARTS(
				YEAR(t.date),
				MONTH(t.date),
				1
			)
	GROUP BY ccb.customer_id,ccb.month_start
),
customers_quarterly_activity AS (
	SELECT
		cma.customer_id,
		 AVG(
			CASE
				WHEN cma.month_start < DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) AS avg_first_3m,
		AVG(
			CASE
				WHEN cma.month_start >= DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) AS avg_last_3m
	FROM customers_monthly_activity AS cma
	GROUP BY cma.customer_id
	HAVING AVG(
			CASE
				WHEN cma.month_start < DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) > 0
)
SELECT
	cqa.customer_id,
	cqa.avg_first_3m,
	cqa.avg_last_3m,
	100.0 * 
		(cqa.avg_last_3m - cqa.avg_first_3m)
		/ cqa.avg_first_3m
		AS pct_decline,
	cqa.avg_last_3m - cqa.avg_first_3m AS abs_decline
FROM customers_quarterly_activity AS cqa
WHERE cqa.avg_last_3m - cqa.avg_first_3m < 0
ORDER BY pct_decline, abs_decline
;


-- Summary
WITH calendar AS (
	SELECT CAST('2025-07-01' AS DATE) AS month_start
		UNION ALL SELECT '2025-08-01'
		UNION ALL SELECT '2025-09-01'
		UNION ALL SELECT '2025-10-01'
		UNION ALL SELECT '2025-11-01'
		UNION ALL SELECT '2025-12-01'
),
customer_ids AS (
	SELECT DISTINCT
		c.customer_id
	FROM customers AS C
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	WHERE a.status IN ('active', 'dormant')
		AND a.open_date < DATEFROMPARTS(
			YEAR(@period_end),
			MONTH(@period_end) - 2,
			1
		)
),
customers_calendar_base AS (
	SELECT *
	FROM customer_ids AS ci
	CROSS JOIN calendar
),
customers_monthly_activity AS (
	SELECT
		ccb.customer_id,
		ccb.month_start,
		COUNT(t.transaction_id) AS count_transactions
	FROM customers_calendar_base AS ccb
	INNER JOIN accounts AS a ON ccb.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
		AND t.date BETWEEN @period_start AND @period_end
		AND ccb.month_start=DATEFROMPARTS(
				YEAR(t.date),
				MONTH(t.date),
				1
			)
	GROUP BY ccb.customer_id,ccb.month_start
),
customers_quarterly_activity AS (
	SELECT
		cma.customer_id,
		 AVG(
			CASE
				WHEN cma.month_start < DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) AS avg_first_3m,
		AVG(
			CASE
				WHEN cma.month_start >= DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) AS avg_last_3m
	FROM customers_monthly_activity AS cma
	GROUP BY cma.customer_id
	HAVING AVG(
			CASE
				WHEN cma.month_start < DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end) - 2,
					1
				)
				THEN cma.count_transactions
			END
		) > 0
),
declining_customers AS (
	SELECT
		cqa.customer_id,
		cqa.avg_first_3m,
		cqa.avg_last_3m,
		100.0 * 
			(cqa.avg_last_3m - cqa.avg_first_3m)
			/ cqa.avg_first_3m
			AS pct_decline,
		cqa.avg_last_3m - cqa.avg_first_3m AS abs_decline
	FROM customers_quarterly_activity AS cqa
	WHERE cqa.avg_last_3m - cqa.avg_first_3m < 0
),
declining_customers_stats AS (
	SELECT
		COUNT(*) AS count_declining_customers,
		AVG(dc.avg_first_3m) AS avg_activity_q3,
		AVG(dc.avg_last_3m) AS avg_activity_q4,
		MIN(dc.abs_decline) AS highest_abs_decline,
		MAX(dc.abs_decline) AS lowest_abs_decline,
		MIN(dc.pct_decline) AS highest_pct_decline,
		MAX(dc.pct_decline) AS lowest_pct_decline
	FROM declining_customers AS dc
),
total_customers AS (
	SELECT
		'All customers' AS metric,
		COUNT(*) AS value
	FROM customers AS c
),
total_eligible_customers AS (
	SELECT
		'Eligible customers' AS metric,
		COUNT(DISTINCT c.customer_id) AS value
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	WHERE a.status IN ('active', 'dormant')
		AND a.open_date < DATEFROMPARTS(
			YEAR(@period_end),
			MONTH(@period_end) - 2,
			1
		)
),
summary AS (
	SELECT
		1 AS sort_order,
		'Total declining customers' AS metric,
		dcs.count_declining_customers AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		2 AS sort_order,
		'Share of declining customers of all customers' AS metric,
		(100.0 * dcs.count_declining_customers
			/
			(
				SELECT value
				FROM total_customers
			)) AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		3 AS sort_order,
		'Share of declining customers of eligible customers' AS metric,
		(100.0 * dcs.count_declining_customers
			/
			(
				SELECT value
				FROM total_eligible_customers
			)) AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		4 AS sort_order,
		'Average customer activity in Q3' AS metric,
		dcs.avg_activity_q3 AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		5 AS sort_order,
		'Average customer activity in Q4' AS metric,
		dcs.avg_activity_q4 AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		6 AS sort_order,
		'Highest absolute decline' AS metric,
		dcs.highest_abs_decline AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		7 AS sort_order,
		'Lowest absolute decline' AS metric,
		dcs.lowest_abs_decline AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		8 AS sort_order,
		'Highest decline in %' AS metric,
		dcs.highest_pct_decline AS value
	FROM declining_customers_stats AS dcs
	UNION ALL
	SELECT
		9 AS sort_order,
		'Lowest decline in %' AS metric,
		dcs.lowest_pct_decline AS value
	FROM declining_customers_stats AS dcs
)
SELECT
	s.metric,
	s.value
FROM summary AS s
ORDER BY sort_order
;

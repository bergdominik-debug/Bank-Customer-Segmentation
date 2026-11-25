-- Audit of customers attributes
-- We consider these attributes: 
	-- value_quartile, 
	-- active_30d, 
	-- dormant_180d, 
	-- declining_6m
	-- customers_status (based on accounts status)


DECLARE @data_start_date DATE = '2022-01-01';
DECLARE @period_end DATE = '2025-12-31';
DECLARE @period_duration INT = 30;
DECLARE @period_dormancy_length INT = 180;

WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @data_start_date
                THEN @data_start_date
            WHEN DAY(a.open_date) <= 15
                THEN DATEFROMPARTS(YEAR(a.open_date), MONTH(a.open_date), 1)
            ELSE DATEADD(
                MONTH,
                1,
                DATEFROMPARTS(YEAR(a.open_date), MONTH(a.open_date), 1)
            )
        END AS adjusted_account_open_date
    FROM customers AS c
    INNER JOIN accounts AS a
        ON c.customer_id = a.customer_id
    WHERE a.status IN ('active', 'dormant')
        AND a.open_date < DATEADD(
				MONTH,
				-2,
				DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end),
					1
				)
			)
),
customer_observation_period AS (
    SELECT
        customer_id,
        MIN(adjusted_account_open_date) AS observation_start_date
    FROM eligible_accounts
    GROUP BY customer_id
),
customer_transaction_metrics AS (
    SELECT
        cop.customer_id,
        SUM(ABS(t.amount)) AS gross_transaction_volume
    FROM customer_observation_period AS cop
    INNER JOIN eligible_accounts AS ea
        ON cop.customer_id = ea.customer_id
    INNER JOIN transactions AS t
        ON ea.account_id = t.account_id
    WHERE t.date >= cop.observation_start_date
        AND t.date < DATEADD(DAY, 1, @period_end)
    GROUP BY cop.customer_id
),
customer_value_base AS (
	SELECT
		cop.customer_id,
		cop.observation_start_date,
		DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1
			AS observation_months,
		ctm.gross_transaction_volume,
		ROUND(
			CAST(ctm.gross_transaction_volume AS DECIMAL(18, 2))
			/ (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
			2
		) AS avg_monthly_gross_transaction_volume
	FROM customer_observation_period AS cop
	INNER JOIN customer_transaction_metrics AS ctm
		ON cop.customer_id = ctm.customer_id
),
customers_quartiles AS (
	SELECT
		cvb.customer_id,
		cvb.gross_transaction_volume,
		cvb.avg_monthly_gross_transaction_volume,
		NTILE(4) OVER (
			ORDER BY cvb.avg_monthly_gross_transaction_volume
		) AS customer_value_quartile
	FROM customer_value_base AS cvb
),
active_customers_in_30_days AS (
	SELECT
		c.customer_id,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY c.customer_id
	HAVING MAX(t.date) >= DATEADD(day, - @period_duration, @period_end)
),
dormant_customers_180_days AS (
	SELECT
		c.customer_id,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_dormancy_length
		AND a.status IN ('active', 'dormant')
	GROUP BY c.customer_id
	HAVING MAX(t.date) < DATEADD(day,-@period_dormancy_length,@period_end)
		OR MAX(t.date) IS NULL
),
calendar AS (
	SELECT CAST('2025-07-01' AS DATE) AS month_start
		UNION ALL SELECT '2025-08-01'
		UNION ALL SELECT '2025-09-01'
		UNION ALL SELECT '2025-10-01'
		UNION ALL SELECT '2025-11-01'
		UNION ALL SELECT '2025-12-01'
),
customers_ids AS (
	SELECT DISTINCT
		c.customer_id
	FROM customers AS C
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	WHERE a.status IN ('active', 'dormant')
        AND a.open_date < DATEADD(
				MONTH,
				-2,
				DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end),
					1
				)
			)
),
customers_calendar_base AS (
	SELECT *
	FROM customers_ids AS ci
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
		AND t.date BETWEEN DATEADD(month, -6,@period_end) AND @period_end
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
				WHEN cma.month_start < DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
					)
				THEN cma.count_transactions
			END
		) AS avg_first_3m,
		AVG(
			CASE
				WHEN cma.month_start >= DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
					)
				THEN cma.count_transactions
			END
		) AS avg_last_3m
	FROM customers_monthly_activity AS cma
	GROUP BY cma.customer_id
	HAVING AVG(
			CASE
				WHEN cma.month_start < DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
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
customer_status_prep AS (
	SELECT
		c.customer_id,
		MAX(
            CASE
                WHEN a.status = 'active'
                THEN 1
                ELSE 0
            END
        ) AS has_active_account,
		MAX(
            CASE
                WHEN a.status = 'dormant'
                THEN 1
                ELSE 0
            END
        ) AS has_dormant_account,
		MAX(
            CASE
                WHEN a.status = 'closed'
                THEN 1
                ELSE 0
            END
        ) AS has_closed_account
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	GROUP BY c.customer_id
),
customers_status AS (
	SELECT
		csp.customer_id,
		CASE
			WHEN csp.has_active_account = 1
				THEN 'active'
			WHEN csp.has_dormant_account = 1
				THEN 'dormant'
			ELSE 'closed'
		END AS customer_status
	FROM customer_status_prep AS csp
),
customers_attributes_matrix AS (
	SELECT
		cs.customer_id,
		cq.customer_value_quartile AS value_quartile,
		CASE
			WHEN ac30d.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS active_30d,
		CASE
			WHEN dc180d.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS dormant_180d,
		CASE
			WHEN dc.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS declining_6m,
		cs.customer_status
	FROM customers_status AS cs
	LEFT JOIN customers_quartiles AS cq ON cs.customer_id=cq.customer_id
	LEFT JOIN active_customers_in_30_days AS ac30d ON cs.customer_id = ac30d.customer_id
	LEFT JOIN dormant_customers_180_days AS dc180d ON cs.customer_id = dc180d.customer_id
	LEFT JOIN declining_customers AS dc ON cs.customer_id=dc.customer_id
)
SELECT
	'Total customers count' AS metric,
	COUNT(cam.customer_id) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Q1_value customers' AS metric,
	SUM(
		CASE
			WHEN cam.value_quartile = 1 THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Q2_value customers' AS metric,
	SUM(
		CASE
			WHEN cam.value_quartile = 2 THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Q3_value customers' AS metric,
	SUM(
		CASE
			WHEN cam.value_quartile = 3 THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Q4_value customers' AS metric,
	SUM(
		CASE
			WHEN cam.value_quartile = 4 THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Customers without quartile' AS metric,
	SUM(
		CASE
			WHEN cam.value_quartile IS NULL THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Active customers in last 30 days' AS metric,
	SUM(cam.active_30d) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Dormant customers in 180 days' AS metric,
	SUM(cam.dormant_180d) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Declining customers in 6 months' AS metric,
	SUM(cam.declining_6m) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Customers having at least one active account' AS metric,
	SUM(
		CASE
			WHEN cam.customer_status = 'active' THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Customers without active but with at least one dormant account' AS metric,
	SUM(
		CASE
			WHEN cam.customer_status = 'dormant' THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
UNION ALL
SELECT
	'Customers having only closed accounts' AS metric,
	SUM(
		CASE
			WHEN cam.customer_status = 'closed' THEN 1
		END
	) AS total_count
FROM customers_attributes_matrix AS cam
;

-- Pivot table for quartiles
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @data_start_date
                THEN @data_start_date
            WHEN DAY(a.open_date) <= 15
                THEN DATEFROMPARTS(YEAR(a.open_date), MONTH(a.open_date), 1)
            ELSE DATEADD(
                MONTH,
                1,
                DATEFROMPARTS(YEAR(a.open_date), MONTH(a.open_date), 1)
            )
        END AS adjusted_account_open_date
    FROM customers AS c
    INNER JOIN accounts AS a
        ON c.customer_id = a.customer_id
    WHERE a.status IN ('active', 'dormant')
        AND a.open_date < DATEADD(
				MONTH,
				-2,
				DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end),
					1
				)
			)
),
customer_observation_period AS (
    SELECT
        customer_id,
        MIN(adjusted_account_open_date) AS observation_start_date
    FROM eligible_accounts
    GROUP BY customer_id
),
customer_transaction_metrics AS (
    SELECT
        cop.customer_id,
        SUM(ABS(t.amount)) AS gross_transaction_volume
    FROM customer_observation_period AS cop
    INNER JOIN eligible_accounts AS ea
        ON cop.customer_id = ea.customer_id
    INNER JOIN transactions AS t
        ON ea.account_id = t.account_id
    WHERE t.date >= cop.observation_start_date
        AND t.date < DATEADD(DAY, 1, @period_end)
    GROUP BY cop.customer_id
),
customer_value_base AS (
	SELECT
		cop.customer_id,
		cop.observation_start_date,
		DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1
			AS observation_months,
		ctm.gross_transaction_volume,
		ROUND(
			CAST(ctm.gross_transaction_volume AS DECIMAL(18, 2))
			/ (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
			2
		) AS avg_monthly_gross_transaction_volume
	FROM customer_observation_period AS cop
	INNER JOIN customer_transaction_metrics AS ctm
		ON cop.customer_id = ctm.customer_id
),
customers_quartiles AS (
	SELECT
		cvb.customer_id,
		cvb.gross_transaction_volume,
		cvb.avg_monthly_gross_transaction_volume,
		NTILE(4) OVER (
			ORDER BY cvb.avg_monthly_gross_transaction_volume
		) AS customer_value_quartile
	FROM customer_value_base AS cvb
),
active_customers_in_30_days AS (
	SELECT
		c.customer_id,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY c.customer_id
	HAVING MAX(t.date) >= DATEADD(day, - @period_duration, @period_end)
),
dormant_customers_180_days AS (
	SELECT
		c.customer_id,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_dormancy_length
		AND a.status IN ('active', 'dormant')
	GROUP BY c.customer_id
	HAVING MAX(t.date) < DATEADD(day,-@period_dormancy_length,@period_end)
		OR MAX(t.date) IS NULL
),
calendar AS (
	SELECT CAST('2025-07-01' AS DATE) AS month_start
		UNION ALL SELECT '2025-08-01'
		UNION ALL SELECT '2025-09-01'
		UNION ALL SELECT '2025-10-01'
		UNION ALL SELECT '2025-11-01'
		UNION ALL SELECT '2025-12-01'
),
customers_ids AS (
	SELECT DISTINCT
		c.customer_id
	FROM customers AS C
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	WHERE a.status IN ('active', 'dormant')
		AND a.open_date < DATEADD(
				MONTH,
				-2,
				DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end),
					1
				)
			)
),
customers_calendar_base AS (
	SELECT *
	FROM customers_ids AS ci
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
		AND t.date BETWEEN DATEADD(
				MONTH,
				-5,
				DATEFROMPARTS(
					YEAR(@period_end),
					MONTH(@period_end),
					1
				)
			) AND @period_end
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
				WHEN cma.month_start < DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
					)
				THEN cma.count_transactions
			END
		) AS avg_first_3m,
		AVG(
			CASE
				WHEN cma.month_start >= DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
					)
				THEN cma.count_transactions
			END
		) AS avg_last_3m
	FROM customers_monthly_activity AS cma
	GROUP BY cma.customer_id
	HAVING AVG(
			CASE
				WHEN cma.month_start < DATEADD(
						MONTH,
						-2,
						DATEFROMPARTS(
							YEAR(@period_end),
							MONTH(@period_end),
							1
						)
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
customer_status_prep AS (
	SELECT
		c.customer_id,
		MAX(
            CASE
                WHEN a.status = 'active'
                THEN 1
                ELSE 0
            END
        ) AS has_active_account,
		MAX(
            CASE
                WHEN a.status = 'dormant'
                THEN 1
                ELSE 0
            END
        ) AS has_dormant_account,
		MAX(
            CASE
                WHEN a.status = 'closed'
                THEN 1
                ELSE 0
            END
        ) AS has_closed_account
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	GROUP BY c.customer_id
),
customers_status AS (
	SELECT
		csp.customer_id,
		CASE
			WHEN csp.has_active_account = 1
				THEN 'active'
			WHEN csp.has_dormant_account = 1
				THEN 'dormant'
			ELSE 'closed'
		END AS customer_status
	FROM customer_status_prep AS csp
),
customers_attributes_matrix AS (
	SELECT
		cs.customer_id,
		cq.customer_value_quartile AS value_quartile,
		CASE
			WHEN ac30d.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS active_30d,
		CASE
			WHEN dc180d.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS dormant_180d,
		CASE
			WHEN dc.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS declining_6m,
		cs.customer_status
	FROM customers_status AS cs
	LEFT JOIN customers_quartiles AS cq ON cs.customer_id=cq.customer_id
	LEFT JOIN active_customers_in_30_days AS ac30d ON cs.customer_id = ac30d.customer_id
	LEFT JOIN dormant_customers_180_days AS dc180d ON cs.customer_id = dc180d.customer_id
	LEFT JOIN declining_customers AS dc ON cs.customer_id=dc.customer_id
)
SELECT
	CASE
		WHEN GROUPING(cam.value_quartile) = 1 THEN 'Total'
		ELSE CAST(cam.value_quartile AS VARCHAR(10))
	END AS quartil,
	SUM(
		CASE
			WHEN cam.active_30d = 1 THEN 1
		END
	) AS active,
	SUM(
		CASE
			WHEN cam.active_30d = 0 THEN 1
		END
	) AS non_active,
	SUM(
		CASE
			WHEN cam.declining_6m = 1 THEN 1
		END
	) AS declining,
	SUM(
		CASE
			WHEN cam.declining_6m = 0 THEN 1
		END
	) AS non_declining,
	SUM(
		CASE
			WHEN cam.dormant_180d = 1 THEN 1
		END
	) AS dormant,
	SUM(
		CASE
			WHEN cam.dormant_180d = 0 THEN 1
		END
	) AS non_dormant
FROM customers_attributes_matrix AS cam
GROUP BY ROLLUP(cam.value_quartile)
ORDER BY quartil DESC
;


-- Audit of segments overlapping
WITH dormant_customers_180_days AS (
	SELECT
		c.customer_id,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_dormancy_length
		AND a.status IN ('active', 'dormant')
	GROUP BY c.customer_id
	HAVING MAX(t.date) < DATEADD(day,-@period_dormancy_length,@period_end)
		OR MAX(t.date) IS NULL
),
base AS (
	SELECT 
		c.customer_id,
		COUNT(t.transaction_id) AS tx_freq,
		SUM(ABS(t.amount)) AS tx_volume
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE a.open_date < DATEADD(month, -6, @period_end) AND a.status IN ('active', 'dormant')
	GROUP BY c.customer_id
	HAVING COUNT(t.transaction_id) > 0
),
low_value_activity_customers AS (
	SELECT TOP 10 PERCENT 
		b.customer_id,
		RANK() OVER(ORDER BY b.tx_freq DESC) AS freq_rank,
		RANK() OVER(ORDER BY b.tx_volume DESC) AS volume_rank,
		RANK() OVER(ORDER BY b.tx_freq DESC) + RANK() OVER(ORDER BY b.tx_volume DESC) AS total_rank
	FROM base AS b
	ORDER BY
		total_rank DESC,
		b.customer_id
),
stats AS (
    SELECT 
        c.customer_id,
        MIN(a.open_date) AS first_open_date,
        COUNT(t.transaction_id) AS number_of_transactions,
        SUM(ABS(t.amount)) AS transactions_volume,
        MAX(DATEDIFF(MONTH, a.open_date, @period_end)) + 1 AS months_of_activity,
        CAST(COUNT(t.transaction_id) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, @period_end)) + 1 AS decimal(18,4)) AS transactions_monthly_raw,
        CAST(SUM(ABS(t.amount)) AS decimal(18,4)) /
        CAST(MAX(DATEDIFF(MONTH, a.open_date, @period_end)) + 1 AS decimal(18,4)) AS volume_monthly_raw
    FROM customers AS c
    INNER JOIN accounts AS a ON c.customer_id = a.customer_id
    LEFT JOIN transactions AS t ON a.account_id = t.account_id
    WHERE a.status IN ('active', 'dormant')
    GROUP BY c.customer_id
),
percentiles AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p75,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p75
    FROM stats
),
active_mass_customers AS (
	SELECT 
		s.customer_id,
		CAST(ROUND(s.transactions_monthly_raw,2) AS decimal(18,2)) AS transactions_monthly,
		CAST(ROUND(s.volume_monthly_raw,2) AS decimal(18,2)) AS volume_monthly
	FROM stats AS s
	CROSS JOIN percentiles AS p
	WHERE (s.transactions_monthly_raw BETWEEN p.t_p25 AND p.t_p75)
		AND (s.volume_monthly_raw BETWEEN p.v_p25 AND p.v_p75)
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
percentiles_low_declining_activity AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transactions_monthly_raw) OVER () AS t_p25,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY volume_monthly_raw) OVER () AS v_p75
    FROM stats
),
high_value_low_activity_customers AS (
	SELECT
		stats.customer_id
	FROM stats
	LEFT JOIN declining_customers AS dc ON stats.customer_id=dc.customer_id
	CROSS JOIN percentiles AS p
	WHERE 
		stats.volume_monthly_raw >= p.v_p75
		AND (
			stats.transactions_monthly_raw <= p.t_p25
			OR dc.customer_id IS NOT NULL
		)
),
high_value_activity_customers AS (
	SELECT TOP 10 PERCENT *,
		RANK() OVER(ORDER BY tx_freq DESC) AS freq_rank,
		RANK() OVER(ORDER BY tx_volume DESC) AS volume_rank,
		RANK() OVER(ORDER BY tx_freq DESC) + RANK() OVER(ORDER BY tx_volume DESC) AS total_rank
	FROM base
	ORDER BY 
		total_rank,
		customer_id
),
customers_segments_matrix AS (
	SELECT
		c.customer_id,
		CASE
			WHEN hvac.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS high_value_activity,
		CASE
			WHEN hvlac.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS high_value_low_activity,
		CASE
			WHEN amc.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS active_mass,
		CASE
			WHEN lvac.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS low_value_activity,
		CASE
			WHEN dc.customer_id IS NOT NULL
			THEN 1
			ELSE 0
		END AS dormant
	FROM customers AS c
	LEFT JOIN high_value_activity_customers AS hvac ON c.customer_id=hvac.customer_id
	LEFT JOIN high_value_low_activity_customers AS hvlac ON c.customer_id=hvlac.customer_id
	LEFT JOIN active_mass_customers AS amc ON c.customer_id=amc.customer_id
	LEFT JOIN low_value_activity_customers AS lvac ON c.customer_id=lvac.customer_id
	LEFT JOIN dormant_customers_180_days AS dc ON c.customer_id=dc.customer_id
),
customers_segments_matrix_summarized AS (
	SELECT
		csm.*,
		(csm.high_value_activity
		+ csm.high_value_low_activity
		+ csm.active_mass
		+ csm.low_value_activity
		+ csm.dormant
		) AS segment_membership_count
	FROM customers_segments_matrix AS csm
),
summary_report AS (
	SELECT
		1 AS sort_order,
		'Total customers count' AS metric,
		COUNT(csm.customer_id) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		2 AS sort_order,
		'Customers with high value and high activity' AS metric,
		SUM(csm.high_value_activity) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		3 AS sort_order,
		'Customers with high value but low or declining activity' AS metric,
		SUM(csm.high_value_low_activity) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		4 AS sort_order,
		'Active mass customers' AS metric,
		SUM(csm.active_mass) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		5 AS sort_order,
		'Customers with low value and activity' AS metric,
		SUM(csm.low_value_activity) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		6 AS sort_order,
		'Dormant customers in 180 days' AS metric,
		SUM(csm.dormant) AS total_count
	FROM customers_segments_matrix AS csm
	UNION ALL
	SELECT
		7 AS sort_order,
		'Customers in one segment' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 1
	UNION ALL
	SELECT
		8 AS sort_order,
		'Customers in two segments' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 2
	UNION ALL
	SELECT
		9 AS sort_order,
		'Customers in three segments' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 3
	UNION ALL
	SELECT
		10 AS sort_order,
		'Customers in four segments' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 4
	UNION ALL
	SELECT
		11 AS sort_order,
		'Customers in five segments' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 5
	UNION ALL
	SELECT
		12 AS sort_order,
		'Non-classified customers' AS metric,
		COUNT(*) AS total_count
	FROM customers_segments_matrix_summarized AS csms
	WHERE csms.segment_membership_count = 0
)
SELECT
	sr.metric,
	sr.total_count
FROM summary_report AS sr
ORDER BY sr.sort_order
;
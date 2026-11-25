-- 9.2 Customer value quartiles / percentiles
DECLARE @data_start_date DATE = '2022-01-01';
DECLARE @period_end DATE = '2025-12-31';

WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
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
        AND a.open_date < DATEFROMPARTS(
			YEAR(@period_end),
			MONTH(@period_end) - 2,
			1
		)
),
customer_observation_period AS (
    SELECT
        customer_id,
        name,
        MIN(adjusted_account_open_date) AS observation_start_date
    FROM eligible_accounts
    GROUP BY customer_id, name
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
		cop.name,
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
)
SELECT
	cvb.customer_id,
	cvb.name,
	cvb.gross_transaction_volume,
	cvb.avg_monthly_gross_transaction_volume,
	NTILE(4) OVER (
		ORDER BY cvb.avg_monthly_gross_transaction_volume
	) AS customer_value_quartile
FROM customer_value_base AS cvb
;  

-- Customer value quartile summary
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
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
        AND a.open_date < DATEFROMPARTS(
			YEAR(@period_end),
			MONTH(@period_end) - 2,
			1
		)
),
customer_observation_period AS (
    SELECT
        customer_id,
        name,
        MIN(adjusted_account_open_date) AS observation_start_date
    FROM eligible_accounts
    GROUP BY customer_id, name
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
		cop.name,
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
customer_quartile_assignment AS (
	SELECT
		cvb.customer_id,
		cvb.name,
		cvb.gross_transaction_volume,
		cvb.avg_monthly_gross_transaction_volume,
		NTILE(4) OVER (
			ORDER BY cvb.avg_monthly_gross_transaction_volume
		) AS customer_value_quartile
	FROM customer_value_base AS cvb
)
SELECT
	cqa.customer_value_quartile,
	COUNT(cqa.customer_id) AS customer_count,
	AVG(cqa.avg_monthly_gross_transaction_volume) AS avg_customer_value,
	MIN(cqa.avg_monthly_gross_transaction_volume) AS min_customer_value,
	MAX(cqa.avg_monthly_gross_transaction_volume) AS max_customer_value,
	SUM(cqa.gross_transaction_volume) AS total_gross_volume,
	SUM(cqa.gross_transaction_volume) / SUM(SUM(cqa.gross_transaction_volume)) OVER () * 100.0 AS share_of_total_volume
FROM customer_quartile_assignment AS cqa
GROUP BY cqa.customer_value_quartile
;  
-- 9.1 Customers with the highest average monthly transaction volume
-- Customers ranked by average monthly gross transaction volume, excluding closed accounts
DECLARE @data_start_date DATE = '2022-01-01';
DECLARE @period_start DATE = '2025-07-01';
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
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
)
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
ORDER BY avg_monthly_gross_transaction_volume DESC;
;

-- Customers with positive net cash flow
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
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
        SUM(t.amount) AS net_cash_flow
    FROM customer_observation_period AS cop
    INNER JOIN eligible_accounts AS ea
        ON cop.customer_id = ea.customer_id
    INNER JOIN transactions AS t
        ON ea.account_id = t.account_id
    WHERE t.date >= cop.observation_start_date
        AND t.date < DATEADD(DAY, 1, @period_end)
    GROUP BY cop.customer_id
	HAVING SUM(t.amount) > 0
)
SELECT
    cop.customer_id,
    cop.name,
    cop.observation_start_date,
    DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1
        AS observation_months,
    ctm.net_cash_flow,
    ROUND(
        CAST(ctm.net_cash_flow AS DECIMAL(18, 2))
        / (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
        2
    ) AS avg_monthly_net_cash_flow
FROM customer_observation_period AS cop
INNER JOIN customer_transaction_metrics AS ctm
    ON cop.customer_id = ctm.customer_id
ORDER BY avg_monthly_net_cash_flow DESC;
;

-- Customer transaction metrics for H2 2025, including accounts opened by September 30
-- Gross transaction volume
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @period_start
                THEN @period_start
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
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
)
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
ORDER BY avg_monthly_gross_transaction_volume DESC
;

-- Customers with positive net cash flow
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @period_start
                THEN @period_start
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
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
        SUM(t.amount) AS net_cash_flow
    FROM customer_observation_period AS cop
    INNER JOIN eligible_accounts AS ea
        ON cop.customer_id = ea.customer_id
    INNER JOIN transactions AS t
        ON ea.account_id = t.account_id
    WHERE t.date >= cop.observation_start_date
        AND t.date < DATEADD(DAY, 1, @period_end)
    GROUP BY cop.customer_id
	HAVING SUM(t.amount) > 0
)
SELECT
    cop.customer_id,
    cop.name,
    cop.observation_start_date,
    DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1
        AS observation_months,
    ctm.net_cash_flow,
    ROUND(
        CAST(ctm.net_cash_flow AS DECIMAL(18, 2))
        / (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
        2
    ) AS avg_monthly_net_cash_flow
FROM customer_observation_period AS cop
INNER JOIN customer_transaction_metrics AS ctm
    ON cop.customer_id = ctm.customer_id
ORDER BY avg_monthly_net_cash_flow DESC;
;

-- Customer transaction metrics – checking accounts only
-- Combining different account types may be misleading from a business perspective
-- Gross transaction volume
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @period_start
                THEN @period_start
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
		AND a.account_type IN ('checking')
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
)
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
ORDER BY avg_monthly_gross_transaction_volume DESC;
;

-- Customers with positive net cash flow
WITH eligible_accounts AS (
    SELECT
        c.customer_id,
        c.name,
        a.account_id,
        a.open_date,
        CASE
            WHEN a.open_date < @period_start
                THEN @period_start
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
	AND a.account_type IN ('checking')
        AND a.open_date < DATEADD(MONTH, 3, @period_start)
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
        SUM(t.amount) AS net_cash_flow
    FROM customer_observation_period AS cop
    INNER JOIN eligible_accounts AS ea
        ON cop.customer_id = ea.customer_id
    INNER JOIN transactions AS t
        ON ea.account_id = t.account_id
    WHERE t.date >= cop.observation_start_date
        AND t.date < DATEADD(DAY, 1, @period_end)
    GROUP BY cop.customer_id
	HAVING SUM(t.amount) > 0
)
SELECT
    cop.customer_id,
    cop.name,
    cop.observation_start_date,
    DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1
        AS observation_months,
    ctm.net_cash_flow,
    ROUND(
        CAST(ctm.net_cash_flow AS DECIMAL(18, 2))
        / (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
        2
    ) AS avg_monthly_net_cash_flow
FROM customer_observation_period AS cop
INNER JOIN customer_transaction_metrics AS ctm
    ON cop.customer_id = ctm.customer_id
ORDER BY avg_monthly_net_cash_flow DESC;
;
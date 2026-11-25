-- Customer Segment Comparison from the perspective of:
-- customer count,
-- transaction volume,
-- transaction frequency,
-- average transaction value,
-- activity trend

DECLARE @period_start DATE = '2025-01-01';
DECLARE @period_end DATE = '2025-12-31';

WITH eligible_accounts AS (
    SELECT
        c.customer_id,
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
        AND a.open_date < DATEADD(MONTH, -3, @period_end)
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
        SUM(ABS(t.amount)) AS customer_gross_transaction_volume,
		SUM(t.amount) AS customer_net_cash_flow,
		COUNT(t.transaction_id) AS customer_transaction_count,
		COUNT(
			CASE
				WHEN t.date >= @period_start AND t.date < DATEADD(month, 6, @period_start)
				THEN t.transaction_id
			END
		) AS h1_customer_transaction_count,
		COUNT(
			CASE
				WHEN t.date >= DATEADD(month, 6, @period_start) AND t.date <= @period_end
				THEN t.transaction_id
			END
		) AS h2_customer_transaction_count
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
		ctm.customer_transaction_count,
		ROUND(
			CAST(ctm.customer_transaction_count AS DECIMAL(18, 2))
			/ (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
			2
		) AS customer_avg_monthly_transaction_count,
		ctm.customer_gross_transaction_volume,
		ROUND(
			CAST(ctm.customer_gross_transaction_volume AS DECIMAL(18, 2))
			/ (DATEDIFF(MONTH, cop.observation_start_date, @period_end) + 1),
			2
		) AS customer_avg_monthly_gross_transaction_volume,
		ctm.customer_net_cash_flow,
		ctm.h1_customer_transaction_count,
		ctm.h2_customer_transaction_count
	FROM customer_observation_period AS cop
	INNER JOIN customer_transaction_metrics AS ctm
		ON cop.customer_id = ctm.customer_id
),
customer_quartile_categorization AS (
	SELECT
		cvb.customer_id,
		cvb.customer_transaction_count,
		cvb.customer_avg_monthly_transaction_count,
		cvb.customer_gross_transaction_volume,
		cvb.customer_avg_monthly_gross_transaction_volume,
		cvb.customer_net_cash_flow,
		cvb.h1_customer_transaction_count,
		cvb.h2_customer_transaction_count,
		NTILE(4) OVER (
			ORDER BY cvb.customer_avg_monthly_gross_transaction_volume
		) AS customer_value_quartile
	FROM customer_value_base AS cvb
),
quartile_comparison AS (
	SELECT
		cqc.customer_value_quartile,
		COUNT(DISTINCT cqc.customer_id) AS customer_count,
		SUM(cqc.customer_gross_transaction_volume) AS gross_transaction_volume,
		SUM(cqc.customer_net_cash_flow) AS net_cash_flow,
		SUM(cqc.customer_transaction_count) AS transaction_count,
		(
			1.0 
			* SUM(cqc.customer_transaction_count)
			/ (DATEDIFF(month, @period_start, @period_end)+1)
		) AS transaction_frequency_per_month,
		AVG(cqc.customer_avg_monthly_transaction_count) AS avg_transaction_count_per_month,
		(1.0* SUM(cqc.customer_gross_transaction_volume)/SUM(cqc.customer_transaction_count)) AS average_transaction_value,
		SUM(cqc.h1_customer_transaction_count) AS h1_activity,
		SUM(cqc.h2_customer_transaction_count) AS h2_activity
	FROM customer_quartile_categorization AS cqc
	GROUP BY cqc.customer_value_quartile
)
SELECT
	qc.*,
	100.0 *(qc.h2_activity-qc.h1_activity) / qc.h1_activity AS activity_change_pct
FROM quartile_comparison AS qc
ORDER BY qc.customer_value_quartile DESC
;  
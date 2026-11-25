--9.4 Active customers
-- Customers with a transaction during the last 30 days
DECLARE @period_end DATE = '2025-12-31';
DECLARE @period_duration INT = 30;


WITH customers_with_transaction AS (
	SELECT
		c.customer_id,
		a.account_id,
		a.status,
		MAX(t.date) AS last_transaction_date
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY c.customer_id, a.account_id, a.status
	HAVING MAX(t.date) >= DATEADD(day, - @period_duration, @period_end)
),
summary_counts AS (
	SELECT
		cwt.status,
		COUNT(DISTINCT cwt.customer_id) AS count_customers,
		COUNT(cwt.account_id) AS count_accounts
	FROM customers_with_transaction AS cwt
GROUP BY cwt.status WITH ROLLUP
)
SELECT
	sc.status,
	sc.count_customers,
	100.0 * sc.count_customers
		/ (
			SELECT sc.count_customers
			FROM summary_counts AS sc
			WHERE sc.status IS NULL
		) AS share_of_active_customers,
	sc.count_accounts,
	100.0 * sc.count_accounts
		/ (
			SELECT sc.count_accounts
			FROM summary_counts AS sc
			WHERE sc.status IS NULL
		) AS share_of_active_accounts
FROM summary_counts AS sc
;

--9.5 Activity trend
-- Monthly active customers and the activity trend
WITH monthly_active_customers_base AS (
	SELECT
		DATEFROMPARTS(
			YEAR(t.date),
			MONTH(t.date),
			1
		) AS month_start,
		COUNT(DISTINCT c.customer_id) AS active_customers
	FROM customers AS c
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	INNER JOIN transactions AS t ON a.account_id=t.account_id
	GROUP BY
		DATEFROMPARTS(
			YEAR(t.date),
			MONTH(t.date),
			1
		)
),
monthly_active_customers AS (
	SELECT
		macb.month_start,
		macb.active_customers,
		LAG(macb.active_customers) OVER(
			ORDER BY macb.month_start
		) AS previous_month,
		AVG(macb.active_customers) OVER(
			ORDER BY macb.month_start
			ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
		) AS rolling_avg_3m
	FROM monthly_active_customers_base AS macb
)
SELECT
    FORMAT(month_start, 'yyyy-MM') AS period_of_time,
    active_customers,
    previous_month,
    ROUND(
        100.0 * (active_customers - previous_month)
        / NULLIF(previous_month,0),
        2
    ) AS mom_change_pct,
    rolling_avg_3m
FROM monthly_active_customers
;
-- 9.7 Region performance
DECLARE @period_end DATE = '2025-12-31';
DECLARE @period_start DATE = DATEFROMPARTS(
        YEAR(@period_end),
        MONTH(@period_end) - 11,
        1
    );


WITH customer_status_prep AS (
	SELECT
		c.customer_id,
		r.region,
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
	INNER JOIN regions AS r ON c.region=r.region
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	GROUP BY c.customer_id,r.region
),
customers_status AS (
	SELECT
		csp.customer_id,
		csp.region,
		CASE
			WHEN csp.has_active_account = 1
				THEN 'active'
			WHEN csp.has_dormant_account = 1
				THEN 'dormant'
			ELSE 'closed'
		END AS customer_status
	FROM customer_status_prep AS csp
),
total_customers AS (
	SELECT
		COUNT(cs.customer_id) AS total_customers
	FROM customers_status AS cs
),
region_metrics AS (
	SELECT
		cs.region,
		COUNT(DISTINCT cs.customer_id) AS customer_count,
		(100.0 * COUNT(DISTINCT cs.customer_id)
			/ (
				SELECT total_customers
				FROM total_customers
			)
		) AS customer_share,
		COUNT(DISTINCT CASE
			WHEN cs.customer_status = 'active'
			THEN cs.customer_id
		END) AS active_customer_count,
		COUNT(DISTINCT CASE
			WHEN cs.customer_status = 'dormant'
			THEN cs.customer_id
		END) AS dormant_customer_count,
		COUNT(DISTINCT CASE
			WHEN cs.customer_status = 'closed'
			THEN cs.customer_id
		END) AS closed_customer_count,
		SUM(ABS(t.amount)) AS regional_transaction_volume,
		SUM(t.amount) AS regional_net_cash_flow,
		COUNT(t.transaction_id) AS regional_transaction_activity,
		(1.0 * COUNT(t.transaction_id)
		/
		COUNT(DISTINCT cs.customer_id)) AS avg_activity_per_customer
	FROM customers_status AS cs
	INNER JOIN accounts AS a ON cs.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
		AND t.date BETWEEN @period_start AND @period_end
	GROUP BY cs.region
)
SELECT
	rm.region,
	rm.customer_count,
	rm.customer_share,
	rm.active_customer_count,
	(100.0 * rm.active_customer_count / rm.customer_count) AS active_customer_share_in_region,
	rm.dormant_customer_count,
	(100.0 * rm.dormant_customer_count / rm.customer_count) AS dormant_customer_share_in_region,
	rm.closed_customer_count,
	(100.0 * rm.closed_customer_count / rm.customer_count) AS closed_customer_share_in_region,
	rm.regional_transaction_volume,
	(100.0 * rm.regional_transaction_volume
		/ (
			SELECT
				SUM(rm.regional_transaction_volume) AS total_transaction_volume
			FROM region_metrics AS rm
		)
	) AS share_transaction_volume,
	rm.regional_net_cash_flow,
	rm.regional_transaction_activity,
	(100.0 * rm.regional_transaction_activity
		/ (
			SELECT
				SUM(rm.regional_transaction_activity) AS total_transaction_activity
			FROM region_metrics AS rm
		)
	) AS share_transaction_activity,
	rm.avg_activity_per_customer,
	RANK() OVER(ORDER BY rm.customer_count DESC) AS rank_customer_count,
	RANK() OVER(ORDER BY rm.active_customer_count DESC) AS rank_active_customers,
	RANK() OVER(ORDER BY rm.regional_transaction_volume DESC) AS rank_transaction_volume,
	RANK() OVER(ORDER BY rm.regional_net_cash_flow DESC) AS rank_net_cash_flow,
	RANK() OVER(ORDER BY rm.regional_transaction_activity DESC) AS rank_activity,
	RANK() OVER(ORDER BY rm.avg_activity_per_customer DESC) AS rank_activity_per_customer
FROM region_metrics AS rm
;

--9.8 Normalized regional performance
--DECLARE @period_start DATE = '2025-01-01';
--DECLARE @period_end DATE = '2025-12-31';

WITH customer_status_prep AS (
	SELECT
		c.customer_id,
		r.region,
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
	INNER JOIN regions AS r ON c.region=r.region
	INNER JOIN accounts AS a ON c.customer_id=a.customer_id
	GROUP BY c.customer_id,r.region
),
customers_status AS (
	SELECT
		csp.customer_id,
		csp.region,
		CASE
			WHEN csp.has_active_account = 1
				THEN 'active'
			WHEN csp.has_dormant_account = 1
				THEN 'dormant'
			ELSE 'closed'
		END AS customer_status
	FROM customer_status_prep AS csp
),
region_metrics AS (
	SELECT
		cs.region,
		(r.population /1000) AS population_in_1000,
		r.branch_count,
		COUNT(DISTINCT cs.customer_id) AS customer_count,
		COUNT(DISTINCT CASE
			WHEN cs.customer_status = 'active'
			THEN cs.customer_id
		END) AS active_customer_count,
		SUM(ABS(t.amount)) AS regional_transaction_volume,
		SUM(t.amount) AS regional_net_cash_flow,
		COUNT(t.transaction_id) AS regional_transaction_activity
	FROM customers_status AS cs
	INNER JOIN regions AS r ON  cs.region=r.region
	INNER JOIN accounts AS a ON cs.customer_id=a.customer_id
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
		AND t.date BETWEEN @period_start AND @period_end
	GROUP BY
		cs.region, 
		r.population / 1000, 
		r.branch_count
),
normalized_region_metrics AS (
	SELECT
		rm.region,
		rm.population_in_1000,
		rm.branch_count,
		(1.0 * rm.customer_count / rm.population_in_1000) AS customers_count_1000_population,
		(1.0 * rm.customer_count / rm.branch_count) AS customers_count_per_branch,
		(1.0 * rm.active_customer_count / rm.population_in_1000) AS active_customers_count_1000_population,
		(1.0 * rm.active_customer_count / rm.branch_count) AS active_customers_count_per_branch,
		(1.0 * rm.regional_transaction_volume / rm.population_in_1000) AS transaction_volume_1000_population,
		(1.0 * rm.regional_transaction_volume / rm.branch_count) AS transaction_volume_per_branch,
		(1.0 * rm.regional_net_cash_flow / rm.population_in_1000) AS regional_net_cash_flow_1000_population,
		(1.0 * rm.regional_net_cash_flow / rm.branch_count) AS regional_net_cash_flow_per_branch,
		(1.0 * rm.regional_transaction_activity / rm.population_in_1000) AS transaction_activity_1000_population,
		(1.0 * rm.regional_transaction_activity / rm.branch_count) AS transaction_activity_per_branch
	FROM region_metrics AS rm
)
SELECT
	nrm.*,
	RANK() OVER(ORDER BY nrm.customers_count_1000_population DESC) AS rank_customer_population,
	RANK() OVER(ORDER BY nrm.active_customers_count_1000_population DESC) AS rank_active_customer_population,
	RANK() OVER(ORDER BY nrm.transaction_volume_1000_population DESC) AS rank_volume_population,
	RANK() OVER(ORDER BY nrm.regional_net_cash_flow_1000_population DESC) AS rank_Net_Cash_Flow_population,
	RANK() OVER(ORDER BY nrm.transaction_activity_1000_population DESC) AS rank_activity_population,
	RANK() OVER(ORDER BY nrm.customers_count_per_branch DESC) AS rank_customer_branch,
	RANK() OVER(ORDER BY nrm.active_customers_count_per_branch DESC) AS rank_active_customer_branch,
	RANK() OVER(ORDER BY nrm.transaction_volume_per_branch DESC) AS rank_volume_branch,
	RANK() OVER(ORDER BY nrm.regional_net_cash_flow_per_branch DESC) AS rank_Net_Cash_Flow_branch,
	RANK() OVER(ORDER BY nrm.transaction_activity_per_branch DESC) AS rank_activity_branch
FROM normalized_region_metrics AS nrm
;


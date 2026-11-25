-- 9.3 Dormant accounts
-- System-defined dormant accounts
SELECT
	a.account_id
FROM accounts AS a
WHERE a.status = 'dormant'
;

-- Summary of dormant accounts by status
SELECT
	a.account_type,
	COUNT(a.account_id) AS dormant_accounts_count
FROM accounts AS a
WHERE a.status = 'dormant'
GROUP BY a.account_type WITH ROLLUP
;

-- Accounts without any transaction for at least 180 days
DECLARE @period_end DATE = '2025-12-31';
DECLARE @period_length INT = 180;

SELECT
	a.account_id,
	MAX(t.date) AS last_transaction_date
FROM accounts AS a
LEFT JOIN transactions AS t ON a.account_id=t.account_id
WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
	AND a.status IN ('active', 'dormant')
GROUP BY a.account_id
HAVING MAX(t.date) < DATEADD(day,-@period_length,@period_end)
	OR MAX(t.date) IS NULL
;

-- Account types without any transaction for at least 180 days
WITH accounts_without_transaction AS (
	SELECT
		a.account_id,
		MAX(t.date) AS last_transaction_date
	FROM accounts AS a
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
	GROUP BY a.account_id
	HAVING MAX(t.date) < DATEADD(day,-@period_length,@period_end)
		OR MAX(t.date) IS NULL
)
SELECT
	a.account_type,
	COUNT(a.account_id) AS dormant_accounts_count
FROM accounts AS a
INNER JOIN accounts_without_transaction AS awt
	ON a.account_id = awt.account_id
GROUP BY a.account_type
;

-- Accounts with status "dormant" but having a transaction in the last 180 days
WITH dormant_status_accounts AS (
	SELECT
		a.account_id
	FROM accounts AS a
	WHERE a.status = 'dormant'
),
nondormant_accounts AS(
	SELECT DISTINCT
		a.account_id
	FROM accounts AS a
	INNER JOIN transactions AS t
		ON a.account_id = t.account_id
	WHERE DATEDIFF(day, t.date, @period_end) <= 180
		AND a.status IN ('active', 'dormant')
)
SELECT
	dsa.account_id
FROM dormant_status_accounts AS dsa
LEFT OUTER JOIN nondormant_accounts AS na
	ON dsa.account_id = na.account_id
WHERE dsa.account_id=na.account_id
;

--Checking the consistency of the query
WITH dormant_status_accounts AS (
	SELECT
		a.account_id
	FROM accounts AS a
	WHERE a.status = 'dormant'
),
nondormant_accounts AS(
	SELECT DISTINCT
		a.account_id
	FROM accounts AS a
	INNER JOIN transactions AS t
		ON a.account_id = t.account_id
	WHERE DATEDIFF(day, t.date, @period_end) <= 180
		AND a.status IN ('active', 'dormant')
),
result AS (
	SELECT
		dsa.account_id
	FROM dormant_status_accounts AS dsa
	LEFT OUTER JOIN nondormant_accounts AS na
		ON dsa.account_id = na.account_id
	WHERE dsa.account_id=na.account_id
)
SELECT
    COUNT(*) AS rows_count,
    COUNT(DISTINCT account_id) AS distinct_accounts
FROM result
;

-- Confusion matrix for dormant accounts
WITH dormant_status_accounts AS (
	SELECT
		a.account_id
	FROM accounts AS a
	WHERE a.status = 'dormant'
),
analytical_dormant_accounts AS (
	SELECT
		a.account_id,
		MAX(t.date) AS last_transaction_date
	FROM accounts AS a
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
	GROUP BY a.account_id
	HAVING MAX(t.date) < DATEADD(day,-@period_length,@period_end)
		OR MAX(t.date) IS NULL
),
confusion_matrix_base AS (
	SELECT
		a.account_id,
		CASE
			WHEN dsa.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS system_dormant,
		CASE
			WHEN ada.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS analytical_dormant
	FROM accounts AS a
	LEFT JOIN dormant_status_accounts AS dsa 
		ON a.account_id=dsa.account_id
	LEFT JOIN analytical_dormant_accounts AS ada
		ON a.account_id=ada.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
)
SELECT
	cmb.system_dormant,
	cmb.analytical_dormant,
	COUNT(*) AS accounts_count
FROM confusion_matrix_base AS cmb
GROUP BY cmb.system_dormant, cmb.analytical_dormant
;

-- Activity breakdown of system-defined dormant accounts
WITH dormant_status_accounts AS (
	SELECT
		a.account_id
	FROM accounts AS a
	WHERE a.status = 'dormant'
),
analytical_dormant_accounts AS (
	SELECT
		a.account_id,
		MAX(t.date) AS last_transaction_date
	FROM accounts AS a
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
	GROUP BY a.account_id
	HAVING MAX(t.date) < DATEADD(day,-@period_length,@period_end)
		OR MAX(t.date) IS NULL
),
confusion_matrix_base AS (
	SELECT
		a.account_id,
		CASE
			WHEN dsa.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS system_dormant,
		CASE
			WHEN ada.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS analytical_dormant
	FROM accounts AS a
	LEFT JOIN dormant_status_accounts AS dsa 
		ON a.account_id=dsa.account_id
	LEFT JOIN analytical_dormant_accounts AS ada
		ON a.account_id=ada.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
),
confusion_matrix AS (
	SELECT
		cmb.system_dormant,
		cmb.analytical_dormant,
		COUNT(*) AS accounts_count
	FROM confusion_matrix_base AS cmb
	GROUP BY cmb.system_dormant, cmb.analytical_dormant
),
total_dormant_status_accounts AS (
	SELECT
		COUNT(*) AS count_dormant_status_accounts
	FROM dormant_status_accounts AS dsa
)
SELECT
    ROUND(
         100.0 * (
            SELECT SUM(accounts_count)
            FROM confusion_matrix
            WHERE system_dormant = 'YES'
				AND analytical_dormant = 'YES'
        )
		/
        (
            SELECT COUNT(*)
            FROM dormant_status_accounts
        ),
        2
    ) AS pct_dormant_without_recent_activity,
	ROUND(
        100.0 * SUM(
            CASE
                WHEN system_dormant = 'YES'
                    AND analytical_dormant = 'NO'
                THEN accounts_count
                ELSE 0
            END
        ) /
        (
            SELECT COUNT(*)
            FROM dormant_status_accounts
        ),
        2
    ) AS pct_dormant_with_recent_activity
FROM confusion_matrix
;


--Summary
WITH dormant_status_accounts AS (
	SELECT
		a.account_id
	FROM accounts AS a
	WHERE a.status = 'dormant'
),
analytical_dormant_accounts AS (
	SELECT
		a.account_id,
		MAX(t.date) AS last_transaction_date
	FROM accounts AS a
	LEFT JOIN transactions AS t ON a.account_id=t.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
	GROUP BY a.account_id
	HAVING MAX(t.date) < DATEADD(day,-@period_length,@period_end)
		OR MAX(t.date) IS NULL
),
confusion_matrix_base AS (
	SELECT
		a.account_id,
		CASE
			WHEN dsa.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS system_dormant,
		CASE
			WHEN ada.account_id IS NOT NULL THEN 'YES'
			ELSE 'NO'
		END AS analytical_dormant
	FROM accounts AS a
	LEFT JOIN dormant_status_accounts AS dsa 
		ON a.account_id=dsa.account_id
	LEFT JOIN analytical_dormant_accounts AS ada
		ON a.account_id=ada.account_id
	WHERE DATEDIFF(DAY,a.open_date, @period_end) >= @period_length
		AND a.status IN ('active', 'dormant')
),
confusion_matrix AS (
	SELECT
		cmb.system_dormant,
		cmb.analytical_dormant,
		COUNT(*) AS accounts_count
	FROM confusion_matrix_base AS cmb
	GROUP BY cmb.system_dormant, cmb.analytical_dormant
),
summary AS (
	SELECT
		'All accounts' AS metric,
		COUNT(*) AS value
	FROM accounts AS a
	UNION ALL
	SELECT
		'Eligible accounts' AS metric,
		COUNT(*) AS value
	FROM confusion_matrix_base AS cmb
	UNION ALL
	SELECT
		'System dormant accounts' AS metric,
		COUNT(*) AS value
	FROM dormant_status_accounts AS dsa
	UNION ALL
	SELECT
		'System dormant and eligible accounts' AS metric,
		SUM(accounts_count) AS value
	FROM confusion_matrix AS cm
	WHERE cm.system_dormant = 'YES'
	GROUP BY cm.system_dormant
	UNION ALL
	SELECT
		'Analytical dormant accounts' AS metric,
		COUNT(*) AS value
	FROM analytical_dormant_accounts AS ada
	UNION ALL
	SELECT
		'Dormant under both definitions' AS metric,
		accounts_count AS value
	FROM confusion_matrix AS cm
	WHERE cm.analytical_dormant = 'YES'
		AND cm.system_dormant = 'YES'
	UNION ALL
	SELECT
		'System dormant but analytically active' AS metric,
		accounts_count AS value
	FROM confusion_matrix AS cm
	WHERE cm.analytical_dormant = 'NO'
		AND cm.system_dormant = 'YES'
	UNION ALL
	SELECT
		'System active but analytically dormant' AS metric,
		accounts_count AS value
	FROM confusion_matrix AS cm
	WHERE cm.analytical_dormant = 'YES'
		AND cm.system_dormant = 'NO'
),
total_eligible_accounts AS (
    SELECT 
		value AS total_eligible_accounts
    FROM summary AS s
    WHERE s.metric = 'Eligible accounts'
),
total_accounts AS (
    SELECT 
		value AS total_accounts
    FROM summary AS s
    WHERE s.metric = 'All accounts'
)
SELECT
    s.metric,
    s.value,
	ROUND(
        100.0 * s.value / tea.total_eligible_accounts,
        2
    ) AS 'Share of Eligible Accounts',
    ROUND(
        100.0 * s.value / ta.total_accounts,
        2
    ) AS 'Share of All Accounts'
FROM summary AS s
CROSS JOIN total_eligible_accounts AS tea
CROSS JOIN total_accounts AS ta
ORDER BY value DESC
;
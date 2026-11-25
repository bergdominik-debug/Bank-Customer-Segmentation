SELECT * FROM transactions
WHERE TRY_CONVERT(float, amount) IS NULL
AND amount IS NOT NULL;

UPDATE transactions
SET amount = LTRIM(RTRIM(amount));

ALTER TABLE transactions
ALTER COLUMN amount float;

SELECT MAX(amount) FROM transactions;
-- VELOCITY CHECK FUNCTION 
CREATE OR REPLACE FUNCTION check_velocity (
	p_customer_key INTEGER,
	p_transaction_datetime TIMESTAMP,
	p_transaction_key INTEGER,
	p_account_key INTEGER
)

RETURNS TABLE(
	velocity_score  INTEGER,
	velocity_flag 	BOOLEAN
)
AS $$
DECLARE
	v_count_10min		INTEGER;
	v_count_today		INTEGER;
	v_velocity_score  	INTEGER := 0;
	v_velocity_flag		BOOLEAN := FALSE;
	v_account_type		VARCHAR(20);
	v_daily_threshold   INTEGER := 15;

BEGIN
-- Count transactions in the last 10 minutes
	SELECT COUNT(*)
	INTO v_count_10min
	FROM fact_transactions
	WHERE 
		customer_key = p_customer_key
		AND transaction_datetime BETWEEN p_transaction_datetime - INTERVAL '10 minutes' AND p_transaction_datetime
		AND transaction_key != p_transaction_key;


-- Get account type
	SELECT account_type
	INTO   v_account_type
	FROM   dim_accounts
	WHERE  account_key = p_account_key;


-- Set daily threshold based on account type
	IF v_account_type = 'Business' THEN
		v_daily_threshold := 40;
	ELSEIF v_account_type = 'Current' THEN
		v_daily_threshold := 25;
	ELSEIF v_account_type = 'Savings' THEN
		v_daily_threshold := 15;
	ELSE -- Wallet
		v_daily_threshold := 10;
	END IF;


-- Count transactions today
	SELECT COUNT(*)
	INTO v_count_today
	FROM fact_transactions
	WHERE
		customer_key = p_customer_key
		AND DATE(transaction_datetime) = DATE(p_transaction_datetime)
		AND transaction_key != p_transaction_key;


-- Score based on the 10 minute count
	IF 	v_count_10min >= 5 THEN
		v_velocity_score := 100;
		v_velocity_flag  := TRUE;
		
	ELSEIF v_count_10min >= 3 THEN
	
		v_velocity_score := 60;
		v_velocity_flag  := TRUE;
	END IF;

-- Add daily count score
	IF  v_count_today > v_daily_threshold THEN
		v_velocity_score := LEAST(100, v_velocity_score + 20);
	END IF;

	RETURN QUERY 
		SELECT v_velocity_score, v_velocity_flag;
END;
$$ LANGUAGE plpgsql;

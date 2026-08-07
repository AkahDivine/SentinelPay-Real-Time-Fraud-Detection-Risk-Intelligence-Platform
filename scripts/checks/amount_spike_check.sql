-- AMOUNT SPIKE FUNCTION
CREATE OR REPLACE FUNCTION check_amount_spike (
	p_customer_key			INTEGER,
	p_amount				NUMERIC(18,2),
	p_transaction_key		INTEGER,
	p_transaction_datetime 	TIMESTAMP,
	P_account_key			INTEGER
)

RETURNS TABLE (
	amount_score INTEGER,
	amount_flag  BOOLEAN
)

AS $$
DECLARE 
	v_count_90days 	INTEGER;
	v_avg_amount 	NUMERIC(18,2);
	v_stddev_amount NUMERIC(18,2);
	v_spike_score 	INTEGER := 0;
	v_spike_flag 	BOOLEAN:= FALSE;
	v_z_score   	NUMERIC(18,2);
	v_account_type	VARCHAR(20);
	v_platform_avg  NUMERIC(18,2);

BEGIN
-- Get transactions history from the last 90 days and calculate average and standard deviation 
	SELECT 
		COUNT(*),
		COALESCE(AVG(amount), 0),
		COALESCE(STDDEV(amount), 0)
	INTO 
		v_count_90days,
		v_avg_amount,
		v_stddev_amount
	FROM fact_transactions
	WHERE
		customer_key = p_customer_key
		AND transaction_datetime >= p_transaction_datetime - INTERVAL '90 days'
		AND transaction_datetime < p_transaction_datetime
		AND transaction_status = 'Completed'
		AND transaction_key != p_transaction_key;


-- Get account type
	SELECT account_type
	INTO v_account_type
	FROM dim_accounts
	WHERE account_key = p_account_key;


-- Route 1: Enough history - use Z-score method
	IF v_count_90days >= 10 THEN
		v_z_score := (p_amount - v_avg_amount) / NULLIF(v_stddev_amount, 0);
	
		IF v_z_score > 2.5 THEN
			v_spike_flag := TRUE;
			
			IF v_z_score > 5.0 THEN
				v_spike_score := 100;
				
			ELSEIF v_z_score > 3.5  THEN
				v_spike_score := 70;
				
			ELSE 
				v_spike_score := 40;
				
			END IF ;
			
		END IF;

-- Route 2: Not enough history - Use ratio against platform average
-- Baseline average transaction amounts used for customers
-- with insufficient transaction history (<10 transactions in 90 days).
	ELSE

		IF v_account_type = 'Business' THEN
			v_platform_avg := 300000;
			
		ELSEIF v_account_type = 'Current' THEN
			v_platform_avg := 170000;
			
		ELSEIF v_account_type = 'Savings' THEN
			v_platform_avg := 80000;
			
		ELSEIF v_account_type = 'Wallet' THEN
			v_platform_avg := 20000;

		END IF;

		IF p_amount > (4 * v_platform_avg) THEN
			v_spike_score := 80;
			v_spike_flag := TRUE;

		ELSEIF p_amount > (2 * v_platform_avg) THEN
			v_spike_score :=50;
			v_spike_flag  :=TRUE;
			
		END IF;

	END IF;

	RETURN QUERY 
		SELECT v_spike_score, v_spike_flag;
END;
$$ LANGUAGE plpgsql;

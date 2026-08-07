-- HARD RULES FUNCTION
CREATE OR REPLACE FUNCTION check_hard_rules (
	p_customer_key			INTEGER,
	p_transaction_datetime	TIMESTAMP,
	p_amount				NUMERIC(18,2),
	p_transaction_key		INTEGER,
	p_account_key			INTEGER,
	p_transaction_direction	VARCHAR(20)
	
)

RETURNS TABLE(
	hard_rule_score		INTEGER,
	hard_rule_flag		BOOLEAN,
	hard_rule_triggered VARCHAR(50)
)

AS $$
DECLARE
	v_hard_rule_score		INTEGER := 0;
	v_hard_rule_flag		BOOLEAN :=FALSE;
	v_hard_rule_triggered	VARCHAR(50);
	v_account_status		VARCHAR(20);
	v_daily_limit			NUMERIC(18,2);
	v_total_spend_today		NUMERIC(18,2);

BEGIN
-- Get account status
	SELECT
		account_status,
		daily_limit
	INTO
		v_account_status,
		v_daily_limit
	FROM dim_accounts
	WHERE account_key = p_account_key;

-- Get today's total spend
	SELECT COALESCE(SUM(amount), 0)
	INTO v_total_spend_today
	FROM fact_transactions
	WHERE
		customer_key = p_customer_key
		AND DATE(transaction_datetime) = DATE(p_transaction_datetime)
		AND transaction_status = 'Completed'
		AND transaction_direction = 'OUTFLOW'
		AND transaction_key != p_transaction_key;



-- Hard rules
	IF v_account_status = 'Closed' THEN
		v_hard_rule_score 	  := 100;
		v_hard_rule_flag  	  := TRUE;
		v_hard_rule_triggered := 'Closed Account Transaction';

	ELSEIF v_account_status = 'Suspended' THEN
		v_hard_rule_score 	  := 95;
		v_hard_rule_flag  	  := TRUE;
		v_hard_rule_triggered := 'Suspended Account Transaction';

	ELSEIF v_account_status = 'Dormant' THEN
		v_hard_rule_score  	  := v_hard_rule_score + 20;
		v_hard_rule_flag  	  := TRUE;
		v_hard_rule_triggered := 'Dormant Account Reactivation';

	ELSEIF v_account_status = 'Restricted' THEN
		v_hard_rule_score 	  := v_hard_rule_score + 25;
		v_hard_rule_flag  	  := TRUE;
		v_hard_rule_triggered := 'Restricted Account Transaction';

	END IF;

 -- DAILY LIMIT CHECK — only for OUTFLOW transactions
	IF p_transaction_direction = 'OUTFLOW' THEN
		
		IF v_total_spend_today + p_amount > v_daily_limit THEN
			v_hard_rule_score 	  := LEAST(100, v_hard_rule_score + 30);
			v_hard_rule_flag  	  := TRUE;
			v_hard_rule_triggered := COALESCE(v_hard_rule_triggered, 'Daily Limit Exceeded');
		
		END IF;
		
	END IF;


	RETURN QUERY 
		SELECT v_hard_rule_score, v_hard_rule_flag, v_hard_rule_triggered;
		
END;
$$ LANGUAGE plpgsql;

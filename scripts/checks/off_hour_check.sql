-- OFF HOUR FUNCTION
CREATE OR REPLACE FUNCTION check_off_hour (
	p_customer_key			INTEGER,
	p_transaction_datetime	TIMESTAMP,
	p_transaction_key		INTEGER
)

RETURNS TABLE(
	off_hour_score	INTEGER,
	off_hour_flag	BOOLEAN
)

AS $$
DECLARE
	v_off_hour_score		INTEGER := 0;
	v_off_hour_flag			BOOLEAN := FALSE;
	v_transaction_hour  	NUMERIC;
	v_off_hour_pct_30days 	NUMERIC;
	

BEGIN

-- Extract hour from transaction datetime
	v_transaction_hour := EXTRACT(HOUR FROM p_transaction_datetime);
	
-- Extracting transaction hour from transaction_datetime
	SELECT 
		COUNT(*) FILTER (
        WHERE EXTRACT(HOUR FROM transaction_datetime) >= 23
           OR EXTRACT(HOUR FROM transaction_datetime) < 6
    	) * 100.0 / NULLIF(COUNT(*), 0) AS off_hour_pct
	INTO v_off_hour_pct_30days
	FROM fact_transactions
	WHERE 
		customer_key = p_customer_key
		AND transaction_datetime >= p_transaction_datetime - INTERVAL '30 days'
		AND transaction_key != p_transaction_key
		AND transaction_datetime < p_transaction_datetime;



-- Scoring logic
	IF v_transaction_hour >= 23 OR v_transaction_hour < 6 THEN

		IF COALESCE(v_off_hour_pct_30days, 0) > 20 THEN
			v_off_hour_score := 25;
			v_off_hour_flag  := FALSE;

		ELSE
			v_off_hour_score := 50;
			v_off_hour_flag  := TRUE;

		END IF;

	ELSE
        v_off_hour_score := 0;
        v_off_hour_flag  := FALSE;
		
    END IF;


	RETURN QUERY 
		SELECT v_off_hour_score, v_off_hour_flag;
		
END;
$$ LANGUAGE plpgsql;

-- LOCATION FUNCTION
CREATE OR REPLACE FUNCTION check_location(
	p_customer_key			INTEGER,
	p_location_key			INTEGER,
	p_transaction_datetime	TIMESTAMP,
	p_transaction_key		INTEGER
)

RETURNS TABLE(
	location_score  INTEGER,
	location_flag	BOOLEAN
)

AS $$
DECLARE 
	v_location_score     INTEGER := 0;
	v_location_flag      BOOLEAN := FALSE;
	v_home_location_key  INTEGER;
	v_risk_level  		 VARCHAR(15);
	v_in_recent_states	 BOOLEAN := FALSE;


BEGIN
-- Get customer home location
	SELECT location_key
	INTO v_home_location_key
	FROM dim_customers
	WHERE customer_key = p_customer_key;
	

-- Get state risk level of current transaction location
	SELECT risk_level
	INTO v_risk_level
	FROM dim_location
	WHERE location_key = p_location_key;

-- Check if customer has transacted from this location in last 30 days
    SELECT EXISTS (
        SELECT 1
        FROM fact_transactions
        WHERE customer_key = p_customer_key
        	AND location_key = p_location_key
        	AND transaction_datetime >= p_transaction_datetime - INTERVAL '30 days'
        	AND transaction_datetime  < p_transaction_datetime
			AND transaction_key != p_transaction_key
    ) 
	INTO v_in_recent_states;


-- Location scoring logic
	IF p_location_key = v_home_location_key THEN
		v_location_score := 0;
		v_location_flag := FALSE;

	ELSEIF v_in_recent_states THEN
		v_location_score := 20;
		v_location_flag  := FALSE;

	ELSE 
		v_location_score := 50;
		v_location_flag   := TRUE;

	END IF;

-- State risk bonus (applied on top location score)
	IF v_risk_level = 'Critical' THEN
        v_location_score := LEAST(100, v_location_score + 10);
		
    ELSEIF v_risk_level = 'High' THEN
        v_location_score := LEAST(100, v_location_score + 15);
		
    ELSEIF v_risk_level = 'Medium' THEN
        v_location_score := LEAST(100, v_location_score + 5);
	
    END IF;

	RETURN QUERY 
		SELECT v_location_score, v_location_flag;
		
END;
$$ LANGUAGE plpgsql;

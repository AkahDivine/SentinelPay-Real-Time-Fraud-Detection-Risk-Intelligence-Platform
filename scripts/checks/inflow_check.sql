-- INFLOW CHECK
CREATE OR REPLACE FUNCTION check_inflow(
	p_customer_key 			  INTEGER, 
	p_amount 				  NUMERIC, 
	p_transaction_datetime    TIMESTAMP, 
	p_transaction_key 		  INTEGER, 
	p_transaction_direction   VARCHAR(20), 
	p_counterparty_type 	  VARCHAR(20), 
	p_counterparty_risk_score INTEGER
)
	
RETURNS TABLE(
	inflow_score INTEGER, 
	inflow_flag  BOOLEAN
)

AS $$
DECLARE
    v_inflow_score INTEGER := 0;
    v_average_inflow NUMERIC(18,2) := 0;
    v_recent_risky_inflows INTEGER := 0;
    v_recent_inflow_total NUMERIC(18,2) := 0;
BEGIN
    -- Money-mule behaviour is an outflow shortly after incoming funds.
    IF p_transaction_direction IS DISTINCT FROM 'OUTFLOW' THEN
        RETURN QUERY SELECT 0, FALSE;
        RETURN;
    END IF;

    -- Use only successful inflows from the customer's recent history.
    SELECT COALESCE(AVG(ft.amount), 0)
    INTO v_average_inflow
    FROM fact_transactions AS ft
    WHERE ft.customer_key = p_customer_key
      AND ft.transaction_direction = 'INFLOW'
      AND ft.transaction_status = 'Success'
      AND ft.transaction_datetime >=
          p_transaction_datetime - INTERVAL '90 days'
      AND ft.transaction_datetime < p_transaction_datetime
      AND ft.transaction_key <> p_transaction_key;

    -- Find risky funds received during the hour before this outflow.
    SELECT COUNT(*), COALESCE(SUM(ft.amount), 0)
    INTO v_recent_risky_inflows, v_recent_inflow_total
    FROM fact_transactions AS ft
    WHERE ft.customer_key = p_customer_key
      AND ft.transaction_direction = 'INFLOW'
      AND ft.transaction_status = 'Success'
      AND ft.counterparty_type IN (
          'External', 'Employer', 'Merchant', 'Customer'
      )
      AND COALESCE(ft.counterparty_risk_score, 0) >= 60
      AND ft.transaction_datetime >=
          p_transaction_datetime - INTERVAL '1 hour'
      AND ft.transaction_datetime < p_transaction_datetime
      AND ft.transaction_key <> p_transaction_key;

    IF v_recent_risky_inflows > 0 THEN
        v_inflow_score := v_inflow_score + 40;
    END IF;

    IF v_average_inflow > 0
       AND p_amount > (4 * v_average_inflow) THEN
        v_inflow_score := v_inflow_score + 30;
    END IF;

    IF v_recent_inflow_total > 0
       AND p_amount >= (0.80 * v_recent_inflow_total) THEN
        v_inflow_score := v_inflow_score + 20;
    END IF;

    v_inflow_score := LEAST(100, v_inflow_score);

    RETURN QUERY
    SELECT v_inflow_score, (v_inflow_score >= 40);
END;
$$ LANGUAGE plpgsql;

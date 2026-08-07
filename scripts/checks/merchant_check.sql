-- Merchant check
CREATE OR REPLACE FUNCTION check_merchant(
	p_customer_key 			INTEGER, 
	p_merchant_key 			INTEGER, 
	p_transaction_datetime  TIMESTAMP, 
	p_transaction_key 		INTEGER
)
RETURNS TABLE(
	merchant_score INTEGER, 
	merchant_flag  BOOLEAN
)

AS $$
DECLARE
    v_merchant_score INTEGER := 0;
    v_merchant_flag BOOLEAN := FALSE;
    v_stored_score INTEGER;
    v_merchant_status VARCHAR(20);
    v_merchant_category VARCHAR(50);
    v_same_category_count INTEGER := 0;
BEGIN
    IF p_merchant_key IS NULL THEN
        RETURN QUERY SELECT 0, FALSE;
        RETURN;
    END IF;

    SELECT risk_score, status, merchant_category
    INTO v_stored_score, v_merchant_status, v_merchant_category
    FROM dim_merchants
    WHERE merchant_key = p_merchant_key;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 100, TRUE;
        RETURN;
    END IF;

    SELECT COUNT(*)
    INTO v_same_category_count
    FROM fact_transactions AS ft
    JOIN dim_merchants AS dm
      ON dm.merchant_key = ft.merchant_key
    WHERE ft.customer_key = p_customer_key
      AND ft.transaction_datetime < p_transaction_datetime
      AND ft.transaction_key <> p_transaction_key
      AND dm.merchant_category = v_merchant_category;

    v_merchant_score := COALESCE(v_stored_score, 0);

    IF v_merchant_status = 'Suspended' THEN
        v_merchant_score := GREATEST(v_merchant_score, 95);
    END IF;

    IF v_same_category_count = 0 AND v_merchant_score >= 60 THEN
        v_merchant_score := LEAST(100, v_merchant_score + 10);
    END IF;

    v_merchant_flag := (
        v_merchant_status = 'Suspended'
        OR v_merchant_score >= 30
    );

    RETURN QUERY
    SELECT LEAST(100, v_merchant_score), v_merchant_flag;
END;
$$ LANGUAGE plpgsql;

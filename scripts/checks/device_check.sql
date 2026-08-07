-- DEVICE FUNCTION
CREATE OR REPLACE FUNCTION check_device(
    p_customer_key INTEGER,
    p_device_key INTEGER,
    p_transaction_datetime TIMESTAMP,
    p_transaction_key INTEGER
)
RETURNS TABLE(device_score INTEGER, device_flag BOOLEAN)

AS $$
DECLARE
    v_device_exists BOOLEAN;
    v_device_assigned BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM dim_device
        WHERE device_key = p_device_key
    )
    INTO v_device_exists;

    SELECT EXISTS (
        SELECT 1
        FROM customer_devices
        WHERE customer_key = p_customer_key
          AND device_key = p_device_key
          AND COALESCE(status, 'Active') = 'Active'
    )
    INTO v_device_assigned;

    IF v_device_assigned THEN
        RETURN QUERY SELECT 0, FALSE;
    ELSIF v_device_exists THEN
        RETURN QUERY SELECT 90, TRUE;
    ELSE
        RETURN QUERY SELECT 100, TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;

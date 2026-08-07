/*
    PURPOSE
    -------
    Finds an existing device or creates it in dim_device, then returns the
    device_key required by process_transaction().

    MATCHING
    --------
    A device is considered existing when either device_id matches or a supplied
    device_fingerprint matches. This function does not assign the device to a
    customer; process_transaction() manages customer_devices after first use.

    DATE NOTE
    ---------
    first_seen uses CURRENT_TIMESTAMP because this routine is intended for live
    device registration.
*/
CREATE OR REPLACE FUNCTION register_live_device(
	p_device_id 		 VARCHAR(20), 
	p_device_type 		 VARCHAR(20), 
	p_operating_system   VARCHAR(50), 
	p_device_brand 		 VARCHAR(50), 
	p_device_fingerprint VARCHAR(255), 
	p_ip_address 		 VARCHAR(50),
	p_first_seen 		 TIMESTAMP
)

RETURNS integer

AS $$
DECLARE
    v_device_key INTEGER;
BEGIN
    -- Search by the provider's device ID or the more stable fingerprint.
    SELECT device_key
    INTO v_device_key
    FROM dim_device
    WHERE device_id = p_device_id
       OR (
            p_device_fingerprint IS NOT NULL
            AND device_fingerprint = p_device_fingerprint
       )
    LIMIT 1;

    -- A completely new device receives a generated device_key.
    IF v_device_key IS NULL THEN
        INSERT INTO dim_device (
            device_id,
            device_type,
            operating_system,
            device_brand,
            device_fingerprint,
            ip_address,
            first_seen
        )
        VALUES (
            p_device_id,
            p_device_type,
            p_operating_system,
            p_device_brand,
            p_device_fingerprint,
            p_ip_address,
            p_first_seen 
        )
        RETURNING device_key INTO v_device_key;
    ELSE
        -- Refresh only supplied metadata; NULL inputs preserve stored values.
        UPDATE dim_device
        SET
            ip_address = COALESCE(p_ip_address, ip_address),
            device_type = COALESCE(p_device_type, device_type),
            operating_system =
                COALESCE(p_operating_system, operating_system),
            device_brand = COALESCE(p_device_brand, device_brand)
        WHERE device_key = v_device_key;
    END IF;

    -- The caller uses this key when processing the transaction.
    RETURN v_device_key;
END;
$$ LANGUAGE plpgsql;

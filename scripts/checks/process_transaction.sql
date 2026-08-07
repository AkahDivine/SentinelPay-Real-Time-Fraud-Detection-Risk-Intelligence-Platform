-- =============================================================
-- STORED PROCEDURE: process_transaction
-- =============================================================
 
/*
    PURPOSE
    -------
    Processes one live transaction from validation through posting.
    A successful INSERT into fact_transactions automatically invokes the
    existing scoring trigger, which writes the transaction risk result.

    IMPORTANT DATE NOTE
    -------------------
    v_now uses CURRENT_TIMESTAMP, so this version is for live transactions.
    It must not be used to backdate generated 2023 history unless a transaction
    timestamp parameter is added and v_now is assigned from that parameter.

    COUNTERPARTY KEY RULES
    ----------------------
    Merchant : provide p_merchant_key only.
    Customer : provide p_counterparty_customer_key only.
    External/Employer : provide p_counterparty_key only.

    OUTPUTS
    -------
    p_status returns APPROVED or REJECTED.
    p_rejection_reason is NULL for approval or contains the rejection reason.
*/
CREATE OR REPLACE PROCEDURE process_transaction(
	IN p_customer_key 				INTEGER, 
	IN p_account_key 				INTEGER, 
	IN p_merchant_key 				INTEGER, 
	IN p_amount 					NUMERIC, 
	IN p_transaction_type 			VARCHAR(25), 
	IN p_channel 					VARCHAR(50), 
	IN p_device_key 				INTEGER, 
	IN p_location_key 				INTEGER, 
	IN p_transaction_direction 		VARCHAR(20), 
	IN p_counterparty_type 			VARCHAR(20), 
	IN p_counterparty_customer_key  INTEGER, 
	IN p_counterparty_key 			INTEGER, 
	INOUT p_status 					VARCHAR(50), 
	INOUT p_rejection_reason 		VARCHAR(100)
)
 
AS $$
DECLARE
    -- Account values are read once and retained for all validation and posting.
    v_account_status VARCHAR(20);
    v_daily_limit NUMERIC(18,2);
    v_current_balance NUMERIC(18,2);
    v_today_total NUMERIC(18,2);
    -- Live processing time. See the historical-date warning above.
    v_now TIMESTAMP := p_transaction_datetime;
    -- Keys and counterparty values derived inside the procedure.
    v_date_key INTEGER;
    v_transaction_key INTEGER;
    v_transaction_id VARCHAR(20);
    v_counterparty_account_id VARCHAR(30);
    v_counterparty_risk_score INTEGER;
BEGIN
    -- Clear any values supplied in the two INOUT output parameters.
    p_status 		   := NULL;
    p_rejection_reason := NULL;

    -- Basic request validation. Invalid input raises an exception because it
    -- cannot represent a valid transaction attempt.
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transaction amount must be greater than zero';
    END IF;

    IF p_transaction_direction NOT IN ('INFLOW', 'OUTFLOW') THEN
        RAISE EXCEPTION 'Invalid transaction direction: %',
            p_transaction_direction;
    END IF;

    /*
        Load and lock the account row.
        FOR UPDATE prevents two simultaneous transactions from spending the
        same balance before either transaction completes.
    */
    SELECT 
		account_status, 
		daily_limit, 
		balance
    INTO 
		v_account_status, 
		v_daily_limit, 
		v_current_balance
    FROM dim_accounts
    WHERE account_key = p_account_key
      AND customer_key = p_customer_key
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Account % does not belong to customer %',
            p_account_key,
            p_customer_key;
    END IF;

    -- The device must exist in dim_device. New devices should first be passed
    -- through register_live_device(), which returns their device_key.
    IF NOT EXISTS (
        SELECT 1 FROM dim_device WHERE device_key = p_device_key
    ) THEN
        RAISE EXCEPTION
            'Device % does not exist; call register_live_device first',
            p_device_key;
    END IF;

    -- Stop if the supplied location cannot be linked to dim_location.
    IF NOT EXISTS (
        SELECT 1 FROM dim_location WHERE location_key = p_location_key
    ) THEN
        RAISE EXCEPTION 'Unknown location_key %', p_location_key;
    END IF;

    /*
        Resolve the counterparty identifier and risk score.
        Exactly one dimension key is allowed for each counterparty type.
    */
    IF p_counterparty_type = 'Merchant' THEN
        IF p_merchant_key IS NULL
           OR p_counterparty_key IS NOT NULL
           OR p_counterparty_customer_key IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid Merchant counterparty keys';
        END IF;

        -- Merchant risk comes directly from dim_merchants.risk_score.
        SELECT 
			merchant_id, 
			risk_score
        INTO 
			v_counterparty_account_id, 
			v_counterparty_risk_score
        FROM dim_merchants
        WHERE merchant_key = p_merchant_key;

    ELSIF p_counterparty_type = 'Customer' THEN
        IF p_counterparty_customer_key IS NULL
           OR p_counterparty_key IS NOT NULL
           OR p_merchant_key IS NOT NULL
           OR p_counterparty_customer_key = p_customer_key THEN
            RAISE EXCEPTION 'Invalid Customer counterparty keys';
        END IF;

        -- A customer counterparty uses its current calculated customer risk.
        -- A score of 10 is used if no customer risk profile exists yet.
        SELECT
            c.customer_id,
            COALESCE(crp.risk_score, 10)
        INTO
            v_counterparty_account_id,
            v_counterparty_risk_score
        FROM dim_customers AS c
        LEFT JOIN customer_risk_profile AS crp
          ON crp.customer_key = c.customer_key
        WHERE c.customer_key = p_counterparty_customer_key
          AND c.created_at <= v_now;

    ELSIF p_counterparty_type IN ('External', 'Employer') THEN
        IF p_counterparty_key IS NULL
           OR p_counterparty_customer_key IS NOT NULL
           OR p_merchant_key IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid External/Employer counterparty keys';
        END IF;

        -- External and Employer counterparties use dim_counterparty.
        SELECT 
			account_id, 
			risk_score
        INTO 
			v_counterparty_account_id, 
			v_counterparty_risk_score
        FROM dim_counterparty
        WHERE counterparty_key = p_counterparty_key
          AND counterparty_type = p_counterparty_type
          AND created_at <= v_now;
    ELSE
        RAISE EXCEPTION 'Invalid counterparty type: %',
            p_counterparty_type;
    END IF;

    IF v_counterparty_account_id IS NULL THEN
        RAISE EXCEPTION 'Counterparty could not be resolved';
    END IF;

    /*
        Salary control:
        salaries must be Employer inflows, with no more than one successful
        salary transaction for the same account in the same calendar month.
    */
    IF p_transaction_type = 'Salary' THEN
        IF p_counterparty_type != 'Employer'
           OR p_transaction_direction != 'INFLOW' THEN
            RAISE EXCEPTION
                'Salary must be an Employer INFLOW transaction';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM fact_transactions
            WHERE account_key = p_account_key
              AND transaction_type = 'Salary'
              AND transaction_status = 'Success'
              AND DATE_TRUNC('month', transaction_datetime)
                  = DATE_TRUNC('month', v_now)
        ) THEN
            p_status := 'REJECTED';
            p_rejection_reason := 'Monthly Salary Already Received';
        END IF;
    END IF;

    -- Convert the transaction timestamp to the YYYYMMDD warehouse date key.
    v_date_key := TO_CHAR(v_now, 'YYYYMMDD')::INTEGER;
    IF NOT EXISTS (
        SELECT 1 FROM dim_date WHERE date_key = v_date_key
    ) THEN
        RAISE EXCEPTION 'Date % is missing from dim_date', v_date_key;
    END IF;

    -- Record a duplicate monthly salary attempt without posting it to the fact
    -- table or changing the account balance.
    IF p_status = 'REJECTED' THEN
        INSERT INTO rejected_transactions (
            customer_key, 
			account_key, 
			merchant_key, 
			device_key,
            location_key, 
			counterparty_customer_key, 
			counterparty_key,
            counterparty_account_id, 
			counterparty_type,
            counterparty_risk_score, 
			amount, 
			transaction_type,
            transaction_datetime, 
			channel, 
			transaction_direction,
            rejection_reason, 
			attempted_at
        )
        VALUES (
            p_customer_key, 
			p_account_key, 
			p_merchant_key, 
			p_device_key,
            p_location_key, 
			p_counterparty_customer_key,
            p_counterparty_key, 
			v_counterparty_account_id,
            p_counterparty_type, 
			v_counterparty_risk_score,
            p_amount, 
			p_transaction_type, 
			v_now, p_channel,
            p_transaction_direction, 
			p_rejection_reason, v_now
        );
        RETURN;
    END IF;

    /*
        Closed and suspended account attempts are deliberately inserted into
        fact_transactions as Failed. This allows score_transaction() to detect
        and classify the corresponding hard-rule fraud type. They are also
        copied to rejected_transactions and never affect the account balance.
    */
    IF v_account_status IN ('Closed', 'Suspended') THEN
        p_status := 'REJECTED';
        p_rejection_reason := CASE
            WHEN v_account_status = 'Closed' THEN 'Account Closed'
            ELSE 'Account Suspended'
        END;

        v_transaction_key := nextval('fact_transaction_key_seq');
        v_transaction_id :=
            'TXN_' || LPAD(v_transaction_key::TEXT, 8, '0');

        INSERT INTO fact_transactions (
            transaction_key, 
			customer_key, 
			account_key, 
			merchant_key,
            device_key, 
			location_key, 
			date_key, 
			transaction_id, 
			amount,
            transaction_type, 
			transaction_datetime, 
			channel,
            transaction_status, 
			failure_reason, 
			transaction_direction,
            counterparty_account_id, 
			counterparty_type,
            counterparty_risk_score, 
			counterparty_customer_key,
            counterparty_key
        )
        VALUES (
            v_transaction_key, 
			p_customer_key, 
			p_account_key,
            p_merchant_key, 
			p_device_key, 
			p_location_key, 
			v_date_key,
            v_transaction_id, 
			p_amount, 
			p_transaction_type, 
			v_now,
            p_channel, 
			'Failed', 
			p_rejection_reason,
            p_transaction_direction, 
			v_counterparty_account_id,
            p_counterparty_type, 
			v_counterparty_risk_score,
            p_counterparty_customer_key, 
			p_counterparty_key
        );

        INSERT INTO rejected_transactions (
            customer_key, 
			account_key, 
			merchant_key, 
			device_key,
            location_key, 
			counterparty_customer_key, 
			counterparty_key,
            counterparty_account_id, 
			counterparty_type,
            counterparty_risk_score, 
			amount, 
			transaction_type,
            transaction_datetime, 
			channel, 
			transaction_direction,
            rejection_reason, 
			attempted_at
        )
        VALUES (
            p_customer_key, 
			p_account_key, 
			p_merchant_key, 
			p_device_key,
            p_location_key, 
			p_counterparty_customer_key,
            p_counterparty_key, 
			v_counterparty_account_id,
            p_counterparty_type, 
			v_counterparty_risk_score,
            p_amount, 
			p_transaction_type, 
			v_now, p_channel,
            p_transaction_direction, 
			p_rejection_reason, 
			v_now
        );
        RETURN;
    END IF;

    -- Reject an outgoing transaction when available balance is insufficient.
    IF p_transaction_direction = 'OUTFLOW'
       AND v_current_balance < p_amount THEN
        p_status := 'REJECTED';
        p_rejection_reason := 'Insufficient Funds';
    END IF;

    /*
        Enforce the account's daily outgoing limit using successful outflows
        already posted on the same transaction date.
    */
    IF p_transaction_direction = 'OUTFLOW'
       AND p_status IS DISTINCT FROM 'REJECTED' THEN
        SELECT COALESCE(SUM(amount), 0)
        INTO v_today_total
        FROM fact_transactions
        WHERE customer_key = p_customer_key
          AND account_key = p_account_key
          AND DATE(transaction_datetime) = DATE(v_now)
          AND transaction_status = 'Success'
          AND transaction_direction = 'OUTFLOW';

        IF v_today_total + p_amount > v_daily_limit THEN
            p_status := 'REJECTED';
            p_rejection_reason := 'Daily Limit Exceeded';
        END IF;
    END IF;

    -- Balance and daily-limit failures are audit-only rejected attempts.
    IF p_status = 'REJECTED' THEN
        INSERT INTO rejected_transactions (
            customer_key, 
			account_key, 
			merchant_key, 
			device_key,
            location_key, 
			counterparty_customer_key, 
			counterparty_key,
            counterparty_account_id, 
			counterparty_type,
            counterparty_risk_score, amount, 
			transaction_type,
            transaction_datetime, 
			channel, 
			transaction_direction,
            rejection_reason, 
			attempted_at
        )
        VALUES (
            p_customer_key, 
			p_account_key, 
			p_merchant_key, 
			p_device_key,
            p_location_key, 
			p_counterparty_customer_key,
            p_counterparty_key, 
			v_counterparty_account_id,
            p_counterparty_type, 
			v_counterparty_risk_score,
            p_amount, p_transaction_type, 
			v_now, 
			p_channel,
            p_transaction_direction, 
			p_rejection_reason, 
			v_now
        );
        RETURN;
    END IF;

    /*
        Approval and fact posting.
        The generated key is used for both the warehouse key and transaction
        identifier. Inserting the fact row fires the scoring trigger.
    */
    p_status 			:= 'APPROVED';
    p_rejection_reason 	:= NULL;
    v_transaction_key 	:= nextval('fact_transaction_key_seq');
    v_transaction_id :=
        'TXN_' || LPAD(v_transaction_key::TEXT, 8, '0');

    INSERT INTO fact_transactions (
        transaction_key, 
		customer_key, 
		account_key, 
		merchant_key,
        device_key, 
		location_key, 
		date_key, 
		transaction_id, 
		amount,
        transaction_type, 
		transaction_datetime, 
		channel,
        transaction_status, 
		failure_reason, 
		transaction_direction,
        counterparty_account_id, 
		counterparty_type,
        counterparty_risk_score, 
		counterparty_customer_key,
        counterparty_key
    )
    VALUES (
        v_transaction_key, 
		p_customer_key, 
		p_account_key,
        p_merchant_key, 
		p_device_key, 
		p_location_key, 
		v_date_key,
        v_transaction_id, 
		p_amount, 
		p_transaction_type, 
		v_now,
        p_channel, 
		'Success', 
		NULL, 
		p_transaction_direction,
        v_counterparty_account_id, 
		p_counterparty_type,
        v_counterparty_risk_score, 
		p_counterparty_customer_key,
        p_counterparty_key
    );

    -- Preserve the balance before and after the approved movement.
    INSERT INTO account_balance_history (
        account_key, 
		customer_key, 
		transaction_key, 
		movement_type,
        amount, 
		balance_before, 
		balance_after, 
		recorded_at
    )
    VALUES (
        p_account_key, 
		p_customer_key, 
		v_transaction_key,
        CASE
            WHEN p_transaction_direction = 'OUTFLOW' THEN 'DEBIT'
            ELSE 'CREDIT'
        END,
        p_amount,
        v_current_balance,
        CASE
            WHEN p_transaction_direction = 'OUTFLOW'
                THEN v_current_balance - p_amount
            ELSE v_current_balance + p_amount
        END,
        v_now
    );

    -- Apply the debit or credit to the current account balance.
    UPDATE dim_accounts
    SET balance = CASE
        WHEN p_transaction_direction = 'OUTFLOW'
            THEN balance - p_amount
        ELSE balance + p_amount
    END
    WHERE account_key = p_account_key;

    /*
        Register the device/customer relationship after scoring.
        Therefore, the first transaction from a new or previously unassigned
        device can be flagged; later transactions recognise it as assigned.
    */
    INSERT INTO customer_devices (
        customer_key, 
		device_key, 
		is_primary, 
		status,
        first_seen, 
		last_seen
    )
    VALUES (
        p_customer_key, 
		p_device_key, 
		FALSE, 
		'Active', 
		v_now, 
		v_now
    )
    ON CONFLICT (customer_key, device_key)
    DO UPDATE SET
        last_seen = EXCLUDED.last_seen,
        status = 'Active';
END;
$$ LANGUAGE plpgsql;

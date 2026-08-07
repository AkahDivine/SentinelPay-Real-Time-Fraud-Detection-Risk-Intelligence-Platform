CREATE OR REPLACE FUNCTION score_transaction()
RETURNS trigger

AS $$
DECLARE
    -- hard rules
    v_hard_score        INTEGER;
    v_hard_flag         BOOLEAN;
    v_hard_triggered    VARCHAR(50);
    v_skip_composite    BOOLEAN := FALSE;

    -- signal scores and flags
    v_velocity_score    INTEGER;
    v_velocity_flag     BOOLEAN;
    v_spike_score       INTEGER;
    v_spike_flag        BOOLEAN;
    v_location_score    INTEGER;
    v_location_flag     BOOLEAN;
    v_device_score      INTEGER;
    v_device_flag       BOOLEAN;
    v_offhour_score     INTEGER;
    v_offhour_flag      BOOLEAN;
    v_merchant_score    INTEGER;
    v_merchant_flag     BOOLEAN;
    v_inflow_score      INTEGER;
    v_inflow_flag       BOOLEAN;

    -- composite results
    v_composite_score   NUMERIC;
    v_final_score       INTEGER;
    v_risk_tier         VARCHAR(15);
    v_fraud_type        VARCHAR(50);
    v_alert_id          INTEGER;
	v_account_created_at TIMESTAMP;
    v_is_new_account    BOOLEAN := FALSE;
	
BEGIN

-- Call all 7 signal functions
	SELECT 
		hard_rule_score, 
		hard_rule_flag, 
		hard_rule_triggered
	INTO 
		v_hard_score, 
		v_hard_flag, 
		v_hard_triggered
	FROM check_hard_rules(
	    NEW.customer_key,
	    NEW.transaction_datetime,
	    NEW.amount,
	    NEW.transaction_key,
	    NEW.account_key,
	    NEW.transaction_direction
	);
	
-- If Closed or Suspended — skip composite entirely
	IF v_hard_triggered IN ('Closed Account Transaction', 
	                        'Suspended Account Transaction') THEN
	    v_skip_composite := TRUE;
	    v_final_score    := v_hard_score;
	END IF;

	IF v_skip_composite = FALSE THEN
	
	    SELECT 
			velocity_score, 
			velocity_flag
	    INTO 
			v_velocity_score, 
			v_velocity_flag
	    FROM check_velocity(
	        NEW.customer_key,
	        NEW.transaction_datetime,
	        NEW.transaction_key,
	        NEW.account_key
	    );
	
	    SELECT 
			amount_score, 
			amount_flag
	    INTO 
			v_spike_score, 
			v_spike_flag
	    FROM check_amount_spike(
	        NEW.customer_key,
	        NEW.amount,
	        NEW.transaction_key,
	        NEW.transaction_datetime,
	        NEW.account_key
	    );
	
	    SELECT 
			location_score, 
			location_flag
	    INTO 
			v_location_score, 
			v_location_flag
	    FROM check_location(
	        NEW.customer_key,
	        NEW.location_key,
	        NEW.transaction_datetime,
	        NEW.transaction_key
	    );
	
	    SELECT 
			device_score, 
			device_flag
	    INTO 
			v_device_score, 
			v_device_flag
	    FROM check_device(
	        NEW.customer_key,
	        NEW.device_key,
	        NEW.transaction_datetime,
	        NEW.transaction_key
	    );
	
	    SELECT 
			off_hour_score, 
			off_hour_flag
	    INTO 
			v_offhour_score, 
			v_offhour_flag
	    FROM check_off_hour(
	        NEW.customer_key,
	        NEW.transaction_datetime,
	        NEW.transaction_key
	    );
	
	    SELECT 
			merchant_score, 
			merchant_flag
	    INTO 	
			v_merchant_score, 
			v_merchant_flag
	    FROM check_merchant(
	        NEW.customer_key,
	        NEW.merchant_key,
	        NEW.transaction_datetime,
	        NEW.transaction_key
	    );
	
	    SELECT 
			inflow_score, 
			inflow_flag
	    INTO 
			v_inflow_score, 
			v_inflow_flag
	    FROM check_inflow(
	        NEW.customer_key,
	        NEW.amount,
	        NEW.transaction_datetime,
	        NEW.transaction_key,
	        NEW.transaction_direction,
	        NEW.counterparty_type,
	        NEW.counterparty_risk_score
	    );
	
	END IF;

-- Weighted composite score
	IF v_skip_composite = FALSE THEN
	
	    v_composite_score :=
	        (v_velocity_score  * 0.20) +
	        (v_spike_score     * 0.20) +
	        (v_location_score  * 0.15) +
	        (v_device_score    * 0.15) +
	        (v_merchant_score  * 0.10) +
	        (v_offhour_score   * 0.10) +
	        (v_inflow_score    * 0.10) + COALESCE(v_hard_score, 0);
	
	END IF;

	    ----------------------------------------------------------
	    -- HARD RULE BONUS
	    ----------------------------------------------------------
		v_composite_score := COALESCE(v_composite_score, 0);
	    ----------------------------------------------------------
	    -- CAP SCORE
	    ----------------------------------------------------------
	    IF v_skip_composite = FALSE THEN
            v_final_score := LEAST(100, ROUND(v_composite_score));
        END IF;
	-- ==========================================================
	-- MINIMUM SCORE PROMOTION RULES
	-- ==========================================================

	SELECT created_at
	INTO v_account_created_at
	FROM dim_accounts
	WHERE account_key = NEW.account_key;
	
	v_is_new_account :=
    	NEW.transaction_datetime - v_account_created_at <= INTERVAL '30 days';
	
	-- Account Takeover
	IF v_device_flag AND v_location_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	IF v_device_flag AND v_spike_flag THEN
	    v_final_score := GREATEST(v_final_score, 75);
	END IF;
	
	IF v_location_flag AND v_spike_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	
	-- Transaction Fraud
	IF v_velocity_flag AND v_spike_flag THEN
	    v_final_score := GREATEST(v_final_score, 75);
	END IF;
	
	IF v_velocity_flag AND v_offhour_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	IF v_velocity_flag AND v_device_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	
	-- Money Mule
	IF v_inflow_flag AND v_velocity_flag THEN
	    v_final_score := GREATEST(v_final_score, 80);
	END IF;
	
	
	-- Merchant Fraud
	IF v_merchant_flag AND v_spike_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	IF v_merchant_flag AND v_offhour_flag THEN
	    v_final_score := GREATEST(v_final_score, 70);
	END IF;
	
	
	/*
	    Identity Fraud promotion must use the same complete condition as the
	    classification below. Previously, a new account with only an unfamiliar
	    location was promoted to High risk and then became Unclassified Fraud.
	*/
	IF v_is_new_account
	   AND (v_device_flag OR v_location_flag)
	   AND v_merchant_flag THEN
	    v_final_score := GREATEST(v_final_score, 75);
	END IF;
	


-- Assign risk tier
	IF v_final_score >= 86 THEN
	    v_risk_tier := 'Critical';
	ELSEIF v_final_score >= 61 THEN
	    v_risk_tier := 'High';
	ELSEIF v_final_score >= 31 THEN
	    v_risk_tier := 'Medium';
	ELSE
	    v_risk_tier := 'Low';
	END IF;


-- Classify fraud type
	IF v_hard_triggered = 'Closed Account Transaction' THEN
	    v_fraud_type := 'Closed Account Transaction';
	
	ELSIF v_hard_triggered = 'Suspended Account Transaction' THEN
	    v_fraud_type := 'Suspended Account Transaction';
	
	ELSIF (v_device_flag AND v_location_flag)
	   OR (v_device_flag AND v_spike_flag)
	   OR (v_location_flag AND v_spike_flag) THEN
	    v_fraud_type := 'Account Takeover';
	
	ELSIF (v_velocity_flag AND v_spike_flag)
	   OR (v_velocity_flag AND v_offhour_flag)
	   OR (v_spike_flag AND v_offhour_flag) THEN
	    v_fraud_type := 'Transaction Fraud';
	
	ELSIF v_inflow_flag AND v_velocity_flag THEN
	    v_fraud_type := 'Money Mule';
	
	ELSIF v_is_new_account AND (v_device_flag OR v_location_flag)
      AND v_merchant_flag THEN
	    v_fraud_type := 'Identity Fraud';
	
	ELSIF v_merchant_flag AND v_spike_flag THEN
	    v_fraud_type := 'Merchant Fraud';
	
	ELSIF v_risk_tier IN ('High', 'Critical') THEN
	    v_fraud_type := 'Unclassified Fraud';
	
	ELSE
	    v_fraud_type := NULL;
	END IF;


-- Write to fact_risk_scores
	INSERT INTO fact_risk_scores (
	    transaction_key, 
		customer_key, 
		risk_score, 
		risk_tier,
	    calculated_at, 
		model_version,
	    velocity_flag, 
		amount_flag, 
		location_flag, 
		device_flag,
	    off_hour_flag, 
		merchant_flag, 
		inflow_flag
	) VALUES (
	    NEW.transaction_key, 
		NEW.customer_key, 
		v_final_score, 
		v_risk_tier,
	    NEW.transaction_datetime + INTERVAL '1 second', 
		'v1.0',
	    COALESCE(v_velocity_flag, FALSE),
	    COALESCE(v_spike_flag,    FALSE),
	    COALESCE(v_location_flag, FALSE),
	    COALESCE(v_device_flag,   FALSE),
	    COALESCE(v_offhour_flag,  FALSE),
	    COALESCE(v_merchant_flag, FALSE),
	    COALESCE(v_inflow_flag,   FALSE)
	);


-- Write to fraud_alerts and fact_fraud_events if High/Critical
	IF v_risk_tier IN ('High', 'Critical') THEN
	
	    INSERT INTO fraud_alerts (
	        transaction_key, 
			customer_key, 
			alert_reason,
	        alert_severity, 
			risk_score, 
			estimated_exposure,
	        alert_status, 
			created_at
	    ) VALUES (
	        NEW.transaction_key,
	        NEW.customer_key,
	        COALESCE(v_hard_triggered, 
			v_fraud_type, 'Suspicious transaction detected'),
	        v_risk_tier,
	        v_final_score,
	        NEW.amount,
	        'Open',
	        NEW.transaction_datetime + INTERVAL '2 seconds'
	    ) RETURNING alert_id INTO v_alert_id;
	
	    INSERT INTO fact_fraud_events (
	        transaction_key, 
			customer_key, 
			alert_id,
	        amount_flagged, 
			fraud_type, 
			fraud_score,
	        decision_taken, 
			rule_triggered, 
			detected_at
	    ) VALUES (
	        NEW.transaction_key,
	        NEW.customer_key,
	        v_alert_id,
	        NEW.amount,
	        v_fraud_type,
	        v_final_score,
	        CASE WHEN v_risk_tier = 'Critical' 
	             THEN 'Transaction Blocked'
	             ELSE 'Transaction Flagged'
	        END,
	        COALESCE(v_fraud_type, v_hard_triggered),
	        NEW.transaction_datetime + INTERVAL '3 seconds'
	    );
	
	END IF;
	
	RETURN NEW;
	
END;
$$ LANGUAGE plpgsql

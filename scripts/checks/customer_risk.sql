/*
    PURPOSE
    -------
    Recalculates one customer's current risk profile from transaction scores
    and confirmed fraud events within a rolling 90-day window.

    p_window_end controls the end of the calculation window. Passing a 2023
    timestamp supports historical backfills; omitting it uses the current time.

    SCORE WEIGHTS
    -------------
    50% average transaction risk score
    25% proportion of High/Critical transactions
    20% fraud-event rate
     5 points when a fraud event occurred within the last 30 days
*/
CREATE OR REPLACE FUNCTION refresh_customer_risk_profile(
	p_customer_key INTEGER, 
	p_window_end   TIMESTAMP without time zone DEFAULT CURRENT_TIMESTAMP)
RETURNS void

AS $$
DECLARE
    -- Define the window and initialise all aggregate values safely.
    v_window_start TIMESTAMP := p_window_end - INTERVAL '90 days';
    v_average_score NUMERIC(5,2) := 0;
    v_high_count INTEGER := 0;
    v_fraud_count INTEGER := 0;
    v_transaction_count INTEGER := 0;
    v_recent_fraud BOOLEAN := FALSE;
    v_risk_score INTEGER := 0;
    v_risk_tier VARCHAR(15);
BEGIN
    -- Aggregate transaction-level risk results inside the 90-day window.
    -- Count fraud events and determine whether any occurred in the last 30 days.
    SELECT
        COALESCE(AVG(rs.risk_score), 0),
        COUNT(*) FILTER (
            WHERE rs.risk_tier IN ('High', 'Critical')
        ),
        COUNT(*)
    INTO
        v_average_score,
        v_high_count,
        v_transaction_count
    FROM fact_risk_scores AS rs
    WHERE rs.customer_key = p_customer_key
      AND rs.calculated_at >= v_window_start
      AND rs.calculated_at <= p_window_end;

    SELECT
        COUNT(*),
        COALESCE(
            MAX(fe.detected_at) >= p_window_end - INTERVAL '30 days',
            FALSE
        )
    INTO
        v_fraud_count,
        v_recent_fraud
    FROM fact_fraud_events AS fe
    WHERE fe.customer_key = p_customer_key
      AND fe.detected_at >= v_window_start
      AND fe.detected_at <= p_window_end;

    -- Calculate a capped 0-100 score. The guard prevents division by zero.
    IF v_transaction_count > 0 THEN
        v_risk_score := LEAST(
            100,
            ROUND(
                (v_average_score * 0.50)
                + (
                    v_high_count::NUMERIC
                    / v_transaction_count
                    * 100
                    * 0.25
                )
                + (
                    v_fraud_count::NUMERIC
                    / v_transaction_count
                    * 100
                    * 0.20
                )
                + CASE WHEN v_recent_fraud THEN 5 ELSE 0 END
            )
        );
    END IF;

    -- Convert the numeric score into the project's four risk tiers.
    v_risk_tier := CASE
        WHEN v_risk_score >= 86 THEN 'Critical'
        WHEN v_risk_score >= 61 THEN 'High'
        WHEN v_risk_score >= 31 THEN 'Medium'
        ELSE 'Low'
    END;

    /*
        Preserve the calculation as a dated snapshot. The unique customer/date
        constraint means repeated live transactions update today's snapshot
        instead of inserting many duplicate rows. Monthly backfill calls this
        function once per customer-month and labels those rows afterward.
    */
    INSERT INTO customer_risk_profile_history (
        customer_key,
        risk_score,
        risk_tier,
        average_transaction_score,
        high_risk_transaction_count,
        fraud_event_count,
        transactions_analyzed,
        window_start,
        window_end,
        snapshot_date,
        snapshot_type,
        calculated_at
    )
    VALUES (
        p_customer_key,
        v_risk_score,
        v_risk_tier,
        v_average_score,
        v_high_count,
        v_fraud_count,
        v_transaction_count,
        v_window_start,
        p_window_end,
        p_window_end::DATE,
        'Daily',
        p_window_end
    )
    ON CONFLICT (customer_key, snapshot_date) DO UPDATE SET
        risk_score = EXCLUDED.risk_score,
        risk_tier = EXCLUDED.risk_tier,
        average_transaction_score =
            EXCLUDED.average_transaction_score,
        high_risk_transaction_count =
            EXCLUDED.high_risk_transaction_count,
        fraud_event_count = EXCLUDED.fraud_event_count,
        transactions_analyzed = EXCLUDED.transactions_analyzed,
        window_start = EXCLUDED.window_start,
        window_end = EXCLUDED.window_end,
        calculated_at = EXCLUDED.calculated_at;

    /*
        Keep one current row per customer.
        INSERT creates the first profile; ON CONFLICT replaces its calculated
        metrics when that customer's profile already exists.
    */
    INSERT INTO customer_risk_profile (
        customer_key,
        risk_score,
        risk_tier,
        average_transaction_score,
        high_risk_transaction_count,
        fraud_event_count,
        transactions_analyzed,
        window_start,
        window_end,
        calculated_at
    )
    VALUES (
        p_customer_key,
        v_risk_score,
        v_risk_tier,
        v_average_score,
        v_high_count,
        v_fraud_count,
        v_transaction_count,
        v_window_start,
        p_window_end,
        /*
            Use the calculation window's end time, not the computer's current
            time. Historical profiles therefore retain their 2023/2024 date,
            while live processing still records the live transaction datetime
            supplied as p_window_end.
        */
        p_window_end
    )
    ON CONFLICT (customer_key) DO UPDATE SET
        risk_score = EXCLUDED.risk_score,
        risk_tier = EXCLUDED.risk_tier,
        average_transaction_score =
            EXCLUDED.average_transaction_score,
        high_risk_transaction_count =
            EXCLUDED.high_risk_transaction_count,
        fraud_event_count = EXCLUDED.fraud_event_count,
        transactions_analyzed = EXCLUDED.transactions_analyzed,
        window_start = EXCLUDED.window_start,
        window_end = EXCLUDED.window_end,
        calculated_at = EXCLUDED.calculated_at;
END;
$$ LANGUAGE plpgsql;

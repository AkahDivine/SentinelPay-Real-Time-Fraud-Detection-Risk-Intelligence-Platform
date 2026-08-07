/*
    TRIGGER FUNCTION
    ----------------
    Runs after a transaction risk-score row is inserted or updated. It refreshes
    the affected customer's 90-day profile using the score calculation time as
    the window end. NEW represents the new fact_risk_scores row.

    This file defines the trigger function only; the trigger on
    fact_risk_scores must already exist or be created separately.
*/
CREATE OR REPLACE FUNCTION refresh_customer_risk_after_score()
RETURNS trigger
 
AS $$
BEGIN
    -- PERFORM calls a function returning void when no result row is required.
    PERFORM refresh_customer_risk_profile(
        NEW.customer_key,
        NEW.calculated_at
    );
    -- AFTER triggers return NEW for clarity, although the row is already saved.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;












/*
    TRIGGER FUNCTION
    ----------------
    Runs after a fraud-event row is inserted or updated. It recalculates the
    affected customer's profile so the fraud count and recent-fraud bonus are
    immediately reflected. NEW represents the new fact_fraud_events row.

    This file defines the trigger function only; the trigger on
    fact_fraud_events must already exist or be created separately.
*/
CREATE OR REPLACE FUNCTION refresh_customer_risk_after_fraud()
 RETURNS trigger
 
AS $$
BEGIN
    -- Use the event detection time as the end of the rolling risk window.
    PERFORM refresh_customer_risk_profile(
        NEW.customer_key,
        NEW.detected_at
    );
    -- AFTER triggers return NEW for clarity, although the row is already saved.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

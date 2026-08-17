

CREATE OR REPLACE VIEW vw_fraud_investigation AS
SELECT
    /* Alert identifiers */
    fa.alert_key,
    fa.alert_id,
    fa.transaction_key,
    fa.customer_key,

    /* Alert workflow */
    fa.alert_reason,
    fa.alert_severity AS severity,
    fa.alert_status,
    fa.assigned_to,
    fa.resolution,
    fa.resolution_comment,
    fa.created_at AS alert_created_at,
    fa.resolved_at,

    /* Transaction details */
    ft.transaction_id,
    ft.transaction_datetime,
    ft.amount,
    ft.transaction_type,
    ft.transaction_direction,
    ft.channel,
    ft.transaction_status,

    /* Readable customer identifier */
    dc.customer_id,

    /* Transaction risk */
    frs.risk_score,
    frs.risk_tier,

    /* Fraud-event details */
    ffe.fraud_type,
    ffe.rule_triggered,
    ffe.decision_taken,
    ffe.detected_at

FROM fraud_alerts AS fa

JOIN fact_transactions AS ft
    ON ft.transaction_key = fa.transaction_key

JOIN dim_customers AS dc
    ON dc.customer_key = fa.customer_key

JOIN fact_risk_scores AS frs
    ON frs.transaction_key = fa.transaction_key

LEFT JOIN fact_fraud_events AS ffe
    ON ffe.transaction_key = fa.transaction_key;

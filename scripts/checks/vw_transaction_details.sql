/*
    Power BI Transaction Drill-through Detail view.

    Grain: one row per transaction.
    The view combines only tables that should have at most one matching row
    for a transaction. LEFT JOIN keeps normal transactions even when they do
    not have a fraud event, alert, merchant, or external counterparty.

    IMPORTANT: fact_risk_scores, fact_fraud_events and fraud_alerts must each
    contain at most one row per transaction_key; otherwise the view can return
    duplicate transaction rows.
*/
CREATE OR REPLACE VIEW public.vw_transaction_details AS
SELECT
    /* Existing columns: keep their names and order for Power BI compatibility. */
    ft.transaction_datetime AS date_time,
    ft.transaction_id,
    dc.full_name AS customer_name,
    ft.transaction_type,
    ft.channel,
    ft.transaction_status AS status,
    ft.transaction_direction,
    ft.amount,
    frs.risk_tier,
    dl.state,

    /* Existing relationship/filter columns. */
    ft.transaction_key,
    ft.customer_key,
    ft.account_key,
    ft.location_key,
    ft.date_key,

    /* Existing transaction-detail columns. */
    ft.transaction_narration,
    ft.counterparty_type,
    ft.counterparty_account_id AS counterparty_id,
    ffe.fraud_type,
    da.account_number,

    /* Customer details. */
    dc.customer_id,
    dc.bvn,
    dc.segment AS customer_segment,
    dc.kyc_status,
    dc.created_at AS customer_since,

    /* Customer account details. */
    da.account_id,
    da.account_type,
    da.currency,
    da.balance,
    da.daily_limit,
    da.account_status,
    da.created_at AS account_created_at,

    /*
        Resolve the displayed counterparty from the appropriate dimension:
        Merchant -> dim_merchants
        External/Employer -> dim_counterparty
        Customer -> dim_customers
    */
    COALESCE(
        dm.merchant_name,
        dcp.name,
        counterparty_customer.full_name,
        ft.counterparty_account_id
    ) AS counterparty_name,
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.merchant_category
        ELSE NULL
    END AS merchant_category,
    CASE
        WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.bank_name
        ELSE NULL
    END AS counterparty_bank_name,
    /* Current entity score; transaction-captured score is the fallback. */
    COALESCE(
        CASE
            WHEN ft.counterparty_type = 'Merchant' THEN dm.risk_score
            WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.risk_score
            WHEN ft.counterparty_type = 'Customer' THEN counterparty_crp.risk_score
        END,
        ft.counterparty_risk_score
    ) AS counterparty_risk_score,
    COALESCE(
        CASE
            WHEN ft.counterparty_type = 'Merchant' THEN dm.risk_level
            WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.risk_tier
            WHEN ft.counterparty_type = 'Customer' THEN counterparty_crp.risk_tier
        END,
        CASE
            WHEN ft.counterparty_risk_score >= 85 THEN 'Critical'
            WHEN ft.counterparty_risk_score >= 60 THEN 'High'
            WHEN ft.counterparty_risk_score >= 30 THEN 'Medium'
            ELSE 'Low'
        END
    )::TEXT AS counterparty_risk_tier,

    /* Device details and whether the device belongs to this customer. */
    dd.device_key,
    dd.device_id,
    dd.device_type,
    dd.operating_system,
    dd.device_brand,
    dd.ip_address,
    dd.first_seen AS device_first_seen,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.customer_devices AS cd
            WHERE cd.customer_key = ft.customer_key
              AND cd.device_key = ft.device_key
        ) THEN 'Known'
        ELSE 'Unknown'
    END AS customer_device_status,

    /* Location details. */
    dl.country,
    dl.geopolitical_zone,
    dl.risk_level AS location_risk_level,

    /* Transaction result details. */
    ft.failure_reason,

    /* Transaction risk result and the seven scoring flags. */
    frs.risk_score,
    frs.calculated_at,
    frs.velocity_flag,
    frs.amount_flag AS amount_spike_flag,
    frs.location_flag,
    frs.device_flag,
    frs.off_hour_flag,
    frs.merchant_flag,
    frs.inflow_flag,

    /* Fraud-event details; blank for transactions that are not fraud events. */
    ffe.fraud_score,
    ffe.amount_flagged,
    ffe.rule_triggered,
    ffe.decision_taken,
    ffe.detected_at,

    /* Analyst-alert workflow details; blank when no alert exists. */
    fa.alert_id,
    fa.alert_reason,
    fa.alert_severity,
    fa.alert_status,
    fa.assigned_to,
    fa.resolution,
    fa.resolution_comment,
    fa.created_at AS alert_created_at,
    fa.resolved_at,

    /* Hard-rule evidence. */
    frs.hard_rule_triggered,
    (frs.hard_rule_triggered IS NOT NULL) AS hard_rule_flag,

    /* Resolved merchant/external/employer/customer investigation fields. */
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.merchant_key
        WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.counterparty_key
        WHEN ft.counterparty_type = 'Customer' THEN counterparty_customer.customer_key
    END AS resolved_counterparty_key,
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.merchant_id
        WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.account_id
        WHEN ft.counterparty_type = 'Customer' THEN counterparty_customer.customer_id
        ELSE ft.counterparty_account_id
    END AS resolved_counterparty_id,
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.state
        WHEN ft.counterparty_type = 'Customer' THEN counterparty_customer.state
        /* dim_counterparty does not store state; use transaction state. */
        ELSE dl.state
    END AS counterparty_state,
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.status
        ELSE NULL
    END AS counterparty_status,
    CASE
        WHEN ft.counterparty_type = 'Merchant' THEN dm.merchant_category
        WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.bank_name
        WHEN ft.counterparty_type = 'Customer' THEN counterparty_customer.segment
        ELSE NULL
    END AS counterparty_category_or_bank,
    CASE
        WHEN ft.counterparty_type IN ('External', 'Employer') THEN dcp.created_at
        WHEN ft.counterparty_type = 'Customer' THEN counterparty_customer.created_at
        ELSE NULL
    END AS counterparty_created_at

FROM public.fact_transactions AS ft

INNER JOIN public.dim_customers AS dc
    ON dc.customer_key = ft.customer_key

INNER JOIN public.dim_accounts AS da
    ON da.account_key = ft.account_key

INNER JOIN public.fact_risk_scores AS frs
    ON frs.transaction_key = ft.transaction_key

INNER JOIN public.dim_location AS dl
    ON dl.location_key = ft.location_key

LEFT JOIN public.dim_device AS dd
    ON dd.device_key = ft.device_key

LEFT JOIN public.dim_merchants AS dm
    ON dm.merchant_key = ft.merchant_key
   AND ft.counterparty_type = 'Merchant'

LEFT JOIN public.dim_counterparty AS dcp
    ON dcp.counterparty_key = ft.counterparty_key
   AND ft.counterparty_type IN ('External', 'Employer')

LEFT JOIN public.dim_customers AS counterparty_customer
    ON counterparty_customer.customer_key = ft.counterparty_customer_key
   AND ft.counterparty_type = 'Customer'

LEFT JOIN public.customer_risk_profile AS counterparty_crp
    ON counterparty_crp.customer_key = ft.counterparty_customer_key
   AND ft.counterparty_type = 'Customer'

LEFT JOIN public.fact_fraud_events AS ffe
    ON ffe.transaction_key = ft.transaction_key

LEFT JOIN public.fraud_alerts AS fa
    ON fa.transaction_key = ft.transaction_key;

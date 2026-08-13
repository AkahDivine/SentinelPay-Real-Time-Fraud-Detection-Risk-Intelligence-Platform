CREATE OR REPLACE VIEW public.vw_customer_account_search AS
SELECT
    c.customer_key,
    c.customer_id,
    c.full_name,
    c.bvn,
	
    -- The database column is segment, but the view exposes a clearer name.
    c.segment AS customer_segment,

    c.kyc_status,
    c.location_key,

    c.state AS state,

    rp.risk_score,
    rp.risk_tier,

    a.account_key,
    a.account_id,
    a.account_number,
    a.account_type,
    a.account_status,
    a.balance,
    a.daily_limit,
    a.currency,
    a.created_at AS account_created_at,

    CONCAT_WS(
        ' ',
        c.customer_id,
        a.account_id,
        a.account_number,
        c.full_name
    ) AS search_filter,

    -- Newly added customer details
    c.gender,
    c.preferred_channel,
    c.created_at AS customer_created_at,

	CASE
    WHEN c.bvn IS NULL THEN NULL
    WHEN LENGTH(c.bvn::TEXT) <= 4 THEN c.bvn::TEXT
    ELSE
        REPEAT('*', LENGTH(c.bvn::TEXT) - 4)
        || RIGHT(c.bvn::TEXT, 4)
	END AS masked_bvn,

	CASE
    WHEN c.phone IS NULL THEN NULL
    WHEN LENGTH(c.phone) < 7 THEN c.phone
    ELSE
        LEFT(c.phone, 4)
        || '****'
        || RIGHT(c.phone, 3)
	END AS masked_phone,

	c.phone AS phone_number


FROM public.dim_customers AS c

LEFT JOIN public.dim_accounts AS a
    ON a.customer_key = c.customer_key

LEFT JOIN public.dim_location AS l
    ON l.location_key = c.location_key

LEFT JOIN public.customer_risk_profile AS rp
    ON rp.customer_key = c.customer_key;

-- SENTINELPAY DATABASE TABLE DDL
-- -----------------------------------------------------------------------------
-- These SQL statements recreate the current SentinelPay database tables.
-- The file defines all columns, data types, generated identities, sequences,
-- primary keys, foreign keys, validation constraints, unique constraints and
-- performance indexes. It contains no data, functions, procedures, triggers,
-- views, database roles or credentials.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS fraud_alerts CASCADE;
DROP TABLE IF EXISTS fact_fraud_events CASCADE;
DROP TABLE IF EXISTS fact_risk_scores CASCADE;
DROP TABLE IF EXISTS account_balance_history CASCADE;
DROP TABLE IF EXISTS rejected_transactions CASCADE;
DROP TABLE IF EXISTS fact_transactions CASCADE;
DROP TABLE IF EXISTS customer_risk_profile_history CASCADE;
DROP TABLE IF EXISTS customer_risk_profile CASCADE;
DROP TABLE IF EXISTS customer_devices CASCADE;
DROP TABLE IF EXISTS dim_accounts CASCADE;
DROP TABLE IF EXISTS dim_counterparty CASCADE;
DROP TABLE IF EXISTS dim_merchants CASCADE;
DROP TABLE IF EXISTS dim_device CASCADE;
DROP TABLE IF EXISTS dim_customers CASCADE;
DROP TABLE IF EXISTS dim_risk_tier CASCADE;
DROP TABLE IF EXISTS dim_time CASCADE;
DROP TABLE IF EXISTS dim_location CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;


-- 1. account_balance_history
CREATE TABLE account_balance_history (
    balance_history_key     INTEGER NOT NULL,
    account_key             INTEGER NOT NULL,
    customer_key            INTEGER NOT NULL,
    transaction_key         INTEGER NOT NULL,
    movement_type           VARCHAR(10) NOT NULL,
    amount                  NUMERIC(18,2) NOT NULL,
    balance_before          NUMERIC(18,2) NOT NULL,
    balance_after           NUMERIC(18,2) NOT NULL,
    recorded_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_balance_history_amount CHECK ((amount > (0)::NUMERIC)),
    CONSTRAINT ck_balance_history_movement CHECK (((movement_type)::TEXT = ANY ((ARRAY['DEBIT'::VARCHAR, 'CREDIT'::VARCHAR])::TEXT[])))
);


ALTER TABLE account_balance_history ALTER COLUMN balance_history_key ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME account_balance_history_balance_history_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


CREATE SEQUENCE customer_device_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- 2. customer_devices
CREATE TABLE customer_devices (
    customer_device_key   INTEGER DEFAULT nextval('customer_device_key_seq'::regclass) NOT NULL,
    customer_key          INTEGER NOT NULL,
    device_key            INTEGER NOT NULL,
    is_primary            BOOLEAN,
    status                VARCHAR(15),
    first_seen            TIMESTAMP,
    last_seen             TIMESTAMP
);


-- 3. customer_risk_profile
CREATE TABLE customer_risk_profile (
    customer_key                 INTEGER NOT NULL,
    risk_score                   INTEGER DEFAULT 0 NOT NULL,
    risk_tier                    VARCHAR(15) DEFAULT 'Low'::VARCHAR NOT NULL,
    average_transaction_score    NUMERIC(5,2) DEFAULT 0 NOT NULL,
    high_risk_transaction_count  INTEGER DEFAULT 0 NOT NULL,
    fraud_event_count            INTEGER DEFAULT 0 NOT NULL,
    transactions_analyzed        INTEGER DEFAULT 0 NOT NULL,
    window_start                 TIMESTAMP NOT NULL,
    window_end                   TIMESTAMP NOT NULL,
    calculated_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_customer_risk_profile_average CHECK (((average_transaction_score >= (0)::NUMERIC) AND (average_transaction_score <= (100)::NUMERIC))),
    CONSTRAINT ck_customer_risk_profile_counts CHECK (((high_risk_transaction_count >= 0) AND (fraud_event_count >= 0) AND (transactions_analyzed >= 0))),
    CONSTRAINT ck_customer_risk_profile_score CHECK (((risk_score >= 0) AND (risk_score <= 100))),
    CONSTRAINT ck_customer_risk_profile_tier CHECK (((risk_tier)::TEXT = ANY ((ARRAY['Low'::VARCHAR, 'Medium'::VARCHAR, 'High'::VARCHAR, 'Critical'::VARCHAR])::TEXT[]))),
    CONSTRAINT ck_customer_risk_profile_window CHECK ((window_start <= window_end))
);


-- 4. customer_risk_profile_history
CREATE TABLE customer_risk_profile_history (
    profile_history_key             BIGINT NOT NULL,
    customer_key                    INTEGER NOT NULL,
    risk_score                      INTEGER NOT NULL,
    risk_tier                       VARCHAR(15) NOT NULL,
    average_transaction_score       NUMERIC(5,2) DEFAULT 0 NOT NULL,
    high_risk_transaction_count     INTEGER DEFAULT 0 NOT NULL,
    fraud_event_count               INTEGER DEFAULT 0 NOT NULL,
    transactions_analyzed           INTEGER DEFAULT 0 NOT NULL,
    window_start                    TIMESTAMP NOT NULL,
    window_end                      TIMESTAMP NOT NULL,
    snapshot_date                   DATE NOT NULL,
    snapshot_type                   VARCHAR(10) DEFAULT 'Daily'::VARCHAR NOT NULL,
    calculated_at                   TIMESTAMP NOT NULL,
    CONSTRAINT ck_customer_risk_profile_history_score CHECK (((risk_score >= 0) AND (risk_score <= 100))),
    CONSTRAINT ck_customer_risk_profile_history_tier CHECK (((risk_tier)::TEXT = ANY ((ARRAY['Low'::VARCHAR, 'Medium'::VARCHAR, 'High'::VARCHAR, 'Critical'::VARCHAR])::TEXT[]))),
    CONSTRAINT ck_customer_risk_profile_history_type CHECK (((snapshot_type)::TEXT = ANY ((ARRAY['Monthly'::VARCHAR, 'Daily'::VARCHAR])::TEXT[])))
);


ALTER TABLE customer_risk_profile_history ALTER COLUMN profile_history_key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME customer_risk_profile_history_profile_history_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


-- 5. dim_accounts
CREATE TABLE dim_accounts (
    account_key         INTEGER NOT NULL,
    customer_key        INTEGER NOT NULL,
    account_id          VARCHAR(20) NOT NULL,
    account_type        VARCHAR(20),
    balance             NUMERIC(18,2),
    daily_limit         NUMERIC(18,2),
    currency            VARCHAR(10),
    account_status      VARCHAR(20),
    created_at          TIMESTAMP,
    account_number      VARCHAR(10) NOT NULL,
    CONSTRAINT ck_dim_accounts_account_number_format CHECK (((account_number)::TEXT ~ '^77[0-9]{8}$'::TEXT))
);


-- 6. dim_counterparty
CREATE TABLE dim_counterparty (
    counterparty_key     INTEGER NOT NULL,
    account_id           VARCHAR(20) NOT NULL,
    name                 VARCHAR(150) NOT NULL,
    bank_name            VARCHAR(100) NOT NULL,
    counterparty_type    VARCHAR(20) NOT NULL,
    risk_score           INTEGER NOT NULL,
    risk_tier            VARCHAR(15) NOT NULL,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_dim_counterparty_risk CHECK (((((risk_tier)::TEXT = 'Low'::TEXT) AND ((risk_score >= 10) AND (risk_score <= 25))) OR (((risk_tier)::TEXT = 'Medium'::TEXT) AND ((risk_score >= 30) AND (risk_score <= 50))) OR (((risk_tier)::TEXT = 'High'::TEXT) AND ((risk_score >= 60) AND (risk_score <= 80))) OR (((risk_tier)::TEXT = 'Critical'::TEXT) AND ((risk_score >= 85) AND (risk_score <= 100))))),
    CONSTRAINT ck_dim_counterparty_type CHECK (((counterparty_type)::TEXT = ANY ((ARRAY['External'::VARCHAR, 'Employer'::VARCHAR])::TEXT[])))
);


ALTER TABLE dim_counterparty ALTER COLUMN counterparty_key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME dim_counterparty_counterparty_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


-- 7. dim_customers
CREATE TABLE dim_customers (
    customer_key         INTEGER NOT NULL,
    customer_id          VARCHAR(20) NOT NULL,
    full_name            VARCHAR(100) NOT NULL,
    email                VARCHAR(100),
    phone                VARCHAR(50),
    gender               VARCHAR(15),
    date_of_birth        DATE,
    state                VARCHAR(50),
    kyc_status           VARCHAR(20),
    location_key         INTEGER,
    segment              VARCHAR(25),
    preferred_channel    VARCHAR(50),
    created_at           TIMESTAMP,
    bvn                  VARCHAR(11) NOT NULL,
    age_group            VARCHAR(10),
    age_group_sort       INTEGER,
    CONSTRAINT ck_dim_customers_bvn_format CHECK (((bvn)::TEXT ~ '^999[0-9]{8}$'::TEXT))
);


-- 8. dim_date
CREATE TABLE dim_date (
    date_key               INTEGER NOT NULL,
    full_date              DATE NOT NULL,
    day_of_week            VARCHAR(15),
    week_number            INTEGER,
    month_number           INTEGER,
    month_name             VARCHAR(20),
    quarter_number         INTEGER,
    quarter_name           VARCHAR(10),
    year_number            INTEGER,
    is_weekend             BOOLEAN,
    is_month_end           BOOLEAN,
    year_month             VARCHAR(7) NOT NULL,
    month_start            DATE,
    month_short            VARCHAR(3),
    month_sort_label       VARCHAR(6) NOT NULL,
    day_abbr               VARCHAR(3),
    weekday_number         INTEGER,
    weekday_sort_label     VARCHAR(10)
);


CREATE SEQUENCE dim_device_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- 9. dim_device
CREATE TABLE dim_device (
    device_key             INTEGER DEFAULT nextval('dim_device_key_seq'::regclass) NOT NULL,
    device_id              VARCHAR(20) NOT NULL,
    device_type            VARCHAR(20),
    operating_system       VARCHAR(50),
    device_brand           VARCHAR(50),
    device_fingerprint     VARCHAR(255),
    ip_address             VARCHAR(50),
    first_seen             TIMESTAMP
);


-- 10. dim_location
CREATE TABLE dim_location (
    location_key         INTEGER NOT NULL,
    location_id          VARCHAR(20) NOT NULL,
    country              VARCHAR(20),
    state                VARCHAR(50),
    geopolitical_zone    VARCHAR(50),
    risk_level           VARCHAR(15)
);


-- 11. dim_merchants
CREATE TABLE dim_merchants (
    merchant_key         INTEGER NOT NULL,
    merchant_id          VARCHAR(20) NOT NULL,
    merchant_name        VARCHAR(100),
    merchant_category    VARCHAR(50),
    country              VARCHAR(20),
    state                VARCHAR(20),
    status               VARCHAR(20),
    risk_level           VARCHAR(15),
    risk_score           INTEGER NOT NULL,
    CONSTRAINT ck_merchants_risk_score CHECK (((((risk_level)::TEXT = 'Low'::TEXT) AND ((risk_score >= 10) AND (risk_score <= 25))) OR (((risk_level)::TEXT = 'Medium'::TEXT) AND ((risk_score >= 30) AND (risk_score <= 50))) OR (((risk_level)::TEXT = 'High'::TEXT) AND ((risk_score >= 60) AND (risk_score <= 80))) OR (((risk_level)::TEXT = 'Critical'::TEXT) AND ((risk_score >= 85) AND (risk_score <= 100)))))
);


-- 12. dim_risk_tier
CREATE TABLE dim_risk_tier (
    risk_tier     VARCHAR(20) NOT NULL,
    sort_order    INTEGER NOT NULL
);


-- 13. dim_time
CREATE TABLE dim_time (
    time_key       SMALLINT NOT NULL,
    hour_number    SMALLINT NOT NULL,
    hour_label     VARCHAR(5) NOT NULL,
    time_period    VARCHAR(20) NOT NULL,
    CONSTRAINT chk_dim_time_hour CHECK (((hour_number >= 0) AND (hour_number <= 23)))
);


-- 14. fact_fraud_events
CREATE TABLE fact_fraud_events (
    fraud_id             INTEGER NOT NULL,
    transaction_key      INTEGER NOT NULL,
    customer_key         INTEGER NOT NULL,
    alert_key            INTEGER,
    amount_flagged       NUMERIC(18,2),
    fraud_type           VARCHAR(50),
    fraud_score          INTEGER,
    decision_taken       VARCHAR(50),
    rule_triggered       VARCHAR(50),
    detected_at          TIMESTAMP
);


ALTER TABLE fact_fraud_events ALTER COLUMN fraud_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME fact_fraud_events_fraud_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


-- 15. fact_risk_scores
CREATE TABLE fact_risk_scores (
    score_id                 INTEGER NOT NULL,
    transaction_key          INTEGER NOT NULL,
    customer_key             INTEGER NOT NULL,
    risk_score               INTEGER,
    risk_tier                VARCHAR(15),
    calculated_at            TIMESTAMP,
    model_version            VARCHAR(5),
    velocity_flag            BOOLEAN,
    amount_flag              BOOLEAN,
    location_flag            BOOLEAN,
    device_flag              BOOLEAN,
    off_hour_flag            BOOLEAN,
    merchant_flag            BOOLEAN,
    inflow_flag              BOOLEAN,
    hard_rule_triggered      VARCHAR(100),
    CONSTRAINT ck_risk_scores_tier CHECK (((risk_tier)::TEXT = ANY ((ARRAY['Low'::VARCHAR, 'Medium'::VARCHAR, 'High'::VARCHAR, 'Critical'::VARCHAR])::TEXT[])))
);


ALTER TABLE fact_risk_scores ALTER COLUMN score_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME fact_risk_scores_score_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


CREATE SEQUENCE fact_transaction_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- 16. fact_transactions
CREATE TABLE fact_transactions (
    transaction_key             INTEGER DEFAULT nextval('fact_transaction_key_seq'::regclass) NOT NULL,
    customer_key                INTEGER NOT NULL,
    account_key                 INTEGER NOT NULL,
    merchant_key                INTEGER,
    device_key                  INTEGER NOT NULL,
    location_key                INTEGER NOT NULL,
    date_key                    INTEGER NOT NULL,
    transaction_id              VARCHAR(20) NOT NULL,
    amount                      NUMERIC(18,2) NOT NULL,
    transaction_type            VARCHAR(25) NOT NULL,
    transaction_datetime        TIMESTAMP NOT NULL,
    channel                     VARCHAR(50) NOT NULL,
    transaction_status          VARCHAR(20) NOT NULL,
    failure_reason              VARCHAR(100),
    transaction_direction       VARCHAR(20) NOT NULL,
    counterparty_account_id     VARCHAR(20),
    counterparty_type           VARCHAR(20),
    counterparty_risk_score     INTEGER,
    counterparty_customer_key   INTEGER,
    counterparty_key            INTEGER,
    transaction_narration       VARCHAR(255),
    time_key                    SMALLINT GENERATED ALWAYS AS (((EXTRACT(hour FROM transaction_datetime))::SMALLINT + 1)) STORED,
    CONSTRAINT ck_transactions_amount_positive CHECK ((amount > (0)::NUMERIC)),
    CONSTRAINT ck_transactions_counterparty_relationship CHECK (((((counterparty_type)::TEXT = 'Customer'::TEXT) AND (counterparty_customer_key IS NOT NULL) AND (counterparty_key IS NULL) AND (merchant_key IS NULL)) OR (((counterparty_type)::TEXT = ANY ((ARRAY['External'::VARCHAR, 'Employer'::VARCHAR])::TEXT[])) AND (counterparty_customer_key IS NULL) AND (counterparty_key IS NOT NULL) AND (merchant_key IS NULL)) OR (((counterparty_type)::TEXT = 'Merchant'::TEXT) AND (counterparty_customer_key IS NULL) AND (counterparty_key IS NULL) AND (merchant_key IS NOT NULL)))),
    CONSTRAINT ck_transactions_counterparty_type CHECK (((counterparty_type)::TEXT = ANY ((ARRAY['External'::VARCHAR, 'Employer'::VARCHAR, 'Merchant'::VARCHAR, 'Customer'::VARCHAR])::TEXT[]))),
    CONSTRAINT ck_transactions_direction CHECK (((transaction_direction)::TEXT = ANY ((ARRAY['INFLOW'::VARCHAR, 'OUTFLOW'::VARCHAR])::TEXT[]))),
    CONSTRAINT ck_transactions_status CHECK (((transaction_status)::TEXT = ANY ((ARRAY['Success'::VARCHAR, 'Failed'::VARCHAR])::TEXT[])))
);


-- 17. fraud_alerts
CREATE TABLE fraud_alerts (
    alert_key               INTEGER NOT NULL,
    transaction_key         INTEGER NOT NULL,
    customer_key            INTEGER NOT NULL,
    alert_reason            VARCHAR(225),
    alert_severity          VARCHAR(50),
    risk_score              INTEGER,
    estimated_exposure      NUMERIC(18,2),
    alert_status            VARCHAR(20),
    created_at              TIMESTAMP,
    resolved_at             TIMESTAMP,
    resolution_comment      VARCHAR(225),
    resolution              VARCHAR(30),
    assigned_to             VARCHAR(100),
    alert_id                VARCHAR(20) NOT NULL,
    CONSTRAINT ck_fraud_alerts_alert_id_format CHECK (((alert_id)::TEXT ~ '^ALRT_[0-9]{6,}$'::TEXT)),
    CONSTRAINT ck_fraud_alerts_resolution CHECK (((resolution IS NULL) OR ((resolution)::TEXT = ANY ((ARRAY['Confirmed Fraud'::VARCHAR, 'False Positive'::VARCHAR])::TEXT[])))),
    CONSTRAINT ck_fraud_alerts_status CHECK (((alert_status)::TEXT = ANY ((ARRAY['Open'::VARCHAR, 'Investigating'::VARCHAR, 'Escalated'::VARCHAR, 'Resolved'::VARCHAR])::TEXT[])))
);


ALTER TABLE fraud_alerts ALTER COLUMN alert_key ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME fraud_alerts_alert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


-- 18. rejected_transactions
CREATE TABLE rejected_transactions (
    rejection_key               INTEGER NOT NULL,
    customer_key                INTEGER NOT NULL,
    account_key                 INTEGER NOT NULL,
    merchant_key                INTEGER,
    amount                      NUMERIC(18,2) NOT NULL,
    transaction_type            VARCHAR(25) NOT NULL,
    transaction_datetime        TIMESTAMP NOT NULL,
    channel                     VARCHAR(50) NOT NULL,
    transaction_direction       VARCHAR(20) NOT NULL,
    rejection_reason            VARCHAR(100) NOT NULL,
    attempted_at                TIMESTAMP NOT NULL,
    device_key                  INTEGER,
    location_key                INTEGER,
    counterparty_customer_key   INTEGER,
    counterparty_key            INTEGER,
    counterparty_account_id     VARCHAR(30),
    counterparty_type           VARCHAR(20),
    counterparty_risk_score     INTEGER
);


ALTER TABLE rejected_transactions ALTER COLUMN rejection_key ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME rejected_transactions_rejection_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


ALTER TABLE ONLY dim_risk_tier
    ADD CONSTRAINT dim_risk_tier_pkey PRIMARY KEY (risk_tier);


ALTER TABLE ONLY dim_time
    ADD CONSTRAINT dim_time_hour_number_key UNIQUE (hour_number);


ALTER TABLE ONLY dim_time
    ADD CONSTRAINT dim_time_pkey PRIMARY KEY (time_key);


ALTER TABLE ONLY fact_fraud_events
    ADD CONSTRAINT fact_fraud_events_pkey PRIMARY KEY (fraud_id);


ALTER TABLE ONLY fact_risk_scores
    ADD CONSTRAINT fact_risk_scores_pkey PRIMARY KEY (score_id);


ALTER TABLE ONLY fraud_alerts
    ADD CONSTRAINT fraud_alerts_pkey PRIMARY KEY (alert_key);


ALTER TABLE ONLY account_balance_history
    ADD CONSTRAINT pk_account_balance_history PRIMARY KEY (balance_history_key);


ALTER TABLE ONLY customer_devices
    ADD CONSTRAINT pk_customer_devices PRIMARY KEY (customer_device_key);


ALTER TABLE ONLY customer_risk_profile
    ADD CONSTRAINT pk_customer_risk_profile PRIMARY KEY (customer_key);


ALTER TABLE ONLY customer_risk_profile_history
    ADD CONSTRAINT pk_customer_risk_profile_history PRIMARY KEY (profile_history_key);


ALTER TABLE ONLY dim_accounts
    ADD CONSTRAINT pk_dim_accounts PRIMARY KEY (account_key);


ALTER TABLE ONLY dim_counterparty
    ADD CONSTRAINT pk_dim_counterparty PRIMARY KEY (counterparty_key);


ALTER TABLE ONLY dim_customers
    ADD CONSTRAINT pk_dim_customers PRIMARY KEY (customer_key);


ALTER TABLE ONLY dim_date
    ADD CONSTRAINT pk_dim_date PRIMARY KEY (date_key);


ALTER TABLE ONLY dim_device
    ADD CONSTRAINT pk_dim_device PRIMARY KEY (device_key);


ALTER TABLE ONLY dim_location
    ADD CONSTRAINT pk_dim_location PRIMARY KEY (location_key);


ALTER TABLE ONLY dim_merchants
    ADD CONSTRAINT pk_dim_merchants PRIMARY KEY (merchant_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT pk_fact_transactions PRIMARY KEY (transaction_key);


ALTER TABLE ONLY rejected_transactions
    ADD CONSTRAINT rejected_transactions_pkey PRIMARY KEY (rejection_key);


ALTER TABLE ONLY customer_risk_profile_history
    ADD CONSTRAINT uq_customer_risk_profile_history_day UNIQUE (customer_key, snapshot_date);


ALTER TABLE ONLY dim_counterparty
    ADD CONSTRAINT uq_dim_counterparty_account_id UNIQUE (account_id);


ALTER TABLE ONLY dim_counterparty
    ADD CONSTRAINT uq_dim_counterparty_name UNIQUE (name);


ALTER TABLE ONLY fraud_alerts
    ADD CONSTRAINT uq_fraud_alerts_alert_id UNIQUE (alert_id);


CREATE INDEX idx_fact_transactions_time_key ON fact_transactions USING btree (time_key);


CREATE INDEX ix_customer_risk_history_snapshot_date ON customer_risk_profile_history USING btree (snapshot_date);


CREATE INDEX ix_customer_risk_history_tier_date ON customer_risk_profile_history USING btree (risk_tier, snapshot_date);


CREATE INDEX ix_customer_risk_profile_calculated_at ON customer_risk_profile USING btree (calculated_at);


CREATE INDEX ix_customer_risk_profile_tier ON customer_risk_profile USING btree (risk_tier);


CREATE INDEX ix_dim_counterparty_risk_tier ON dim_counterparty USING btree (risk_tier);


CREATE INDEX ix_dim_counterparty_type ON dim_counterparty USING btree (counterparty_type);


CREATE INDEX ix_fact_risk_scores_tier ON fact_risk_scores USING btree (risk_tier);


CREATE INDEX ix_fact_transactions_account_datetime ON fact_transactions USING btree (account_key, transaction_datetime);


CREATE INDEX ix_fact_transactions_customer_datetime ON fact_transactions USING btree (customer_key, transaction_datetime);


CREATE INDEX ix_fact_transactions_device ON fact_transactions USING btree (device_key);


CREATE INDEX ix_fact_transactions_location ON fact_transactions USING btree (location_key);


CREATE INDEX ix_fraud_alerts_status ON fraud_alerts USING btree (alert_status);


CREATE INDEX ix_fraud_alerts_transaction_key ON fraud_alerts USING btree (transaction_key);


CREATE INDEX ix_fraud_events_customer_detected ON fact_fraud_events USING btree (customer_key, detected_at);


CREATE INDEX ix_risk_scores_customer_calculated ON fact_risk_scores USING btree (customer_key, calculated_at);


CREATE INDEX ix_transactions_counterparty ON fact_transactions USING btree (counterparty_key);


CREATE INDEX ix_transactions_counterparty_customer ON fact_transactions USING btree (counterparty_customer_key);


CREATE UNIQUE INDEX uq_customer_devices_customer_device ON customer_devices USING btree (customer_key, device_key);


CREATE UNIQUE INDEX uq_dim_accounts_account_number ON dim_accounts USING btree (account_number);


CREATE UNIQUE INDEX uq_dim_customers_bvn ON dim_customers USING btree (bvn);


CREATE UNIQUE INDEX uq_dim_device_device_id ON dim_device USING btree (device_id);


CREATE UNIQUE INDEX uq_dim_device_fingerprint ON dim_device USING btree (device_fingerprint) WHERE (device_fingerprint IS NOT NULL);


CREATE UNIQUE INDEX uq_fact_fraud_events_transaction_key ON fact_fraud_events USING btree (transaction_key);


CREATE UNIQUE INDEX uq_fact_risk_scores_transaction_key ON fact_risk_scores USING btree (transaction_key);


CREATE UNIQUE INDEX uq_fact_transactions_transaction_id ON fact_transactions USING btree (transaction_id);


CREATE UNIQUE INDEX uq_fraud_alerts_transaction_key ON fraud_alerts USING btree (transaction_key);


ALTER TABLE ONLY dim_accounts
    ADD CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fraud_alerts
    ADD CONSTRAINT fk_alerts_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fraud_alerts
    ADD CONSTRAINT fk_alerts_transaction FOREIGN KEY (transaction_key) REFERENCES fact_transactions(transaction_key) ON DELETE CASCADE;


ALTER TABLE ONLY account_balance_history
    ADD CONSTRAINT fk_balance_history_account FOREIGN KEY (account_key) REFERENCES dim_accounts(account_key);


ALTER TABLE ONLY account_balance_history
    ADD CONSTRAINT fk_balance_history_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY account_balance_history
    ADD CONSTRAINT fk_balance_history_transaction FOREIGN KEY (transaction_key) REFERENCES fact_transactions(transaction_key) ON DELETE CASCADE;


ALTER TABLE ONLY customer_risk_profile
    ADD CONSTRAINT fk_customer_risk_profile_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key) ON DELETE CASCADE;


ALTER TABLE ONLY customer_risk_profile_history
    ADD CONSTRAINT fk_customer_risk_profile_history_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY customer_devices
    ADD CONSTRAINT fk_customers_key FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY dim_customers
    ADD CONSTRAINT fk_customers_location FOREIGN KEY (location_key) REFERENCES dim_location(location_key);


ALTER TABLE ONLY customer_devices
    ADD CONSTRAINT fk_devices_key FOREIGN KEY (device_key) REFERENCES dim_device(device_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_fact_transactions_time FOREIGN KEY (time_key) REFERENCES dim_time(time_key);


ALTER TABLE ONLY fact_fraud_events
    ADD CONSTRAINT fk_fraud_events_alert FOREIGN KEY (alert_key) REFERENCES fraud_alerts(alert_key);


ALTER TABLE ONLY fact_fraud_events
    ADD CONSTRAINT fk_fraud_events_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fact_fraud_events
    ADD CONSTRAINT fk_fraud_events_transaction FOREIGN KEY (transaction_key) REFERENCES fact_transactions(transaction_key) ON DELETE CASCADE;


ALTER TABLE ONLY fact_risk_scores
    ADD CONSTRAINT fk_risk_scores_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fact_risk_scores
    ADD CONSTRAINT fk_risk_scores_transaction FOREIGN KEY (transaction_key) REFERENCES fact_transactions(transaction_key) ON DELETE CASCADE;


ALTER TABLE ONLY rejected_transactions
    ADD CONSTRAINT fk_rt_account FOREIGN KEY (account_key) REFERENCES dim_accounts(account_key);


ALTER TABLE ONLY rejected_transactions
    ADD CONSTRAINT fk_rt_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY rejected_transactions
    ADD CONSTRAINT fk_rt_merchant FOREIGN KEY (merchant_key) REFERENCES dim_merchants(merchant_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_account FOREIGN KEY (account_key) REFERENCES dim_accounts(account_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_counterparty FOREIGN KEY (counterparty_key) REFERENCES dim_counterparty(counterparty_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_counterparty_customer FOREIGN KEY (counterparty_customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_customer FOREIGN KEY (customer_key) REFERENCES dim_customers(customer_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_date FOREIGN KEY (date_key) REFERENCES dim_date(date_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_device FOREIGN KEY (device_key) REFERENCES dim_device(device_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_location FOREIGN KEY (location_key) REFERENCES dim_location(location_key);


ALTER TABLE ONLY fact_transactions
    ADD CONSTRAINT fk_transactions_merchant FOREIGN KEY (merchant_key) REFERENCES dim_merchants(merchant_key);



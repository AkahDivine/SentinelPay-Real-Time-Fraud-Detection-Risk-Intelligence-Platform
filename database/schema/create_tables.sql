-- =============================================================
-- SentinelPay — DDL Script
-- Database: sentinelpay_db
-- Author: Akah Chijioke Divine
-- Version: 1.0
-- =============================================================


DROP TABLE IF EXISTS fact_fraud_events CASCADE;
DROP TABLE IF EXISTS fraud_alerts CASCADE;
DROP TABLE IF EXISTS fact_risk_scores CASCADE;
DROP TABLE IF EXISTS fact_transactions CASCADE;
DROP TABLE IF EXISTS dim_accounts CASCADE;
DROP TABLE IF EXISTS dim_merchants CASCADE;
DROP TABLE IF EXISTS dim_customers CASCADE;
DROP TABLE IF EXISTS dim_device CASCADE;
DROP TABLE IF EXISTS dim_location CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;

-- 1. dim_date
CREATE TABLE dim_date (
    date_key          INTEGER      NOT NULL,
    full_date         DATE         NOT NULL,
    day_of_week       VARCHAR(15),
    week_number       INTEGER,
    month_number      INTEGER,
    month_name        VARCHAR(20),
    quarter_number    INTEGER,
    quarter_name      VARCHAR(10),
    year_number       INTEGER,
    is_weekend        BOOLEAN,
    is_month_end      BOOLEAN,

    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);


-- 2. dim_location
CREATE TABLE dim_location (
    location_key          INTEGER      NOT NULL,
    location_id           VARCHAR(20)  NOT NULL,
    country               VARCHAR(20),
    state                 VARCHAR(50),
    geopolitical_zone     VARCHAR(50),
    risk_level            VARCHAR(15),

    CONSTRAINT pk_dim_location PRIMARY KEY (location_key)
);


-- 3. dim_device
CREATE TABLE dim_device (
    device_key            INTEGER      NOT NULL,
    device_id             VARCHAR(20)  NOT NULL,
    device_type           VARCHAR(20),
    device_fingerprint    VARCHAR(255),
    ip_address            VARCHAR(50),
    first_seen            TIMESTAMP,

    CONSTRAINT pk_dim_device PRIMARY KEY (device_key)
);


-- 4. dim_customers
CREATE TABLE dim_customers (
    customer_key          INTEGER      NOT NULL,
    customer_id           VARCHAR(20)  NOT NULL,
    full_name             VARCHAR(100) NOT NULL,
    email                 VARCHAR(100),
    phone                 VARCHAR(50),
    gender                VARCHAR(15),
    date_of_birth         DATE,
    state                 VARCHAR(50),
    kyc_status            VARCHAR(20),
    location_key          INTEGER,
    segment               VARCHAR(25),
    preferred_channel     VARCHAR(50),
    created_at            TIMESTAMP,

    CONSTRAINT pk_dim_customers PRIMARY KEY (customer_key),
    CONSTRAINT fk_customers_location FOREIGN KEY (location_key)
        REFERENCES dim_location (location_key)
);

-- 5. customer_devices
CREATE TABLE customer_devices (
	customer_device_key		INTEGER NOT NULL,
	customer_key 			INTEGER NOT NULL,
	device_key				INTEGER NOT NULL,
	is_primary				BOOLEAN,
	status					VARCHAR(15),
	first_seen				TIMESTAMP,
	last_seen				TIMESTAMP,

	CONSTRAINT pk_customer_devices PRIMARY KEY (customer_device_key),
	CONSTRAINT fk_customers_key FOREIGN KEY (customer_key)
			REFERENCES dim_customers (customer_key),
	CONSTRAINT fk_devices_key FOREIGN KEY (device_key)
			REFERENCES dim_device (device_key)
);

-- 6. dim_merchants
CREATE TABLE dim_merchants (
    merchant_key          INTEGER      NOT NULL,
    merchant_id           VARCHAR(20)  NOT NULL,
    merchant_name         VARCHAR(100),
    merchant_category     VARCHAR(50),
    country               VARCHAR(20),
    state                 VARCHAR(20),
    status                VARCHAR(20),
    risk_level            VARCHAR(15),

    CONSTRAINT pk_dim_merchants PRIMARY KEY (merchant_key)
);


-- 7. dim_accounts
CREATE TABLE dim_accounts (
    account_key           INTEGER      NOT NULL,
    customer_key          INTEGER      NOT NULL,
    account_id            VARCHAR(20)  NOT NULL,
    account_type          VARCHAR(20),
    balance               NUMERIC(18,2),
    daily_limit           NUMERIC(18,2),
    currency              VARCHAR(10),
    account_status        VARCHAR(20),
    created_at            TIMESTAMP,

    CONSTRAINT pk_dim_accounts PRIMARY KEY (account_key),
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers (customer_key)
);


-- 8. fact_transactions
CREATE TABLE fact_transactions (
    transaction_key           INTEGER      NOT NULL,
    customer_key              INTEGER      NOT NULL,
    account_key               INTEGER      NOT NULL,
    merchant_key              INTEGER,
    device_key                INTEGER      NOT NULL,
    location_key              INTEGER      NOT NULL,
    date_key                  INTEGER      NOT NULL,
    transaction_id            VARCHAR(20)  NOT NULL,
    amount                    NUMERIC(18,2)NOT NULL,
    transaction_type          VARCHAR(25)  NOT NULL,
    transaction_datetime      TIMESTAMP    NOT NULL,
    channel                   VARCHAR(50)  NOT NULL,
    transaction_status        VARCHAR(20)  NOT NULL,
	failure_reason            VARCHAR(100),
    transaction_direction     VARCHAR(20)  NOT NULL,
    counterparty_account_id   VARCHAR(20),
    counterparty_type         VARCHAR(20),
    counterparty_risk_score   INTEGER,

    CONSTRAINT pk_fact_transactions PRIMARY KEY (transaction_key),
    CONSTRAINT fk_transactions_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers (customer_key),
    CONSTRAINT fk_transactions_account FOREIGN KEY (account_key)
        REFERENCES dim_accounts (account_key),
    CONSTRAINT fk_transactions_merchant FOREIGN KEY (merchant_key)
        REFERENCES dim_merchants (merchant_key),
    CONSTRAINT fk_transactions_device FOREIGN KEY (device_key)
        REFERENCES dim_device (device_key),
    CONSTRAINT fk_transactions_location FOREIGN KEY (location_key)
        REFERENCES dim_location (location_key),
    CONSTRAINT fk_transactions_date FOREIGN KEY (date_key)
        REFERENCES dim_date (date_key)
);


-- 9. fact_risk_scores
CREATE TABLE fact_risk_scores (
    score_id 			  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_key       INTEGER      NOT NULL,
    customer_key          INTEGER      NOT NULL,
    risk_score            INTEGER,
    risk_tier             VARCHAR(15),
    calculated_at         TIMESTAMP,
    model_version         VARCHAR(5),
    velocity_flag         BOOLEAN,
    amount_flag           BOOLEAN,
    location_flag         BOOLEAN,
    device_flag           BOOLEAN,
    off_hour_flag         BOOLEAN,
    merchant_flag         BOOLEAN,
    inflow_flag           BOOLEAN,

    CONSTRAINT fk_risk_scores_transaction FOREIGN KEY (transaction_key)
        REFERENCES fact_transactions (transaction_key),
    CONSTRAINT fk_risk_scores_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers (customer_key)
);

-- 10. fraud_alerts
CREATE TABLE fraud_alerts (
    alert_id			  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_key       INTEGER      NOT NULL,
    customer_key          INTEGER      NOT NULL,
    alert_reason          VARCHAR(225),
    alert_severity        VARCHAR(50),
    risk_score            INTEGER,
    estimated_exposure    NUMERIC(18,2),
    alert_status          VARCHAR(20),
    created_at            TIMESTAMP,
    resolved_at           TIMESTAMP,
	resolution_comment    VARCHAR(225),

    CONSTRAINT fk_alerts_transaction FOREIGN KEY (transaction_key)
        REFERENCES fact_transactions (transaction_key),
    CONSTRAINT fk_alerts_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers (customer_key)
);


-- 11. fact_fraud_events
CREATE TABLE fact_fraud_events (
    fraud_id 			  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_key       INTEGER      NOT NULL,
    customer_key          INTEGER      NOT NULL,
    alert_id              INTEGER,
    amount_flagged        NUMERIC(18,2),
    fraud_type            VARCHAR(50),
    fraud_score           INTEGER,
    decision_taken        VARCHAR(50),
    rule_triggered        VARCHAR(50),
    detected_at           TIMESTAMP,
    resolved_at           TIMESTAMP,

    CONSTRAINT fk_fraud_events_transaction FOREIGN KEY (transaction_key)
        REFERENCES fact_transactions (transaction_key),
    CONSTRAINT fk_fraud_events_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers (customer_key),
	CONSTRAINT fk_fraud_events_alert FOREIGN KEY (alert_id)
        REFERENCES fraud_alerts (alert_id)
);


-- 12. account_balance_history
CREATE TABLE account_balance_history (
    history_key       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_key       INTEGER       NOT NULL,
    customer_key      INTEGER       NOT NULL,
    transaction_key   INTEGER,
    movement_type     VARCHAR(10)   NOT NULL,  
    amount            NUMERIC(18,2) NOT NULL,
    balance_before    NUMERIC(18,2) NOT NULL,
    balance_after     NUMERIC(18,2) NOT NULL,
    recorded_at       TIMESTAMP     NOT NULL,
 
    CONSTRAINT fk_abh_account FOREIGN KEY (account_key)
        REFERENCES dim_accounts(account_key),
    CONSTRAINT fk_abh_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers(customer_key)
);


-- 13. rejected_transactions
CREATE TABLE rejected_transactions (
    rejection_key        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_key          INTEGER		  NOT NULL,
    account_key           INTEGER		  NOT NULL,
    merchant_key          INTEGER,
    amount                NUMERIC(18,2)   NOT NULL,
    transaction_type      VARCHAR(25)     NOT NULL,
    transaction_datetime  TIMESTAMP       NOT NULL,
    channel               VARCHAR(50)     NOT NULL,
    transaction_direction VARCHAR(20)     NOT NULL,
    rejection_reason      VARCHAR(100)	  NOT NULL,
    attempted_at          TIMESTAMP       NOT NULL,
 
    CONSTRAINT fk_rt_customer FOREIGN KEY (customer_key)
        REFERENCES dim_customers(customer_key),
    CONSTRAINT fk_rt_account FOREIGN KEY (account_key)
        REFERENCES dim_accounts(account_key),
    CONSTRAINT fk_rt_merchant FOREIGN KEY (merchant_key)
    	REFERENCES dim_merchants(merchant_key)
);


 



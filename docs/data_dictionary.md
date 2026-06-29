# SentinelPay — Data Dictionary
### Real-Time Fraud Detection & Risk Intelligence Platform
**Version:** 1.0  
**Author:** Akah Chijioke Divine  
**Last Updated:** June 2026  

---

## Overview

This data dictionary documents every table and column in the SentinelPay PostgreSQL database. The schema follows a star schema design with `fact_` and `dim_` naming conventions, separating transactional events (facts) from descriptive context (dimensions). All tables are Nigeria-specific and calibrated to Nigerian fintech transaction patterns.

**Database:** PostgreSQL  
**Schema type:** Star schema  
**Total tables:** 10 (3 fact, 6 dimension, 1 supporting)

---

## Table Index

| # | Table | Type | Description |
|---|---|---|---|
| 1 | `dim_date` | Dimension | Calendar attributes for time-intelligence analysis |
| 2 | `dim_location` | Dimension | Nigerian state and geopolitical zone risk classification |
| 3 | `dim_device` | Dimension | Customer device fingerprints and metadata |
| 4 | `dim_customers` | Dimension | Customer profiles and KYC information |
| 5 | `dim_merchants` | Dimension | Merchant profiles and risk classification |
| 6 | `dim_accounts` | Dimension | Account-level attributes and status |
| 7 | `fact_transactions` | Fact | Core transactional event table |
| 8 | `fact_risk_scores` | Fact | Risk scoring output per transaction |
| 9 | `fact_fraud_events` | Fact | Detected fraud event records |
| 10 | `fraud_alerts` | Supporting | Operational alert records for fraud team |

---

## Dimension Tables

---

### 1. `dim_date`

**Description:** Date dimension table supporting all time-intelligence analysis in Power BI. Pre-calculates calendar attributes so queries never need to derive month, quarter, or weekend status from raw timestamps. Covers January 2023 to December 2024 for historical analysis plus live streaming period.

**Relationships:** One-to-many with `fact_transactions` via `date_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `date_key` | integer | NOT NULL | Surrogate primary key — sequential integer representing each unique date | `20230101` |
| `full_date` | date | NOT NULL | The actual calendar date | `2023-01-01` |
| `day_of_week` | varchar(15) | NULL | Full name of the day | `Sunday` |
| `week_number` | integer | NULL | ISO week number within the year (1–53) | `1` |
| `month_number` | integer | NULL | Numeric month (1–12) | `1` |
| `month_name` | varchar(20) | NULL | Full name of the month | `January` |
| `quarter_number` | integer | NULL | Fiscal quarter number (1–4) | `1` |
| `quarter_name` | varchar(10) | NULL | Quarter label | `Q1` |
| `year_number` | integer | NULL | Four-digit calendar year | `2023` |
| `is_weekend` | boolean | NULL | TRUE if Saturday or Sunday — used for fraud pattern analysis | `TRUE` |
| `is_month_end` | boolean | NULL | TRUE if last day of the month — used for salary period fraud detection | `FALSE` |

---

### 2. `dim_location`

**Description:** Nigerian location dimension classifying all 36 states plus FCT by geopolitical zone and fraud risk level. Risk levels are based on documented Nigerian fintech fraud concentration patterns. Used by the risk scoring engine to apply state-level risk bonuses to transaction scores.

**Relationships:** One-to-many with `fact_transactions` via `location_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `location_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `location_id` | varchar(20) | NOT NULL | Business identifier for the location record | `LOC_001` |
| `country` | varchar(20) | NULL | Country name — always Nigeria for this system | `Nigeria` |
| `state` | varchar(50) | NULL | Nigerian state name including FCT | `Lagos` |
| `geopolitical_zone` | varchar(50) | NULL | One of six Nigerian geopolitical zones | `South West` |
| `risk_level` | varchar(15) | NULL | State fraud risk classification — High, Medium, or Low | `High` |

**Risk level classifications:**

| Risk level | States |
|---|---|
| High | Lagos, Rivers, Delta, Anambra |
| Medium | FCT (Abuja), Kano, Oyo, Kaduna |
| Low | All remaining 29 states |

**Geopolitical zones:**

| Zone | States included |
|---|---|
| South West | Lagos, Ogun, Oyo, Osun, Ondo, Ekiti |
| South South | Rivers, Delta, Bayelsa, Cross River, Akwa Ibom, Edo |
| South East | Anambra, Imo, Abia, Enugu, Ebonyi |
| North Central | FCT, Kogi, Benue, Nasarawa, Plateau, Niger, Kwara |
| North West | Kano, Kaduna, Katsina, Sokoto, Kebbi, Zamfara, Jigawa |
| North East | Borno, Yobe, Adamawa, Taraba, Bauchi, Gombe |

---

### 3. `dim_device`

**Description:** Device dimension storing fingerprints and metadata for every unique device used to perform transactions. The scoring engine compares current transaction device fingerprints against the 60-day known device list per customer to detect device anomalies — a primary account takeover signal.

**Relationships:** One-to-many with `fact_transactions` via `device_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `device_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `device_id` | varchar(20) | NOT NULL | Business identifier for the device | `DEV_001` |
| `device_type` | varchar(20) | NULL | Category of device used for the transaction | `Mobile` |
| `device_fingerprint` | varchar(255) | NULL | Unique cryptographic fingerprint identifying the specific device — used for anomaly detection | `a3f9c2e1b7d4...` |
| `ip_address` | varchar(50) | NULL | IP address associated with the transaction — new IP combined with new device triggers elevated scoring | `102.89.45.231` |
| `first_seen` | timestamp | NULL | Timestamp when this device was first recorded in the system — used to identify brand new devices | `2023-03-15 09:22:11` |

**Device type values:** Mobile, Web, POS, USSD, Desktop

---

### 4. `dim_customers`

**Description:** Customer profile dimension containing KYC information, demographic data, account segmentation, and location references. Customer home state is used as the baseline for location anomaly detection. Segment and preferred channel support behavioural profiling in Power BI.

**Relationships:**  
- One-to-many with `fact_transactions` via `customer_key`  
- One-to-many with `dim_accounts` via `customer_key`  
- One-to-many with `fact_risk_scores` via `customer_key`  
- One-to-many with `fact_fraud_events` via `customer_key`  
- One-to-many with `fraud_alerts` via `customer_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `customer_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `customer_id` | varchar(20) | NOT NULL | Business identifier for the customer | `CUST_001` |
| `full_name` | varchar(100) | NOT NULL | Customer full name — generated using Nigerian name patterns | `Emeka Okonkwo` |
| `email` | varchar(100) | NULL | Customer email address | `emeka.okonkwo@gmail.com` |
| `phone` | varchar(50) | NULL | Nigerian phone number | `+2348012345678` |
| `country` | varchar(20) | NULL | Country of residence — always Nigeria | `Nigeria` |
| `gender` | varchar(15) | NULL | Customer gender | `Male` |
| `date_of_birth` | date | NULL | Customer date of birth | `1990-06-14` |
| `state` | varchar(50) | NULL | Nigerian home state — primary anchor for location anomaly detection | `Lagos` |
| `kyc_status` | varchar(20) | NULL | KYC verification status — unverified customers carry higher baseline risk | `Verified` |
| `location_key` | integer | NULL | Foreign key reference to `dim_location` | `1` |
| `segment` | varchar(25) | NULL | Customer risk and value segment | `Premium` |
| `preferred_channel` | varchar(50) | NULL | Most frequently used transaction channel | `Mobile` |
| `created_at` | timestamp | NULL | Timestamp when customer account was created in the system | `2023-01-10 08:00:00` |

**KYC status values:** Verified, Unverified, Pending, Suspended  
**Segment values:** Premium, Standard, Basic, High-Risk  
**Preferred channel values:** Mobile, Web, POS, USSD, Bank Transfer

---

### 5. `dim_merchants`

**Description:** Merchant profile dimension classifying all merchants by category and risk level. Merchant risk level directly feeds into the merchant risk scoring signal. High-risk categories (crypto exchanges, betting platforms) carry significantly elevated scores. Used for both outflow transaction analysis and counterparty risk assignment.

**Relationships:** One-to-many with `fact_transactions` via `merchant_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `merchant_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `merchant_id` | varchar(20) | NOT NULL | Business identifier for the merchant | `MERCH_001` |
| `merchant_name` | varchar(100) | NULL | Trading name of the merchant | `QuickMart Superstore` |
| `merchant_category` | varchar(50) | NULL | Business category of the merchant — determines base risk classification | `Supermarket` |
| `country` | varchar(20) | NULL | Country where merchant is registered — always Nigeria | `Nigeria` |
| `state` | varchar(20) | NULL | Nigerian state where merchant operates | `Lagos` |
| `status` | varchar(20) | NULL | Merchant verification and operational status | `Active` |
| `risk_level` | varchar(15) | NULL | Merchant fraud risk classification used in scoring engine | `Low` |

**Risk level values and typical categories:**

| Risk level | Score contribution | Typical merchant categories |
|---|---|---|
| Low | 0–15 pts | Supermarkets, utilities, telecoms, government |
| Medium | 40–45 pts | Electronics, travel, online retail |
| High | 80 pts | Crypto exchanges, betting platforms, unverified merchants |

**Merchant status values:** Active, Suspended, Unverified, Blacklisted

---

### 6. `dim_accounts`

**Description:** Account dimension storing account-level financial attributes and status. Account status is one of the most critical fraud signals — transactions from CLOSED or SUSPENDED accounts trigger hard rule overrides in the scoring engine, bypassing the composite model entirely and assigning maximum risk scores. One customer can have multiple accounts, supporting mule account detection.

**Relationships:**  
- Many-to-one with `dim_customers` via `customer_key`  
- One-to-many with `fact_transactions` via `account_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `account_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `customer_key` | integer | NOT NULL | Foreign key reference to `dim_customers` — one customer can have multiple accounts | `1` |
| `account_id` | varchar(20) | NULL | Business identifier for the account | `ACC_001` |
| `account_type` | varchar(20) | NULL | Type of account held by the customer | `Savings` |
| `balance` | numeric(18,2) | NULL | Current account balance in Nigerian Naira | `250000.00` |
| `daily_limit` | numeric(18,2) | NULL | Maximum daily transaction limit in Naira — used to detect limit-breach fraud patterns | `500000.00` |
| `currency` | varchar(10) | NULL | Transaction currency — always NGN for this system | `NGN` |
| `account_status` | varchar(20) | NULL | Current operational status of the account — drives hard rule overrides in scoring engine | `ACTIVE` |
| `created_at` | timestamp | NULL | Timestamp when account was opened | `2023-01-10 08:30:00` |

**Account status values and scoring treatment:**

| Status | Scoring treatment |
|---|---|
| ACTIVE | Normal composite scoring — no adjustment |
| DORMANT | Base score + 40 pts if transaction occurs |
| RESTRICTED | Base score + 25 pts |
| SUSPENDED | Hard rule override — score = 95, Critical, immediate alert |
| CLOSED | Hard rule override — score = 100, Critical, immediate alert |

**Account type values:** Savings, Current, Wallet, Business, Joint

---

## Fact Tables

---

### 7. `fact_transactions`

**Description:** Core fact table capturing every financial transaction event — both inflows and outflows. Central hub of the star schema, connecting to all six dimension tables. Every row in this table triggers the risk scoring engine. Counterparty columns support inflow anomaly detection and money mule pattern identification.

**Relationships:**  
- Many-to-one with all six dimension tables  
- One-to-one with `fact_risk_scores` via `transaction_key`  
- One-to-one with `fact_fraud_events` via `transaction_key`  
- One-to-many with `fraud_alerts` via `transaction_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `transaction_key` | integer | NOT NULL | Surrogate primary key | `1` |
| `customer_key` | integer | NOT NULL | Foreign key to `dim_customers` | `1` |
| `account_key` | integer | NOT NULL | Foreign key to `dim_accounts` | `1` |
| `merchant_key` | integer | NULL | Foreign key to `dim_merchants` — nullable because inflow transactions have no merchant | `42` |
| `device_key` | integer | NOT NULL | Foreign key to `dim_device` | `7` |
| `location_key` | integer | NOT NULL | Foreign key to `dim_location` — location where transaction was initiated | `3` |
| `date_key` | integer | NOT NULL | Foreign key to `dim_date` | `20230315` |
| `transaction_id` | varchar(20) | NULL | Unique business identifier for the transaction | `TXN_000001` |
| `amount` | numeric(18,2) | NULL | Transaction amount in Nigerian Naira | `45000.00` |
| `transaction_type` | varchar(25) | NULL | Specific nature of the transaction — determines direction and fraud profile | `Merchant Payment` |
| `transaction_datetime` | timestamp | NULL | Full timestamp of when the transaction occurred — used for velocity, off-hour, and time-series analysis | `2023-03-15 02:34:11` |
| `channel` | varchar(50) | NULL | Platform or channel through which the transaction was initiated | `Mobile` |
| `transaction_status` | varchar(20) | NULL | Current processing status of the transaction | `Completed` |
| `transaction_direction` | varchar(20) | NULL | High-level direction of funds — drives inflow vs outflow scoring logic | `OUTFLOW` |
| `counterparty_account_id` | varchar(15) | NULL | Account ID of the other party in the transaction — used to cross-reference known customers and merchants | `ACC_MERCH_042` |
| `counterparty_type` | varchar(20) | NULL | Category of the counterparty entity — determines default risk score assignment | `MERCHANT` |
| `counterparty_risk_score` | integer | NULL | Risk score of the counterparty at time of transaction — calculated from their latest scoring history or merchant risk level | `45` |

**Transaction type values:**

| Direction | Transaction types |
|---|---|
| INFLOW | Deposit, Transfer In, Refund, Salary Credit |
| OUTFLOW | Transfer Out, Bill Payment, Merchant Payment, Withdrawal, Airtime Purchase |

**Channel values:** Mobile, Web, POS, USSD, Bank Transfer  
**Transaction status values:** Completed, Pending, Failed, Reversed  
**Transaction direction values:** INFLOW, OUTFLOW

**Counterparty type values and default risk scores:**

| Counterparty type | Default risk score | Description |
|---|---|---|
| CUSTOMER | Calculated from history | Existing platform customer |
| MERCHANT | Derived from dim_merchants.risk_level | Registered platform merchant |
| CORPORATE | 30 | Registered business entity |
| UTILITY | 10 | Utility service provider |
| EXTERNAL | 60 | Unknown or unregistered external party |

---

### 8. `fact_risk_scores`

**Description:** Scoring output table storing the complete risk assessment for every transaction. One row per transaction. The seven boolean flag columns record which individual signals fired during scoring, enabling fraud type classification downstream. The `model_version` column supports performance comparison between scoring iterations. All history-based calculations reference this table when computing counterparty risk scores.

**Relationships:**  
- One-to-one with `fact_transactions` via `transaction_key`  
- Many-to-one with `dim_customers` via `customer_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `score_id` | integer | NOT NULL | Surrogate primary key | `1` |
| `transaction_key` | integer | NOT NULL | Foreign key to `fact_transactions` — one score per transaction | `1` |
| `customer_key` | integer | NOT NULL | Foreign key to `dim_customers` — enables customer-level risk history queries | `1` |
| `risk_score` | integer | NULL | Composite fraud risk score between 0 and 100 — calculated from seven weighted signals plus combination boosters | `78` |
| `risk_tier` | varchar(15) | NULL | Risk classification derived from composite score | `High` |
| `calculated_at` | timestamp | NULL | Timestamp when scoring engine processed this transaction | `2023-03-15 02:34:12` |
| `model_version` | varchar(5) | NULL | Version of the scoring model used — enables before/after performance comparison | `v1.0` |
| `velocity_flag` | boolean | NULL | TRUE if customer exceeded velocity threshold — 3+ transactions in 10 minutes or 15+ in one day | `FALSE` |
| `amount_flag` | boolean | NULL | TRUE if transaction amount exceeded 2x the customer's 90-day rolling average | `TRUE` |
| `location_flag` | boolean | NULL | TRUE if transaction location differs from customer home state or recent travel states | `FALSE` |
| `device_flag` | boolean | NULL | TRUE if device fingerprint not seen in customer's 60-day known device list | `TRUE` |
| `off_hour_flag` | boolean | NULL | TRUE if transaction occurred between 11pm and 5am — evaluated against 30-day customer behaviour pattern | `TRUE` |
| `merchant_flag` | boolean | NULL | TRUE if merchant risk level is Medium or High — or first-time use of high-risk merchant category | `FALSE` |
| `inflow_flag` | boolean | NULL | TRUE if inflow anomaly detected — large inflow, multiple sources, rapid receive-then-send pattern, or high-risk counterparty | `FALSE` |

**Risk tier thresholds:**

| Score range | Risk tier | System action |
|---|---|---|
| 0 – 30 | Low | Allow transaction, log only |
| 31 – 60 | Medium | Allow transaction, monitor |
| 61 – 85 | High | Flag transaction, alert fraud team |
| 86 – 100 | Critical | Block transaction, trigger email alert |

**Model version values:** v1.0 (current — all 7 signals active), v2.0 (reserved for future weight adjustments)

---

### 9. `fact_fraud_events`

**Description:** Analytical record of every detected fraud event. Only created when a transaction scores High or Critical. Records the specific fraud type determined by signal pattern matching, which rule triggered the classification, what decision was taken, and full resolution tracking. The time between `detected_at` and `resolved_at` is the primary performance metric — detection-to-resolution time — which demonstrates the system's core value proposition.

**Relationships:**  
- One-to-one with `fact_transactions` via `transaction_key`  
- Many-to-one with `dim_customers` via `customer_key`  
- One-to-one with `fraud_alerts` via `alert_id`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `fraud_id` | integer | NOT NULL | Surrogate primary key | `1` |
| `transaction_key` | integer | NOT NULL | Foreign key to `fact_transactions` | `1` |
| `customer_key` | integer | NOT NULL | Foreign key to `dim_customers` | `1` |
| `alert_id` | integer | NULL | Foreign key to `fraud_alerts` — links analytical record to operational alert | `1` |
| `amount_flagged` | numeric(18,2) | NULL | Transaction amount at risk in Nigerian Naira | `180000.00` |
| `fraud_type` | varchar(25) | NULL | Classified fraud pattern determined by scoring signal combinations | `Account Takeover` |
| `fraud_score` | integer | NULL | The composite risk score at time of fraud event creation — snapshot from fact_risk_scores | `82` |
| `decision_taken` | varchar(50) | NULL | System action taken in response to the fraud event | `Transaction Flagged` |
| `rule_triggered` | varchar(50) | NULL | The specific scoring rule or combination that caused fraud classification | `device_flag + location_flag + amount_flag` |
| `detected_at` | timestamp | NULL | Timestamp when fraud event was created by scoring engine | `2023-03-15 02:34:13` |
| `resolved_at` | timestamp | NULL | Timestamp when fraud team marked the event as resolved — NULL until resolution | `2023-03-15 04:10:00` |

**Fraud type values and signal patterns:**

| Fraud type | Signal combination |
|---|---|
| Account Takeover | device_flag + location_flag + amount_flag |
| Transaction Fraud | velocity_flag + amount_flag + off_hour_flag |
| Money Mule | inflow_flag + velocity_flag + high counterparty risk score |
| Identity Fraud | new account (< 30 days) + device_flag + merchant_flag |
| Merchant Fraud | merchant_flag (High) + amount_flag + repeated same merchant |
| Unclassified Fraud | High or Critical score with no matching pattern |

**Decision taken values:** Transaction Flagged, Transaction Blocked, Account Suspended, Under Review, False Positive Confirmed  
**Rule triggered examples:** `device_flag + location_flag + amount_flag`, `velocity_flag + amount_flag`, `account_status = CLOSED`

---

## Supporting Table

---

### 10. `fraud_alerts`

**Description:** Operational alert table serving as the action queue for the fraud operations team. Created simultaneously with `fact_fraud_events` for every High or Critical transaction. While `fact_fraud_events` is the analytical record, `fraud_alerts` is the operational trigger — what the fraud team sees and acts on. Alert lifecycle tracks from Open through Under Review to Resolved, with `estimated_exposure` quantifying the financial risk in Naira. Critical alerts additionally trigger email notifications via the Python alert system.

**Relationships:**  
- Many-to-one with `fact_transactions` via `transaction_key`  
- Many-to-one with `dim_customers` via `customer_key`

| Column | Data Type | Nullable | Description | Example Value |
|---|---|---|---|---|
| `alert_id` | integer | NOT NULL | Surrogate primary key | `1` |
| `transaction_key` | integer | NOT NULL | Foreign key to `fact_transactions` | `1` |
| `customer_key` | integer | NOT NULL | Foreign key to `dim_customers` | `1` |
| `alert_reason` | varchar(225) | NULL | Human-readable description of why the alert was triggered — written for fraud operations team review | `Device anomaly detected: new device fingerprint from unrecognised IP in Kano. Customer home state: Lagos.` |
| `alert_severity` | varchar(50) | NULL | Operational severity classification — determines urgency and escalation path | `High` |
| `risk_score` | integer | NULL | Composite risk score at time of alert creation — snapshot from scoring engine | `82` |
| `estimated_exposure` | numeric(18,2) | NULL | Financial amount at risk in Nigerian Naira — equal to the flagged transaction amount for single events | `180000.00` |
| `alert_status` | varchar(15) | NULL | Current lifecycle status of the alert — updated by fraud operations team | `Open` |
| `created_at` | timestamp | NULL | Timestamp when alert was generated by the system | `2023-03-15 02:34:13` |
| `resolved_at` | timestamp | NULL | Timestamp when fraud team marked alert as resolved — NULL until action taken | `2023-03-15 04:10:00` |

**Alert severity values:**

| Severity | Score range | System behaviour |
|---|---|---|
| Medium | 31 – 60 | Logged, no immediate alert |
| High | 61 – 85 | Alert created, fraud team notified |
| Critical | 86 – 100 | Alert created, transaction blocked, email notification fired |

**Alert status values and lifecycle:**

| Status | Description |
|---|---|
| Open | Alert just created — awaiting fraud team review |
| Under Review | Fraud team has acknowledged and is investigating |
| Resolved — Fraud Confirmed | Investigation confirmed fraudulent activity |
| Resolved — False Positive | Investigation confirmed legitimate transaction |
| Escalated | Referred to senior fraud analyst or compliance team |

---

## Key Computed Values

The following values are not stored as columns but are calculated at query time via PostgreSQL views or Power BI measures:

| Computed value | Location | Formula |
|---|---|---|
| `is_off_hour` | `vw_transactions` PostgreSQL view | `CASE WHEN EXTRACT(HOUR FROM transaction_datetime) BETWEEN 0 AND 5 OR EXTRACT(HOUR FROM transaction_datetime) = 23 THEN TRUE ELSE FALSE END` |
| `detection_to_resolution_time` | Power BI measure | `resolved_at - detected_at` from `fact_fraud_events` |
| `fraud_rate` | Power BI measure | `COUNT(fraud_id) / COUNT(transaction_key) × 100` |
| `estimated_total_exposure` | Power BI measure | `SUM(estimated_exposure)` from `fraud_alerts` where `alert_status != 'Resolved — False Positive'` |

---

## Nigerian Context Reference

**States by fraud volume weight (data generation):**

| Weight | States |
|---|---|
| ~60% of transactions | Lagos, Abuja (FCT), Kano |
| ~25% of transactions | Rivers, Oyo, Kaduna, Anambra, Delta |
| ~15% of transactions | All remaining 29 states |

**Transaction timing patterns:**
- Month-end (last 3 days): 2× normal transaction volume — salary credit period
- Weekends: 1.3× normal transaction volume
- Off-hour (11pm–5am): 8–12% of total transactions — higher fraud concentration

**Fraud rate targets (historical data):**
- Overall fraud rate: ~3% of all transactions
- December fraud rate: ~8% — holiday season spike
- New account fraud rate (< 30 days): ~12%

---

*This data dictionary is a living document and will be updated as the system evolves through model versions.*

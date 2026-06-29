-- Generates one row per day from 2022-01-01 to 2027-12-31 using GENERATE_SERIES,
-- then calculates and inserts all date attributes for each day including
-- day name, week number, month, quarter, year, weekend flag, and month-end flag.
INSERT INTO dim_date (
    date_key,
    full_date,
    day_of_week,
    week_number,
    month_number,
    month_name,
    quarter_number,
    quarter_name,
    year_number,
    is_weekend,
    is_month_end
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER                          AS date_key,
    d::DATE                                                  AS full_date,
    TO_CHAR(d, 'Day')                                        AS day_of_week,
    EXTRACT(WEEK FROM d)::INTEGER                            AS week_number,
    EXTRACT(MONTH FROM d)::INTEGER                           AS month_number,
    TO_CHAR(d, 'Month')                                      AS month_name,
    EXTRACT(QUARTER FROM d)::INTEGER                         AS quarter_number,
    'Q' || EXTRACT(QUARTER FROM d)::INTEGER                  AS quarter_name,
    EXTRACT(YEAR FROM d)::INTEGER                            AS year_number,
    EXTRACT(DOW FROM d) IN (0, 6)                            AS is_weekend,
    d = (DATE_TRUNC('MONTH', d) + INTERVAL '1 MONTH - 1 day')::DATE AS is_month_end
	
FROM GENERATE_SERIES(
    '2022-01-01'::DATE,
    '2027-12-31'::DATE,
    '1 day'::INTERVAL
) AS d;
 
 


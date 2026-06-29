/* 
Generates one row per day from 2022-01-01 to 2027-12-31 using GENERATE_SERIES,
then calculates and inserts all date attributes for each day including
day name, week number, month, quarter, year, weekend flag, and month-end flag.
*/
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
 

/*
Populate the dim_location table.

1. Download the 'dim_location.csv' file from the project's Schema
   folder.

2. Import the data into PostgreSQL using ONE of the following methods:
   - Option 1: Use pgAdmin's Import/Export Data feature (GUI).
   - Option 2: Run the COPY command below.

Note:
- The CSV file already contains the location_key values.
- Ensure the file path in the COPY command matches the location of
  the downloaded CSV file on your computer.
*/

COPY dim_location (
    location_key,
    location_id,
    country,
    state,
    risk_level
)
FROM 'Enter you dim_location file path here'
WITH (
    FORMAT CSV,
    HEADER TRUE
);



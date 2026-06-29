-- Verify all tables created
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;



-- verify the dime_date data generation sql
-- ensure there are 2191 rows is you generated fron 2022-01-01 to 2027-12-31 like i did 
SELECT COUNT(*) AS total_days 
FROM dim_date;

-- ensure there are data in all columns
SELECT * 
FROM dim_date LIMIT 5;

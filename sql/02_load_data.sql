-- =====================================================================
-- LinkedIn Professional Networking & Jobs Database
-- File: sql/02_load_data.sql
-- Description: Bulk load seed data CSVs into the linkedin schema using
--              psql \copy in parent-before-child dependency order.
-- Usage: psql -d <database> -f sql/02_load_data.sql
-- =====================================================================

SET search_path TO linkedin;

\echo '1/12 Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)

\echo '2/12 Loading skills...'
\copy skills FROM 'seed_data/skills.csv' WITH (FORMAT csv, HEADER true)

\echo '3/12 Loading companies...'
\copy companies FROM 'seed_data/companies.csv' WITH (FORMAT csv, HEADER true)

\echo '4/12 Loading members...'
\copy members FROM 'seed_data/members.csv' WITH (FORMAT csv, HEADER true)

\echo '5/12 Loading positions...'
\copy positions FROM 'seed_data/positions.csv' WITH (FORMAT csv, HEADER true)

\echo '6/12 Loading member_skills...'
\copy member_skills FROM 'seed_data/member_skills.csv' WITH (FORMAT csv, HEADER true)

\echo '7/12 Loading connections...'
\copy connections FROM 'seed_data/connections.csv' WITH (FORMAT csv, HEADER true)

\echo '8/12 Loading invitations...'
\copy invitations FROM 'seed_data/invitations.csv' WITH (FORMAT csv, HEADER true)

\echo '9/12 Loading jobs...'
\copy jobs FROM 'seed_data/jobs.csv' WITH (FORMAT csv, HEADER true)

\echo '10/12 Loading job_skills...'
\copy job_skills FROM 'seed_data/job_skills.csv' WITH (FORMAT csv, HEADER true)

\echo '11/12 Loading applications...'
\copy applications FROM 'seed_data/applications.csv' WITH (FORMAT csv, HEADER true)

\echo '12/12 Loading profile_views...'
\copy profile_views FROM 'seed_data/profile_views.csv' WITH (FORMAT csv, HEADER true)

\echo 'Gathering optimizer statistics...'
ANALYZE;
\echo 'Data load complete!'

-- =====================================================================
-- LinkedIn DBMS Project: Optimized Workload Queries (Phase 4)
-- File: sql/06_optimized_queries.sql
-- Description: Contains the full 30 workload queries. Queries with structural
--              bottlenecks are rewritten to achieve sargability, eliminate
--              correlated subqueries, and resolve SQL three-valued logic bugs.
-- Note: All markers (-- @R01 ... -- @W05) are strictly preserved for benchmarking.
-- =====================================================================
SET search_path TO linkedin;
BEGIN;

-- @R01
-- Profile header: member 1023 with their current position and company
-- Optimized via: idx_positions_member_start
SELECT m.member_id, m.first_name, m.last_name, m.headline, p.title, c.company_name
FROM members m
LEFT JOIN positions p ON p.member_id = m.member_id AND p.end_date IS NULL
LEFT JOIN companies c ON c.company_id = p.company_id
WHERE m.member_id = 1023;

-- @R02
-- Experience section: member 1023's positions, latest first
-- Optimized via: idx_positions_member_start (eliminates Sort node)
SELECT p.title, c.company_name, p.employment_type, p.start_date, p.end_date
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE p.member_id = 1023
ORDER BY p.start_date DESC;

-- @R03
-- "My Network": everyone connected to member 1023
-- Optimization: Rewrite OR condition to UNION ALL. This allows PostgreSQL to perform
-- two pure Index Only Scans (connections_pkey for member_a, idx_connections_member_b for member_b).
SELECT c.member_b AS connection_id, c.connected_at
FROM connections c
WHERE c.member_a = 1023
UNION ALL
SELECT c.member_a AS connection_id, c.connected_at
FROM connections c
WHERE c.member_b = 1023
ORDER BY connected_at DESC;

-- @R04
-- Profile page: mutual connections of member 1023 and member 356
-- Optimization: Decomposed OR subqueries into UNION ALL CTEs to use indexes on both members.
WITH f1 AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a AS friend FROM connections WHERE member_b = 1023
),
f2 AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 356
    UNION ALL
    SELECT member_a AS friend FROM connections WHERE member_b = 356
)
SELECT f1.friend
FROM f1
JOIN f2 ON f1.friend = f2.friend;

-- @R05
-- "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections
-- Optimized via: connections_pkey and idx_connections_member_b
WITH my_conn AS (
    SELECT member_b AS f FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a AS f FROM connections WHERE member_b = 1023
)
SELECT CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END AS suggestion, count(*) AS mutuals
FROM my_conn mc
JOIN connections c ON c.member_a = mc.f OR c.member_b = mc.f
WHERE CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END <> 1023
  AND CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END NOT IN (SELECT f FROM my_conn)
GROUP BY 1
ORDER BY mutuals DESC, suggestion
LIMIT 20;

-- @R06
-- Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026
-- Optimized via: idx_jobs_title_trgm (GIN) and idx_jobs_open_posted
SELECT j.job_id, j.title, c.company_name, j.workplace_type, j.min_salary_lpa, j.max_salary_lpa, j.posted_at
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE j.status = 'OPEN'
  AND j.title ILIKE '%data analyst%'
  AND (j.city_id = 1 OR j.workplace_type = 'REMOTE')
  AND j.posted_at >= '2026-06-01'
ORDER BY j.posted_at DESC;

-- @R07
-- "Jobs for you": open jobs that need at least 2 of member 1023's skills
-- Optimized via: idx_job_skills_skill_job and idx_jobs_open_posted
SELECT js.job_id, count(*) AS matching_skills
FROM job_skills js
JOIN member_skills ms ON ms.skill_id = js.skill_id AND ms.member_id = 1023
JOIN jobs j           ON j.job_id = js.job_id AND j.status = 'OPEN'
GROUP BY js.job_id
HAVING count(*) >= 2
ORDER BY matching_skills DESC, js.job_id DESC
LIMIT 25;

-- @R08
-- Recruiter: applicants of job 14075 by pipeline stage
-- Optimized via: uq_applications_job_member
SELECT a.status, count(*) AS applicants
FROM applications a
WHERE a.job_id = 14075
GROUP BY a.status
ORDER BY applicants DESC;

-- @R09
-- "My Jobs": member 1023's applications with their status
-- Optimized via: idx_applications_member_applied
SELECT a.application_id, j.title, c.company_name, a.status, a.applied_at
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.member_id = 1023
ORDER BY a.applied_at DESC;

-- @R10
-- Invitations tab: pending invitations received by member 1023
-- Optimized via: idx_invitations_pending_recipient
SELECT i.invitation_id, i.sender_id, m.first_name, m.last_name, i.note, i.sent_at
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.recipient_id = 1023 AND i.status = 'PENDING'
ORDER BY i.sent_at DESC;

-- @R11
-- "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately)
-- Optimized via: idx_profile_views_viewed_date
SELECT coalesce(v.viewer_id::text, 'Someone in private mode') AS viewer, count(*) AS views, max(v.viewed_at) AS last_view
FROM profile_views v
WHERE v.viewed_id = 217
  AND v.viewed_at >= '2026-04-01'
GROUP BY 1
ORDER BY last_view DESC;

-- @R12
-- Company page: current employees of Flipkart and their average tenure in years
-- Optimized via: idx_companies_name and idx_positions_active_company
SELECT c.company_name, count(*) AS current_employees,
       round(avg((DATE '2026-07-01' - p.start_date) / 365.25), 1) AS avg_tenure_years
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE c.company_name = 'Flipkart' AND p.end_date IS NULL
GROUP BY c.company_name;

-- @R13
-- Engagement: members who have never viewed anyone's profile (for a re-engagement nudge)
-- Bug Fix & Optimization: The original query used NOT IN (SELECT viewer_id FROM profile_views).
-- Because profile_views has NULL viewer_id (private views), SQL 3-valued logic caused NOT IN
-- to return UNKNOWN for all rows (0 rows returned).
-- Rewritten to NOT EXISTS, which correctly evaluates NULLs and uses an instant Hash Anti-Join.
SELECT m.member_id, m.first_name, m.last_name
FROM members m
WHERE NOT EXISTS (
    SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id
);

-- @R14
-- Talent insights: average days from application to hire, per company (2026 hires)
-- Optimized via: idx_applications_hired
SELECT c.company_name, count(*) AS hires,
       round(avg(EXTRACT(EPOCH FROM (a.status_updated_at - a.applied_at)) / 86400), 1) AS avg_days_to_hire
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.status = 'HIRED'
  AND a.status_updated_at >= '2026-01-01'
GROUP BY c.company_name
HAVING count(*) >= 3
ORDER BY avg_days_to_hire;

-- @R15
-- Skill demand: skills most requested by jobs posted in 2026
-- Optimization: Replace non-sargable EXTRACT(YEAR FROM j.posted_at) with sargable date range.
SELECT s.skill_name, count(*) AS jobs
FROM job_skills js
JOIN skills s ON s.skill_id = js.skill_id
JOIN jobs j   ON j.job_id = js.job_id
WHERE j.posted_at >= '2026-01-01 00:00:00+05:30' AND j.posted_at < '2027-01-01 00:00:00+05:30'
GROUP BY s.skill_name
ORDER BY jobs DESC
LIMIT 20;

-- @R16
-- Salary insights: average advertised salary range per job title and city (2026 postings with salaries)
-- Optimized via: idx_jobs_salary_insights
SELECT j.title, coalesce(ct.city_name, 'Remote') AS city, count(*) AS postings,
       round(avg(j.min_salary_lpa), 1) AS avg_min_lpa, round(avg(j.max_salary_lpa), 1) AS avg_max_lpa
FROM jobs j
LEFT JOIN cities ct ON ct.city_id = j.city_id
WHERE j.min_salary_lpa IS NOT NULL AND j.posted_at >= '2026-01-01'
GROUP BY j.title, coalesce(ct.city_name, 'Remote')
ORDER BY j.title, avg_max_lpa DESC NULLS LAST;

-- @R17
-- Talent flow: companies people joined right after leaving TCS
-- Optimized via: idx_positions_member_start and idx_companies_name
SELECT nxt.company_name, count(*) AS moved
FROM (
    SELECT p.member_id, p.company_id,
           lead(p.company_id) OVER (PARTITION BY p.member_id ORDER BY p.start_date) AS next_company_id
    FROM positions p
) t
JOIN companies cur ON cur.company_id = t.company_id AND cur.company_name = 'TCS'
JOIN companies nxt ON nxt.company_id = t.next_company_id
WHERE t.next_company_id <> t.company_id
GROUP BY nxt.company_name
ORDER BY moved DESC
LIMIT 15;

-- @R18
-- Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first
-- Optimized via: idx_members_open_to_work_city and idx_member_skills_endorsements
SELECT m.member_id, m.first_name, m.last_name, m.headline, ms.endorsements
FROM members m
JOIN member_skills ms ON ms.member_id = m.member_id
JOIN skills s         ON s.skill_id = ms.skill_id AND s.skill_name = 'SQL'
WHERE m.open_to_work AND m.city_id = 1
ORDER BY ms.endorsements DESC
LIMIT 50;

-- @R19
-- Employer report: open jobs and June 2026 applications of every IT Services company
-- Optimization: Severe bottleneck (443ms) rewritten from correlated scalar subqueries in SELECT
-- to pre-aggregated CTEs joined onto companies. Drops execution time by over 98%!
WITH open_jobs_summary AS (
    SELECT company_id, count(*) AS open_jobs
    FROM jobs
    WHERE status = 'OPEN'
    GROUP BY company_id
),
june_apps_summary AS (
    SELECT j.company_id, count(*) AS june_applications
    FROM applications a
    JOIN jobs j ON j.job_id = a.job_id
    WHERE a.applied_at >= '2026-06-01 00:00:00+05:30'
    GROUP BY j.company_id
)
SELECT c.company_id, c.company_name,
       coalesce(oj.open_jobs, 0) AS open_jobs,
       coalesce(ja.june_applications, 0) AS june_applications
FROM companies c
LEFT JOIN open_jobs_summary oj ON oj.company_id = c.company_id
LEFT JOIN june_apps_summary ja ON ja.company_id = c.company_id
WHERE c.industry = 'IT Services'
ORDER BY june_applications DESC;

-- @R20
-- Platform analytics: applications per day and running total, June 2026
-- Optimization: Replace applied_at::date function filter with sargable timestamp range.
SELECT day, apps, sum(apps) OVER (ORDER BY day) AS running_total
FROM (
    SELECT applied_at::date AS day, count(*) AS apps
    FROM applications
    WHERE applied_at >= '2026-06-01 00:00:00+05:30' AND applied_at < '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Skills pages: the most-endorsed member for each skill
-- Optimized via: idx_member_skills_endorsements
SELECT skill_name, member_id, endorsements
FROM (
    SELECT s.skill_name, ms.member_id, ms.endorsements,
           ROW_NUMBER() OVER (PARTITION BY ms.skill_id ORDER BY ms.endorsements DESC, ms.member_id) AS rn
    FROM member_skills ms
    JOIN skills s ON s.skill_id = ms.skill_id
) t
WHERE rn = 1
ORDER BY endorsements DESC;

-- @R22
-- Trust & safety console: all applications, newest first, page 4,001 (25 per page)
-- Optimized via: idx_applications_applied_at (Index Scan replaces Seq Scan + Sort)
SELECT application_id, job_id, member_id, status, applied_at
FROM applications
ORDER BY applied_at DESC
OFFSET 100000
LIMIT 25;

-- @R23
-- Sign-in: find the member by email, ignoring case
-- Optimized via: idx_members_lower_email (Expression Index turns Seq Scan into Index Scan)
SELECT member_id, first_name, last_name, is_premium
FROM members
WHERE lower(email) = 'yash.sharma1023@gmail.com';

-- @R24
-- Growth: invitation acceptance rate of Premium vs free senders (2026)
-- Optimized via: idx_invitations_sent_status
SELECT m.is_premium, count(*) AS invitations,
       round(100.0 * count(*) FILTER (WHERE i.status = 'ACCEPTED') / count(*), 1) AS accept_pct
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.sent_at >= '2026-01-01'
GROUP BY m.is_premium;

-- @R25
-- Career insights: members with a career break of more than 6 months between two positions
-- Optimized via: idx_positions_member_start
SELECT member_id, prev_end, start_date, start_date - prev_end AS gap_days
FROM (
    SELECT member_id, start_date,
           lag(end_date) OVER (PARTITION BY member_id ORDER BY start_date) AS prev_end
    FROM positions
) t
WHERE start_date - prev_end > 182
ORDER BY gap_days DESC, member_id
LIMIT 100;

-- @W01
-- "Easy Apply": member 1023 applies to job 14075
INSERT INTO applications (application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at)
VALUES (90000001, 14075, 1023, '2026-07-01 09:00:00+05:30', TRUE, 'APPLIED', '2026-07-01 09:00:00+05:30')
ON CONFLICT (job_id, member_id) DO NOTHING;

-- @W02
-- Member 1023 accepts their oldest pending invitation
-- Optimized via: idx_invitations_pending_recipient
UPDATE invitations
SET status = 'ACCEPTED', responded_at = '2026-07-01 09:10:00+05:30'
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING');

-- @W03
-- …and the new connection is stored once, smaller member id first
-- Optimized via: idx_invitations_pending_recipient
INSERT INTO connections (member_a, member_b, connected_at)
SELECT least(sender_id, recipient_id), greatest(sender_id, recipient_id), '2026-07-01 09:10:00+05:30'
FROM invitations
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING')
ON CONFLICT DO NOTHING;

-- @W04
-- Nightly job: close every job whose closing date has passed
-- Optimized via: idx_jobs_open_closes
UPDATE jobs
SET status = 'CLOSED'
WHERE status = 'OPEN' AND closes_at < '2026-07-01 00:00:00+05:30';

-- @W05
-- Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days
-- Optimized via: idx_applications_stale_cleanup
UPDATE applications a
SET status = 'REJECTED', status_updated_at = '2026-07-01 10:00:00+05:30'
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE a.job_id = j.job_id
  AND c.company_name = 'TCS'
  AND a.status = 'APPLIED'
  AND a.applied_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '60 days';

-- @END
ROLLBACK;

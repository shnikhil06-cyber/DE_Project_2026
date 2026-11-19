-- =====================================================================
-- LinkedIn Professional Networking & Jobs Database
-- File: sql/05_indexes.sql
-- Description: Production secondary indexes engineered for Phase 4 optimization.
--              Includes B-tree, Partial, Covering (INCLUDE), Expression, and GIN indexes.
-- Rules:
--   * Every index explains which queries it serves and why this column order/type.
--   * Avoid duplicate/redundant indexes to keep write overhead minimal.
-- =====================================================================

SET search_path TO linkedin;

-- ---------------------------------------------------------------------
-- 1. Extension for Trigram Substring Search
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- 2. POSITIONS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R01, R02, R17, R25
-- Why B-tree (member_id, start_date DESC):
--   R01 and R02 filter by member_id; R02 sorts by start_date DESC.
--   R17 and R25 use window functions partitioned by member_id and ordered by start_date.
--   Having member_id first (equality) followed by start_date (sort/range) eliminates in-memory sorting.
CREATE INDEX IF NOT EXISTS idx_positions_member_start 
ON positions (member_id, start_date DESC) 
INCLUDE (company_id, end_date, title, employment_type);

-- Serves: R12
-- Why Partial B-tree:
--   Filters active employees (end_date IS NULL) for specific companies (e.g. Flipkart).
--   Partial index indexes only active positions, keeping index small and hyper-focused.
CREATE INDEX IF NOT EXISTS idx_positions_active_company 
ON positions (company_id, start_date) 
WHERE end_date IS NULL;


-- ---------------------------------------------------------------------
-- 3. CONNECTIONS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R03, R04, R05, W03
-- Why B-tree (member_b, connected_at DESC):
--   Connections PK indexes (member_a, member_b). Looking up member_b = X forces a sequential
--   or bitmap scan. This reverse index on (member_b, connected_at DESC) allows instant index-only scans.
CREATE INDEX IF NOT EXISTS idx_connections_member_b 
ON connections (member_b, connected_at DESC) 
INCLUDE (member_a);


-- ---------------------------------------------------------------------
-- 4. JOBS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R06 (Trigram substring search on job title)
-- Why GIN trgm:
--   B-tree cannot index leading wildcard ILIKE '%data analyst%'. GIN with trigrams makes substring
--   matching an instant index scan. Partial on status = 'OPEN' indexes only active jobs.
CREATE INDEX IF NOT EXISTS idx_jobs_title_trgm 
ON jobs USING gin (title gin_trgm_ops) 
WHERE status = 'OPEN';

-- Serves: R06, R07, W04
-- Why Partial B-tree:
--   R06 filters posted_at range and workplace_type/city_id on OPEN jobs.
--   W04 updates expired jobs (closes_at < now() WHERE status = 'OPEN').
CREATE INDEX IF NOT EXISTS idx_jobs_open_posted 
ON jobs (posted_at DESC, city_id, workplace_type) 
WHERE status = 'OPEN';

CREATE INDEX IF NOT EXISTS idx_jobs_open_closes 
ON jobs (closes_at) 
WHERE status = 'OPEN';

-- Serves: R16 (Salary insights)
-- Why B-tree covering:
--   Filters by posted_at and min_salary_lpa IS NOT NULL, grouped by title and city.
CREATE INDEX IF NOT EXISTS idx_jobs_salary_insights 
ON jobs (posted_at, min_salary_lpa, title, city_id) 
WHERE min_salary_lpa IS NOT NULL;


-- ---------------------------------------------------------------------
-- 5. JOB_SKILLS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R07, R15
-- Why B-tree (skill_id, job_id):
--   The PK is (job_id, skill_id). Queries searching which jobs require skill X need an index
--   starting with skill_id to avoid a full table scan over 65k rows.
CREATE INDEX IF NOT EXISTS idx_job_skills_skill_job 
ON job_skills (skill_id, job_id);


-- ---------------------------------------------------------------------
-- 6. APPLICATIONS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R09
-- Why B-tree (member_id, applied_at DESC):
--   Composite unique key is (job_id, member_id). Filtering by member_id requires scanning
--   the second column. Indexing member_id first enables index scan for "My Jobs".
CREATE INDEX IF NOT EXISTS idx_applications_member_applied 
ON applications (member_id, applied_at DESC) 
INCLUDE (job_id, status);

-- Serves: R14 (Time to hire)
-- Why Partial Covering B-tree:
--   Filters status = 'HIRED' and status_updated_at >= 2026. Only ~4% of rows are HIRED.
CREATE INDEX IF NOT EXISTS idx_applications_hired 
ON applications (status_updated_at, applied_at, job_id) 
WHERE status = 'HIRED';

-- Serves: R19, R20, R22
-- Why B-tree (applied_at DESC):
--   R20 filters applied_at range; R22 orders by applied_at DESC.
CREATE INDEX IF NOT EXISTS idx_applications_applied_at 
ON applications (applied_at DESC) 
INCLUDE (job_id, member_id, status);

-- Serves: W05 (Recruiter cleanup of stale unreviewed applications)
-- Why Partial B-tree:
--   Indexes only unreviewed applications (status = 'APPLIED') by applied_at.
CREATE INDEX IF NOT EXISTS idx_applications_stale_cleanup 
ON applications (applied_at, job_id) 
WHERE status = 'APPLIED';


-- ---------------------------------------------------------------------
-- 7. INVITATIONS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R10, W02, W03
-- Why Partial B-tree (recipient_id, sent_at DESC):
--   R10 fetches pending invitations for member X. W02/W03 finds oldest pending invitation.
--   Partial index on status = 'PENDING' makes lookup instant.
CREATE INDEX IF NOT EXISTS idx_invitations_pending_recipient 
ON invitations (recipient_id, sent_at ASC) 
INCLUDE (invitation_id, sender_id, note) 
WHERE status = 'PENDING';

-- Serves: R24 (Growth acceptance rate in 2026)
-- Why Covering B-tree:
CREATE INDEX IF NOT EXISTS idx_invitations_sent_status 
ON invitations (sent_at, sender_id, status) 
WHERE sent_at >= '2026-01-01';


-- ---------------------------------------------------------------------
-- 8. PROFILE_VIEWS INDEXES
-- ---------------------------------------------------------------------
-- Serves: R11
-- Why Covering B-tree:
--   Filters by viewed_id and viewed_at range, grouping by viewer_id.
CREATE INDEX IF NOT EXISTS idx_profile_views_viewed_date 
ON profile_views (viewed_id, viewed_at DESC) 
INCLUDE (viewer_id);

-- Serves: R13 (Re-engagement nudge)
-- Why Partial B-tree:
--   Indexes viewer_id for NOT EXISTS subquery, excluding NULLs (private mode viewers).
CREATE INDEX IF NOT EXISTS idx_profile_views_viewer 
ON profile_views (viewer_id) 
WHERE viewer_id IS NOT NULL;


-- ---------------------------------------------------------------------
-- 9. MEMBERS & COMPANIES INDEXES
-- ---------------------------------------------------------------------
-- Serves: R23 (Case-insensitive login)
-- Why Expression Index:
--   Queries using lower(email) bypass standard index on email. An expression index
--   on lower(email) turns this into an instant Unique Index Scan.
CREATE UNIQUE INDEX IF NOT EXISTS idx_members_lower_email 
ON members (lower(email));

-- Serves: R18 (Open-to-work candidate sourcing)
-- Why Partial B-tree:
CREATE INDEX IF NOT EXISTS idx_members_open_to_work_city 
ON members (city_id, member_id) 
WHERE open_to_work = TRUE;

-- Serves: R18, R21
-- Why B-tree (skill_id, endorsements DESC):
--   R21 window function groups by skill_id and orders by endorsements DESC.
--   R18 filters by skill and orders by endorsements DESC.
CREATE INDEX IF NOT EXISTS idx_member_skills_endorsements 
ON member_skills (skill_id, endorsements DESC, member_id);

-- Serves: R12, R17
-- Why B-tree:
CREATE INDEX IF NOT EXISTS idx_companies_name 
ON companies (company_name, company_id);

-- Serves: R19
-- Why Partial B-tree on IT Services:
CREATE INDEX IF NOT EXISTS idx_companies_it_services 
ON companies (company_id, company_name) 
WHERE industry = 'IT Services';

-- Refresh statistics for query planner
ANALYZE;

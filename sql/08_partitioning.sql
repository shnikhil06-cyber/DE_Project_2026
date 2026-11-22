-- =====================================================================
-- LinkedIn Professional Networking & Jobs Database
-- File: sql/08_partitioning.sql
-- Description: Phase 5 Table Partitioning Architecture for `applications`
-- 
-- 1. ARCHITECTURAL JUSTIFICATION:
--    `applications` is LinkedIn's highest-velocity fact table (150k in seed,
--    3.0M in large dataset, projecting to 30M+ at 100x scale).
--    Workload queries (R06, R14, R19, R20, R22, W01, W05) overwhelmingly filter
--    by application time ranges (`applied_at`).
--    Partitioning Strategy: RANGE partitioning by `applied_at` (Quarterly).
--
-- 2. POSTGRESQL PRIMARY KEY RULE FOR PARTITIONED TABLES:
--    In PostgreSQL, any UNIQUE or PRIMARY KEY constraint on a partitioned table
--    MUST include all the partition key columns.
--    Hence, the surrogate PK is composite: (application_id, applied_at),
--    and the candidate natural key is: UNIQUE (job_id, member_id, applied_at).
-- =====================================================================

SET search_path TO linkedin;

-- ---------------------------------------------------------------------
-- 1. Create Range-Partitioned Applications Table
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS applications_partitioned CASCADE;

CREATE TABLE applications_partitioned (
    application_id INT NOT NULL,
    job_id INT NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    member_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    applied_at TIMESTAMPTZ NOT NULL,
    easy_apply BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL CHECK (
        status IN ('APPLIED', 'HIRED', 'INTERVIEW', 'OFFER', 'REJECTED', 'SHORTLISTED', 'VIEWED', 'WITHDRAWN')
    ),
    status_updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_applications_partitioned PRIMARY KEY (application_id, applied_at),
    CONSTRAINT uq_applications_part_job_member UNIQUE (job_id, member_id, applied_at),
    CONSTRAINT chk_applications_part_status_ts CHECK (status_updated_at >= applied_at)
) PARTITION BY RANGE (applied_at);

-- ---------------------------------------------------------------------
-- 2. Create Quarterly Partitions (2025 - 2026)
-- ---------------------------------------------------------------------
CREATE TABLE applications_2025_q1 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE applications_2025_q2 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE applications_2025_q3 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE applications_2025_q4 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE applications_2026_q1 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE applications_2026_q2 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE applications_2026_q3 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE applications_2026_q4 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Catch-all default partition for defensive ingestion
CREATE TABLE applications_default PARTITION OF applications_partitioned DEFAULT;

-- ---------------------------------------------------------------------
-- 3. Local Partition Indexes (Propagated Automatically to Partitions)
-- ---------------------------------------------------------------------
CREATE INDEX idx_part_apps_member_applied 
ON applications_partitioned (member_id, applied_at DESC);

CREATE INDEX idx_part_apps_applied_at 
ON applications_partitioned (applied_at DESC);

CREATE INDEX idx_part_apps_hired 
ON applications_partitioned (status_updated_at, applied_at, job_id) 
WHERE status = 'HIRED';

CREATE INDEX idx_part_apps_stale 
ON applications_partitioned (applied_at, job_id) 
WHERE status = 'APPLIED';

-- ---------------------------------------------------------------------
-- 4. Demonstration of Partition Pruning
-- ---------------------------------------------------------------------
-- The query planner examines constraints and prunes all non-matching partitions,
-- scanning ONLY `applications_2026_q2` and completely skipping the other 7 partitions.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) 
FROM applications_partitioned
WHERE applied_at >= '2026-06-01 00:00:00+05:30' 
  AND applied_at <  '2026-07-01 00:00:00+05:30';

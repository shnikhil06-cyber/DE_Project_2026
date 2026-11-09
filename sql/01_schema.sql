-- =====================================================================
-- LinkedIn Professional Networking & Jobs Database
-- File: sql/01_schema.sql
-- Description: DDL Schema definition with complete constraints (PK, FK,
--              UNIQUE, NOT NULL, CHECK) for PostgreSQL 15+.
-- Note: As per Phase 2 instructions, NO secondary indexes are created
--       here; only implicit indexes for PK and UNIQUE constraints exist.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS linkedin;
SET search_path TO linkedin;

-- Clean drop of existing tables in reverse dependency order
DROP TABLE IF EXISTS profile_views CASCADE;
DROP TABLE IF EXISTS applications CASCADE;
DROP TABLE IF EXISTS job_skills CASCADE;
DROP TABLE IF EXISTS jobs CASCADE;
DROP TABLE IF EXISTS invitations CASCADE;
DROP TABLE IF EXISTS connections CASCADE;
DROP TABLE IF EXISTS member_skills CASCADE;
DROP TABLE IF EXISTS positions CASCADE;
DROP TABLE IF EXISTS members CASCADE;
DROP TABLE IF EXISTS companies CASCADE;
DROP TABLE IF EXISTS skills CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ---------------------------------------------------------------------
-- 1. CITIES
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id INT PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL UNIQUE,
    state VARCHAR(100) NOT NULL
);

-- ---------------------------------------------------------------------
-- 2. SKILLS
-- ---------------------------------------------------------------------
CREATE TABLE skills (
    skill_id INT PRIMARY KEY,
    skill_name VARCHAR(100) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- 3. COMPANIES
-- ---------------------------------------------------------------------
CREATE TABLE companies (
    company_id INT PRIMARY KEY,
    company_name VARCHAR(150) NOT NULL,
    industry VARCHAR(50) NOT NULL CHECK (
        industry IN (
            'Banking', 'Consulting', 'E-commerce', 'EdTech', 'Fintech',
            'Healthcare', 'IT Services', 'Manufacturing', 'Software', 'Telecom'
        )
    ),
    company_size VARCHAR(20) NOT NULL CHECK (
        company_size IN ('1-10', '11-50', '51-200', '201-1000', '1001-5000', '5001-10000', '10001+')
    ),
    hq_city_id INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    founded_year SMALLINT NOT NULL CHECK (founded_year BETWEEN 1800 AND 2100),
    website VARCHAR(255)
);

-- ---------------------------------------------------------------------
-- 4. MEMBERS
-- ---------------------------------------------------------------------
CREATE TABLE members (
    member_id INT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    headline VARCHAR(255),
    email VARCHAR(255) NOT NULL UNIQUE,
    city_id INT REFERENCES cities(city_id) ON DELETE SET NULL,
    industry VARCHAR(50) NOT NULL CHECK (
        industry IN (
            'Banking', 'Consulting', 'E-commerce', 'EdTech', 'Fintech',
            'Healthcare', 'IT Services', 'Manufacturing', 'Software', 'Telecom'
        )
    ),
    is_premium BOOLEAN NOT NULL DEFAULT FALSE,
    open_to_work BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL
);

-- ---------------------------------------------------------------------
-- 5. POSITIONS (Work Experience)
-- ---------------------------------------------------------------------
CREATE TABLE positions (
    position_id INT PRIMARY KEY,
    member_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    company_id INT NOT NULL REFERENCES companies(company_id) ON DELETE RESTRICT,
    title VARCHAR(150) NOT NULL,
    employment_type VARCHAR(20) NOT NULL CHECK (
        employment_type IN ('CONTRACT', 'FULL_TIME', 'INTERNSHIP')
    ),
    start_date DATE NOT NULL,
    end_date DATE,
    CONSTRAINT chk_positions_date_order CHECK (end_date IS NULL OR end_date >= start_date)
);

-- ---------------------------------------------------------------------
-- 6. MEMBER_SKILLS (M:N Skills with endorsements)
-- ---------------------------------------------------------------------
CREATE TABLE member_skills (
    member_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    skill_id INT NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    endorsements INT NOT NULL DEFAULT 0 CHECK (endorsements >= 0),
    PRIMARY KEY (member_id, skill_id)
);

-- ---------------------------------------------------------------------
-- 7. CONNECTIONS (Bidirectional 2-way relationship stored once)
-- ---------------------------------------------------------------------
CREATE TABLE connections (
    member_a INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    member_b INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    connected_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (member_a, member_b),
    CONSTRAINT chk_connections_canonical_order CHECK (member_a < member_b)
);

-- ---------------------------------------------------------------------
-- 8. INVITATIONS
-- ---------------------------------------------------------------------
CREATE TABLE invitations (
    invitation_id INT PRIMARY KEY,
    sender_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    recipient_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    note TEXT,
    sent_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (
        status IN ('ACCEPTED', 'IGNORED', 'PENDING', 'WITHDRAWN')
    ),
    responded_at TIMESTAMPTZ,
    CONSTRAINT chk_invitations_no_self CHECK (sender_id <> recipient_id),
    CONSTRAINT chk_invitations_response_status CHECK (
        (status = 'PENDING' AND responded_at IS NULL) OR
        (status <> 'PENDING' AND responded_at IS NOT NULL AND responded_at >= sent_at)
    )
);

-- ---------------------------------------------------------------------
-- 9. JOBS
-- ---------------------------------------------------------------------
CREATE TABLE jobs (
    job_id INT PRIMARY KEY,
    company_id INT NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    title VARCHAR(150) NOT NULL,
    city_id INT REFERENCES cities(city_id) ON DELETE SET NULL,
    workplace_type VARCHAR(20) NOT NULL CHECK (
        workplace_type IN ('HYBRID', 'ONSITE', 'REMOTE')
    ),
    employment_type VARCHAR(20) NOT NULL CHECK (
        employment_type IN ('CONTRACT', 'FULL_TIME', 'INTERNSHIP')
    ),
    min_experience SMALLINT NOT NULL CHECK (min_experience >= 0),
    min_salary_lpa NUMERIC(6,2) CHECK (min_salary_lpa >= 0),
    max_salary_lpa NUMERIC(6,2) CHECK (max_salary_lpa >= 0),
    posted_at TIMESTAMPTZ NOT NULL,
    closes_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('CLOSED', 'OPEN')),
    CONSTRAINT chk_jobs_closing_after_posted CHECK (closes_at >= posted_at),
    CONSTRAINT chk_jobs_salary_range CHECK (
        max_salary_lpa IS NULL OR min_salary_lpa IS NULL OR max_salary_lpa >= min_salary_lpa
    ),
    CONSTRAINT chk_jobs_remote_city CHECK (
        (workplace_type = 'REMOTE' AND city_id IS NULL) OR
        (workplace_type IN ('ONSITE', 'HYBRID') AND city_id IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------
-- 10. JOB_SKILLS (M:N Skills required for jobs)
-- ---------------------------------------------------------------------
CREATE TABLE job_skills (
    job_id INT NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    skill_id INT NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    PRIMARY KEY (job_id, skill_id)
);

-- ---------------------------------------------------------------------
-- 11. APPLICATIONS (Job Applications)
-- ---------------------------------------------------------------------
CREATE TABLE applications (
    application_id INT PRIMARY KEY,
    job_id INT NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    member_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    applied_at TIMESTAMPTZ NOT NULL,
    easy_apply BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL CHECK (
        status IN ('APPLIED', 'HIRED', 'INTERVIEW', 'OFFER', 'REJECTED', 'SHORTLISTED', 'VIEWED', 'WITHDRAWN')
    ),
    status_updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_applications_job_member UNIQUE (job_id, member_id),
    CONSTRAINT chk_applications_status_timestamp CHECK (status_updated_at >= applied_at)
);

-- ---------------------------------------------------------------------
-- 12. PROFILE_VIEWS
-- ---------------------------------------------------------------------
CREATE TABLE profile_views (
    view_id INT PRIMARY KEY,
    viewer_id INT REFERENCES members(member_id) ON DELETE SET NULL,
    viewed_id INT NOT NULL REFERENCES members(member_id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_profile_views_no_self CHECK (viewer_id IS NULL OR viewer_id <> viewed_id)
);

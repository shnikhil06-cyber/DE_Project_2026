# Phase 1: Problem Understanding & Stakeholder Analysis

**Project:** LinkedIn Professional Networking & Jobs Database (DBMS Project)  
**Team No:** 36 (Section B)  
**Deliverable:** `docs/01_problem_understanding.md`

---

## 1. Executive Summary & Context

LinkedIn operates a dual-sided marketplace: a professional graph network connecting members and an employment marketplace connecting talent with employers. The production database was provisioned without formal schema specifications or tuning, leading to severe latency bottlenecks across core features. 

The engineering objective is to rebuild a robust, highly constrained relational schema (PostgreSQL 15+), establish reliable query execution baselines across 30 production workloads, engineer high-impact index and query optimizations, and guarantee sub-millisecond to sub-second scalability as user activity grows by 20× to 100×.

---

## 2. Problem Decomposition (P1–P7)

| Problem ID | Problem Description | Stakeholders Affected | Classification | Performance Target (Large Data) | Relevant Workload Queries |
|---|---|---|---|---|---|
| **P1** | **Network & Profile Latency**: Profiles, career histories, and connection lists suffer from high latency, especially for high-degree members ("influencers" / super-connectors). | Member / Job Seeker | **Customer-Facing / Real-Time** | < 5 ms | R01, R02, R03, R04 |
| **P2** | **Network Growth & PYMK Overhead**: "People You May Know" (2nd-degree connection graph walks) and invitation management take too long to compute. | Growth Team, Member / Job Seeker | **Real-Time (Invitations) & Interactive (PYMK)** | < 5 ms (W02, W03) / < 250 ms (R05, R10) | R05, R10, W02, W03 |
| **P3** | **Job Search, Matching & Application Lag**: Job search filtering and personalized recommendations lag; application submission must be instantaneous and idempotent. | Job Seeker, Recruiter | **Real-Time (Apply) & Interactive (Search/Match)** | < 5 ms (R09, W01) / < 250 ms (R06, R07) | R06, R07, R09, W01 |
| **P4** | **Recruiter Pipeline & Candidate Discovery**: Recruiters face sluggish candidate searches and pipeline aggregation views; stale unreviewed applications accumulate. | Recruiter, Corporate HR | **Real-Time (Pipeline) & Interactive (Search/Batch)** | < 5 ms (R08) / < 250 ms (R18, W05) | R08, R18, W05 |
| **P5** | **Profile View Analytics & Broken Re-engagement**: Profile viewer tracking lacks indexing; the re-engagement campaign query for members who never view profiles erroneously returns empty results due to three-valued logic. | Member, Growth & Engagement Team | **Real-Time (Views) & Interactive (Campaign)** | < 5 ms (R11) / < 250 ms (R13) | R11, R13 |
| **P6** | **Talent Insights & Workforce Analytics Timeouts**: Strategic reports (tenure, hiring velocity, skill demand, salary benchmarks, talent transitions, career gaps) timeout under full table scans. | Talent Insights Team, Company Page Admin | **Reporting / Analytics (OLAP)** | < 5,000 ms | R12, R14, R15, R16, R17, R25 |
| **P7** | **Platform Scalability & Batch Maintenance Degradation**: Authentication lookups, moderation console pagination, daily activity rollups, and job cleanup degrade as traffic grows 20×. | Platform Engineering, Trust & Safety | **Mixed: Real-Time / Interactive / Batch / Analytics** | < 5 ms (R23) / < 250 ms (R22) / < 1,000 ms (W04) / < 5,000 ms (R19–R21, R24) | R19, R20, R21, R22, R23, R24, W04 |

---

## 3. Detailed Business Needs by Problem

### P1: Member Profile & Network Experience
* **Business Need:** Profile rendering is LinkedIn’s primary landing surface. When a member navigates to another member's profile or their own network page, the database must instantly fetch current employment, full career chronological history, 1st-degree connections, and shared mutual connections.
* **Bottleneck:** Bidirectional connection storage (`member_a < member_b`) requires matching `WHERE member_a = X OR member_b = X`. Without composite indexing and efficient index union scans, PostgreSQL defaults to full table sequential scans over hundreds of thousands of connection records.

### P2: Organic Network Expansion (PYMK & Invitations)
* **Business Need:** Viral expansion depends on high-quality recommendations. 2nd-degree connections must be ranked by mutual connection counts while excluding existing connections and the member themselves. Invitation acceptance must be transactional, immediately creating a connection pair while maintaining canonical order (`least()`, `greatest()`).
* **Bottleneck:** PYMK computes a self-join across a graph of degree $O(d^2)$. Without indexes on connection endpoints, computing 2nd-degree friends triggers nested loop joins with multiple full-table scans.

### P3: Job Discovery & Application Flow
* **Business Need:** Job seekers need instant, filtered discovery matching job titles (case-insensitive search), locations (city-specific or remote), and recent post dates. Furthermore, the "Jobs for you" recommendation engine matches candidate skills with job requirements ($M:N$ join). Applying via "Easy Apply" must be instantaneous, ACID-compliant, and idempotent (preventing duplicate applications).
* **Bottleneck:** Multi-attribute filtering (`ILIKE '%data analyst%'`, `status = 'OPEN'`, `workplace_type = 'REMOTE'`) causes costly sequential filtering. Duplicate prevention requires an enforced `UNIQUE (job_id, member_id)` candidate key.

### P4: Recruiter Workflows & Pipeline Hygiene
* **Business Need:** Recruiters track candidate pipelines by stage (`APPLIED`, `VIEWED`, `SHORTLISTED`, `INTERVIEW`, `OFFER`, `HIRED`, `REJECTED`). Finding qualified open-to-work talent by skill and location (e.g., Bengaluru + SQL) ranked by endorsements is crucial for sourcing. Stale, unreviewed applications must be cleaned up in batches.
* **Bottleneck:** Filtering by job stage or searching candidates across `members`, `member_skills`, and `skills` without composite indexes requires scanning the 212k-row `member_skills` table.

### P5: Profile Views & Re-engagement Campaign
* **Business Need:** Members value knowing who viewed their profile, distinguishing named members from private/anonymous viewers. The marketing team requires accurate segmentation of disengaged members (those who have never viewed any profile) to send re-engagement nudges.
* **Bottleneck & Logic Bug:** `profile_views` contains anonymous views where `viewer_id IS NULL`. In SQL three-valued logic, `WHERE member_id NOT IN (SELECT viewer_id FROM profile_views)` yields `UNKNOWN` for all rows whenever the subquery returns at least one `NULL`, resulting in an empty set. This requires a query rewrite to `NOT EXISTS` or `IS NOT NULL` filtering.

### P6: Strategic Talent Insights & Benchmarking
* **Business Need:** Enterprise customers and internal analysts require aggregate market intelligence: average employee tenure, mean time from application to hire, most in-demand skills, salary distributions by role/city, inter-company employee migration patterns (e.g., exits from TCS), and career breaks (> 6 months).
* **Bottleneck:** Analytical queries combine window functions (`LAG`, `LEAD`), multi-table joins, date math, and grouping over heavy fact tables (`applications`, `positions`, `jobs`).

### P7: Platform Reliability, Trust & Safety, and Maintenance
* **Business Need:** Platform infrastructure must support sub-millisecond case-insensitive authentication (`lower(email)`), rapid deep pagination for trust and safety audits without degradation, daily application throughput tracking, automated expiration of closed jobs, and analysis of Premium conversion efficacy.
* **Bottleneck:** Case-insensitive lookups bypass B-tree indexes unless an expression index is present; high-offset pagination (`OFFSET 100000`) forces PostgreSQL to scan and discard 100,000 rows.

---

## 4. Architectural Assumptions

1. **Database Platform:** PostgreSQL 15 or newer with strict SQL standards compliance, ACID isolation, and cost-based query optimization.
2. **Timezone Standardization:** All timestamps are ingested and processed with an explicit timezone offset (`+05:30` IST) stored as `TIMESTAMPTZ`.
3. **Graph Storage Canonicalization:** Connections represent an undirected, symmetric relationship. To eliminate redundant rows, edges are strictly stored once such that `member_a < member_b`.
4. **Idempotent Application Submission:** A member cannot submit multiple applications to the same job posting; the combination `(job_id, member_id)` is strictly unique.
5. **Private Profile Views:** When members view profiles in "private mode", their `viewer_id` is recorded as `NULL`, preserving view metrics without violating user privacy.
6. **Workplace Constraints:** Remote jobs do not tie to a specific physical city (`workplace_type = 'REMOTE' ⇔ city_id IS NULL`), whereas on-site and hybrid roles mandate a valid `city_id`.
7. **Read-After-Write Consistency:** Interactive write operations (invitation acceptance, application submissions) must reflect immediately in the user's session without eventual consistency lag.

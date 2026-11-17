# Phase 3: Baseline Query Performance & Plan Analysis

**Course:** Database Management Systems · **Year:** B.Tech 2nd Year  
**Team No:** 36 (Section B)  
**Deliverable:** `docs/03_baseline_timings.md`  
**Database:** PostgreSQL 15+ (`linkedin_db`)  
**Hardware Environment:** Apple M4, 16 GB Unified Memory, macOS 15.x  
**Raw Benchmark Outputs:** `benchmarks/results/baseline/*.txt` & `benchmarks/results/baseline/summary.csv`

---

## 1. Methodology & Measurement Standards

Every query in `queries/workload_30.sql` (25 reads `R01`–`R25` and 5 writes `W01`–`W05`) was benchmarked using the required rigorous methodology:

1. **Engine Level Timing:** Measured via PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)` engine, reading the actual `Execution Time` at the plan termination.
2. **Repetition & Statistical Averaging:** Each workload was executed **3 consecutive times** (`Run 1`, `Run 2`, `Run 3`) under identical conditions. The arithmetic mean is reported as the benchmark average.
3. **Write Isolation & Consistency:** All mutation queries (`W01`–`W05`) were executed inside explicit `BEGIN; ... ROLLBACK;` blocks, guaranteeing zero persistent state drift across repetitions.
4. **Unindexed Baseline Purity:** Benchmarking was executed strictly against the canonical Phase 2 schema with **only primary key and unique constraint indexes**. No secondary indexes or query rewrites were introduced.
5. **Traceability:** Full query plans with buffer hits and scan nodes for all 3 runs per query are preserved in `benchmarks/results/baseline/<query_id>.txt`.

---

## 2. Baseline Timing Table (All 30 Workloads)

| SQL Query                                                                                                            | Type  |   Run 1 (ms) |   Run 2 (ms) |   Run 3 (ms) | Average (ms) |
| -------------------------------------------------------------------------------------------------------------------- | ----- | -----------: | -----------: | -----------: | -----------: |
| **R01**: Profile header: member 1023 with their current position and company                                         | READ  |        6.837 |        6.566 |        6.915 |        6.773 |
| **R02**: Experience section: member 1023's positions, latest first                                                   | READ  |        5.082 |        5.316 |        5.203 |        5.200 |
| **R03**: "My Network": everyone connected to member 1023                                                             | READ  |        4.707 |        4.443 |        4.059 |        4.403 |
| **R04**: Profile page: mutual connections of member 1023 and member 356                                              | READ  |       14.637 |       13.643 |       13.870 |       14.050 |
| **R05**: "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections                   | READ  |       50.781 |       49.967 |       50.932 |       50.560 |
| **R06**: Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026        | READ  |       11.514 |       11.340 |       11.558 |       11.471 |
| **R07**: "Jobs for you": open jobs that need at least 2 of member 1023's skills                                      | READ  |        9.746 |        9.586 |        9.660 |        9.664 |
| **R08**: Recruiter: applicants of job 14075 by pipeline stage                                                        | READ  |        0.173 |        0.137 |        0.141 |        0.150 |
| **R09**: "My Jobs": member 1023's applications with their status                                                     | READ  |        3.537 |        3.236 |        3.056 |        3.276 |
| **R10**: Invitations tab: pending invitations received by member 1023                                                | READ  |        4.867 |        3.953 |        4.294 |        4.371 |
| **R11**: "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately) | READ  |        9.269 |        8.258 |        8.588 |        8.705 |
| **R12**: Company page: current employees of Flipkart and their average tenure in years                               | READ  |        9.349 |        9.427 |        9.341 |        9.372 |
| **R13**: Engagement: members who have never viewed anyone's profile (for a re-engagement nudge)                      | READ  |       44.404 |       44.087 |       46.116 |       44.869 |
| **R14**: Talent insights: average days from application to hire, per company (2026 hires)                            | READ  |       16.448 |       17.162 |       17.952 |       17.187 |
| **R15**: Skill demand: skills most requested by jobs posted in 2026                                                  | READ  |       16.446 |       15.874 |       15.789 |       16.036 |
| **R16**: Salary insights: average advertised salary range per job title and city (2026 postings with salaries)       | READ  |        3.179 |        3.334 |        3.291 |        3.268 |
| **R17**: Talent flow: companies people joined right after leaving TCS                                                | READ  |       69.140 |       70.686 |       70.207 |       70.011 |
| **R18**: Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first                        | READ  |       16.364 |       15.658 |       15.631 |       15.884 |
| **R19**: Employer report: open jobs and June 2026 applications of every IT Services company                          | READ  |      449.780 |      441.821 |      439.052 |      443.551 |
| **R20**: Platform analytics: applications per day and running total, June 2026                                       | READ  |       11.961 |       11.823 |       11.856 |       11.880 |
| **R21**: Skills pages: the most-endorsed member for each skill                                                       | READ  |      183.745 |      190.345 |      190.073 |      188.054 |
| **R22**: Trust & safety console: all applications, newest first, page 4,001 (25 per page)                            | READ  |       57.667 |       59.846 |       59.462 |       58.992 |
| **R23**: Sign-in: find the member by email, ignoring case                                                            | READ  |       18.139 |       18.217 |       17.899 |       18.085 |
| **R24**: Growth: invitation acceptance rate of Premium vs free senders (2026)                                        | READ  |       17.516 |       18.165 |       18.708 |       18.130 |
| **R25**: Career insights: members with a career break of more than 6 months between two positions                    | READ  |       65.601 |       65.052 |       64.856 |       65.170 |
| **W01**: "Easy Apply": member 1023 applies to job 14075                                                              | WRITE |        1.401 |        0.900 |        0.850 |        1.050 |
| **W02**: Member 1023 accepts their oldest pending invitation                                                         | WRITE |        4.736 |        4.419 |        4.399 |        4.518 |
| **W03**: …and the new connection is stored once, smaller member id first                                             | WRITE |        4.965 |        5.127 |        5.270 |        5.121 |
| **W04**: Nightly job: close every job whose closing date has passed                                                  | WRITE |        7.035 |        5.331 |        4.852 |        5.739 |
| **W05**: Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days                          | WRITE |        7.186 |        5.801 |        5.981 |        6.323 |
| **Total (sum of all 30)**                                                                                            |       | **1126.212** | **1119.520** | **1119.861** | **1121.864** |

---

## 3. Plan Node Breakdown & Execution Bottlenecks

### `R01`: Profile Header

- **Scan Nodes:** `Index Scan using members_pkey on members` \| `Seq Scan on positions` \| `Index Scan using companies_pkey on companies`
- **Why it is slow/fast:** Direct primary key index lookups on `members` and `companies` take <0.01 ms, but the join forces a full sequential scan across all 99,940 rows of `positions` because `positions.member_id` lacks a foreign key index.

### `R02`: Experience Section

- **Scan Nodes:** `Seq Scan on positions` \| `Index Scan using companies_pkey on companies`
- **Why it is slow/fast:** Fast primary key join on `companies`, but scans the entire `positions` table (99,940 rows) to filter for `member_id = 1023` followed by a memory sort on `start_date DESC`.

### `R03`: "My Network" (1st-degree Connections)

- **Scan Nodes:** `Bitmap Heap Scan on connections` \| `Bitmap Index Scan on connections_pkey`
- **Why it is slow/fast:** The primary key `(member_a, member_b)` enables an index scan for `member_a = 1023`, but looking up `member_b = 1023` forces an expensive Bitmap Index Scan / Heap Scan over connection blocks.

### `R04`: Mutual Connections

- **Scan Nodes:** `Seq Scan on connections`
- **Why it is slow/fast:** Evaluates two independent subqueries with `OR` clauses (`member_a = X OR member_b = X`), causing PostgreSQL to execute two parallel sequential scans across 219,966 connection edges before hash joining.

### `R05`: "People You May Know" (2nd-degree Connections)

- **Scan Nodes:** `Bitmap Heap Scan on connections` \| `Bitmap Index Scan on connections_pkey`
- **Why it is slow/fast:** Explores 2nd-degree graph edges by joining the 1st-degree connection set against `connections` with an `OR` condition, re-scanning large portions of the 220k-row graph without an index on `member_b`.

### `R06`: Filtered Job Search

- **Scan Nodes:** `Seq Scan on jobs` \| `Index Scan using companies_pkey on companies`
- **Why it is slow/fast:** Performs full sequential scan of 15,000 jobs to evaluate regex substring pattern `ILIKE '%data analyst%'` and compound date/city filters; lacks trigram/GIN and composite date indexes.

### `R07`: Skill-Based Job Recommendations

- **Scan Nodes:** `Seq Scan on job_skills` \| `Seq Scan on jobs` \| `Index Only Scan using member_skills_pkey on member_skills`
- **Why it is slow/fast:** While member skills are fetched via PK index, matching against required job skills requires a full sequential scan of all 65,719 rows in `job_skills` and 15,000 rows in `jobs`.

### `R08`: Recruiter Pipeline Applicants

- **Scan Nodes:** `Index Scan using uq_applications_job_member on applications`
- **Why it is slow/fast:** Highly efficient (**0.150 ms**) because `job_id` is the leading column of the unique composite constraint `(job_id, member_id)`, allowing an instantaneous B-tree index lookup.

### `R09`: "My Jobs"

- **Scan Nodes:** `Index Scan using uq_applications_job_member on applications` \| `Index Scan using jobs_pkey on jobs` \| `Index Scan using companies_pkey on companies`
- **Why it is slow/fast:** Reasonably quick (3.27 ms) due to PK joins on jobs and companies, but filtering by `member_id` requires scanning index leaves since `member_id` is the secondary column of `(job_id, member_id)`.

### `R10`: Pending Received Invitations

- **Scan Nodes:** `Seq Scan on invitations` \| `Index Scan using members_pkey on members`
- **Why it is slow/fast:** Forces a full sequential scan over 60,000 invitations because `recipient_id` lacks a foreign key index.

### `R11`: Profile Viewers Audit

- **Scan Nodes:** `Seq Scan on profile_views`
- **Why it is slow/fast:** Scans all 199,996 profile view rows sequentially to filter by `viewed_id = 217` and date threshold, as `viewed_id` is completely unindexed.

### `R12`: Company Employee Tenure

- **Scan Nodes:** `Seq Scan on positions` \| `Seq Scan on companies`
- **Why it is slow/fast:** Performs full table scans on both `companies` (filtering for name 'Flipkart') and `positions` (filtering active employees `end_date IS NULL` and `company_id`).

### `R13`: Re-engagement Inactive Audience

- **Scan Nodes:** `Seq Scan on members` \| `Seq Scan on profile_views`
- **Why it is slow/fast:** Scans all 40,000 members and all 199,996 profile views. **Critical finding:** returns 0 rows because `viewer_id` contains NULLs (anonymous views), causing `NOT IN (SELECT viewer_id ...)` to evaluate to `UNKNOWN` under SQL three-valued logic.

### `R14`: Average Time to Hire

- **Scan Nodes:** `Seq Scan on applications` \| `Seq Scan on jobs` \| `Seq Scan on companies`
- **Why it is slow/fast:** Heavy analytical multi-join sequentially scanning 150k applications, 15k jobs, and 2k companies before grouping and filtering by hire threshold.

### `R15`: Skill Demand in 2026

- **Scan Nodes:** `Seq Scan on jobs` \| `Index Only Scan using job_skills_pkey on job_skills` \| `Seq Scan on skills`
- **Why it is slow/fast:** Scans all 15,000 jobs to evaluate `EXTRACT(YEAR FROM posted_at) = 2026` (non-sargable expression), followed by joining the full requirements junction table.

### `R16`: Salary Range Insights

- **Scan Nodes:** `Seq Scan on jobs` \| `Seq Scan on cities`
- **Why it is slow/fast:** Moderately fast (3.26 ms) because `cities` is tiny (10 rows), but still sequentially scans 15,000 jobs for salary ranges and dates.

### `R17`: Inter-Company Talent Flow

- **Scan Nodes:** `Seq Scan on positions` \| `Seq Scan on companies` \| `Index Scan using companies_pkey on companies`
- **Why it is slow/fast:** Slow (70 ms) due to evaluating the analytical window function `lead(company_id) OVER (PARTITION BY member_id ORDER BY start_date)` across 99,940 positions, requiring an in-memory or spill sort.

### `R18`: Recruiter Open-to-Work Candidate Sourcing

- **Scan Nodes:** `Seq Scan on member_skills` \| `Seq Scan on skills` \| `Index Scan using members_pkey on members`
- **Why it is slow/fast:** Scans all 212,417 member skills and 40,000 members, lacking composite indexes on `(city_id, open_to_work)` or `(skill_id, endorsements)`.

### `R19`: IT Services Employer Monthly Rollup

- **Scan Nodes:** `Seq Scan on companies` \| `Seq Scan on jobs` \| `Index Scan using uq_applications_job_member on applications`
- **Why it is slow/fast:** **Severe bottleneck (443.5 ms, slowest query in workload)**! Executes correlated scalar subqueries inside the `SELECT` clause for every IT Services company, repeatedly executing scans across `jobs` and `applications`.

### `R20`: Platform Daily Application Trajectory

- **Scan Nodes:** `Seq Scan on applications`
- **Why it is slow/fast:** Scans 149,984 applications sequentially to group by date expression `applied_at::date` and compute running window sum.

### `R21`: Skill Leaderboard (Top Endorsed Members)

- **Scan Nodes:** `Seq Scan on member_skills` \| `Seq Scan on skills`
- **Why it is slow/fast:** **Second slowest query (188.0 ms)**. The window function `ROW_NUMBER() OVER (PARTITION BY skill_id ORDER BY endorsements DESC)` requires sorting all 212,417 rows of `member_skills` in memory.

### `R22`: Trust & Safety Deep Pagination

- **Scan Nodes:** `Seq Scan on applications`
- **Why it is slow/fast:** High latency (58.9 ms) due to deep offset pagination (`OFFSET 100000 LIMIT 25`), forcing PostgreSQL to sort all 150k application records by `applied_at DESC` and discard 100,000 rows.

### `R23`: Case-Insensitive User Authentication

- **Scan Nodes:** `Seq Scan on members`
- **Why it is slow/fast:** Full sequential scan of 40,000 members because the functional predicate `lower(email)` cannot utilize the standard B-tree index on `email`.

### `R24`: Premium Conversion & Invitation Acceptance Rate

- **Scan Nodes:** `Seq Scan on invitations` \| `Seq Scan on members`
- **Why it is slow/fast:** Sequential scans over 60,000 invitations and 40,000 members with conditional filters for 2026.

### `R25`: Career Break Detection (>6 Months)

- **Scan Nodes:** `Seq Scan on positions`
- **Why it is slow/fast:** Evaluates `lag(end_date) OVER (PARTITION BY member_id ORDER BY start_date)` across 99,940 positions, requiring an expensive sort node following a full table sequential scan.

### `W01`: "Easy Apply" Idempotent Submission

- **Scan Nodes:** `(no scan)`
- **Why it is slow/fast:** Extremely fast (1.05 ms) single-row insertion verified by unique candidate index `uq_applications_job_member`.

### `W02`: Invitation Acceptance Transaction

- **Scan Nodes:** `Seq Scan on invitations` \| `Index Scan using invitations_pkey on invitations`
- **Why it is slow/fast:** Subquery `SELECT min(invitation_id) ... WHERE recipient_id = 1023` sequentially scans all 60,000 invitations because `recipient_id` lacks a foreign key index.

### `W03`: Canonical Connection Creation

- **Scan Nodes:** `Seq Scan on invitations` \| `Index Scan using invitations_pkey on invitations`
- **Why it is slow/fast:** Subquery lookup experiences identical sequential scan overhead on `invitations` before inserting into `connections`.

### `W04`: Nightly Job Expiration

- **Scan Nodes:** `Seq Scan on jobs`
- **Why it is slow/fast:** Sequentially scans all 15,000 jobs to find records meeting `status = 'OPEN' AND closes_at < ...` due to absence of a partial index on open jobs.

### `W05`: Recruiter Application Cleanup

- **Scan Nodes:** `Seq Scan on jobs` \| `Seq Scan on companies` \| `Index Scan using uq_applications_job_member on applications`
- **Why it is slow/fast:** Scans `companies` and `jobs` sequentially to resolve TCS job IDs before updating stale applications.

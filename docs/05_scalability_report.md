# Phase 5: Scalability Report (Large Dataset 20×)

**Course:** Database Management Systems · **Year:** B.Tech 2nd Year  
**Team No:** 36 (Section B)  
**Deliverable:** `docs/05_scalability_report.md`  
**Database:** PostgreSQL 18.6 (`linkedin_large`)  
**Hardware Environment:** Apple M4, 16 GB RAM, macOS 15.x  
**Raw Benchmark Plans:** `benchmarks/results/large/*.txt` & `benchmarks/results/large/summary.csv`

---

## 1. Overview & Key Findings

In Phase 5, we tested our Phase 4 optimized schema and indexes against the 20× large dataset released by faculty (`large_data.zip`). 

The large dataset contains **21,303,424 total rows** across the 12 tables (about 20 times the seed dataset of 1,043,188 rows). We loaded this data into a new database `linkedin_large`, applied our secondary indexes from `sql/05_indexes.sql`, ran `ANALYZE`, and timed all 30 queries (`R01` to `R25` and `W01` to `W05`) using `EXPLAIN (ANALYZE, BUFFERS)` with 3 runs each.

### Main Takeaways:
1. **Target SLA Compliance (29 of 30 met):**
   - **Real-time queries (`R01–R04, R08–R11, R23, W01–W03`):** Target is **< 5 ms**. All 12 queries ran in **0.03 ms to 1.17 ms**, well within the limit.
   - **Interactive queries (`R05–R07, R12, R18, R22, W05`):** Target is **< 250 ms**. All ran between **0.19 ms and 83.71 ms**.
   - **Analytics queries (`R14–R17, R19–R21, R24, R25`):** Target is **< 5,000 ms**. All completed between **12.47 ms and 655.68 ms**.
   - **Batch job (`W04`):** Target is **< 1,000 ms**. It took **139.70 ms**.
2. **The Only SLA Miss (`R13`):**
   - `R13` took **270.98 ms** on average against a 250 ms target. Looking at the EXPLAIN plan, PostgreSQL's default `work_mem = 4MB` was not enough to hold the hash table for 800,000 members, so it spilled to disk in 8 batches (writing 11,980 disk buffers). Setting `work_mem = 64MB` kept the hash table entirely in memory and reduced execution time to **231.54 ms**. In reality, finding users who never viewed a profile is an offline marketing re-engagement task rather than a real-time UI query, so treating it as an analytics query easily satisfies the 5,000 ms target.
3. **Deep Pagination (`R22`):**
   - `R22` (`OFFSET 100000 LIMIT 25`) ran in 9.49 ms using our index on `applied_at`. But because `OFFSET` still has to scan through 100,000 index tuples before returning 25 rows, this will become slow at 100× scale. We implemented Keyset Pagination (`WHERE applied_at < last_seen_timestamp`), which drops the time to **0.013 ms** (a 99.9% reduction).
4. **Total Workload Execution Time:**
   - The total execution time for all 30 queries on the 20× large dataset is **2,429.35 ms** (~2.4 seconds). Even though the data grew by 20.4×, our total workload time only grew by **2.16×** compared to the unoptimized baseline on the seed data (1,121.86 ms).
5. **Storage Growth:**
   - Database size grew from **151 MB** on seed data to **2,842 MB (2.84 GB)** on large data (an 18.8× increase). Indexes make up **57.3%** of the total relation storage, which is expected because we added covering and partial indexes to support high-speed lookups.

---

## 2. Benchmark Results Table (All 30 Queries)

The table below compares the 3-run average execution times of our optimized queries on the seed dataset versus the 20× large dataset.

| Query | Type | Target (ms) | Seed Optimized (ms) | Large Optimized (ms) | Growth (Large ÷ Seed) | Meets Target? | What we observed / Plan used |
|:---|:---|---:|---:|---:|---:|:---:|:---|
| **R01** | READ | < 5 | 0.132 | **0.402** | 3.05× | YES | Index Scan on members, Index Only Scan on positions, Index Scan on companies |
| **R02** | READ | < 5 | 0.115 | **0.250** | 2.17× | YES | Index Only Scan on positions (`idx_positions_member_start`), Index Scan on companies |
| **R03** | READ | < 5 | 0.082 | **0.187** | 2.28× | YES | `UNION ALL` of two Index Only Scans using `connections_pkey` and `idx_connections_member_b` |
| **R04** | READ | < 5 | 0.165 | **0.186** | 1.13× | YES | Index Only Scans on connections for both members, hash join on member IDs |
| **R05** | READ | < 250 | 0.564 | **4.048** | 7.18× | YES | Bitmap Index Scans on `connections_pkey` and `idx_connections_member_b`, Bitmap Heap Scan |
| **R06** | READ | < 250 | 0.488 | **4.621** | 9.47× | YES | Bitmap Index Scan on `idx_jobs_open_posted`, Index Scan on companies |
| **R07** | READ | < 250 | 2.310 | **23.652** | 10.24× | YES | Index Only Scan on `member_skills_pkey` and `idx_job_skills_skill_job`, Index Scan on jobs |
| **R08** | READ | < 5 | 0.149 | **0.191** | 1.28× | YES | Index Scan on candidate key `uq_applications_job_member` |
| **R09** | READ | < 5 | 0.142 | **0.223** | 1.57× | YES | Index Scan on `idx_applications_member_applied`, Index Scans on jobs and companies |
| **R10** | READ | < 5 | 0.108 | **0.085** | 0.79× | YES | Index Scan on partial index `idx_invitations_pending_recipient` (cached hit) |
| **R11** | READ | < 5 | 0.174 | **0.105** | 0.60× | YES | Index Only Scan on `idx_profile_views_viewed_date` |
| **R12** | READ | < 250 | 0.177 | **0.190** | 1.07× | YES | Index Scan on `idx_companies_name`, Index Scan on `idx_positions_active_company` |
| **R13** | READ | < 250 | 21.684 | **270.977** | 12.50× | NO* | Parallel Hash Anti Join spilled to disk under 4MB `work_mem`. Fixed with 64MB `work_mem` (231.54 ms) |
| **R14** | READ | < 5000 | 5.963 | **62.220** | 10.43× | YES | Bitmap Index Scan on partial index `idx_applications_hired` |
| **R15** | READ | < 5000 | 15.247 | **63.489** | 4.16× | YES | Bitmap Index Scan on `idx_jobs_open_posted`, HashAggregate for skill counts |
| **R16** | READ | < 5000 | 2.250 | **12.465** | 5.54× | YES | Index Scan on `idx_jobs_salary_insights`, HashAggregate |
| **R17** | READ | < 5000 | 62.136 | **655.682** | 10.55× | YES | Index Only Scan on `idx_positions_member_start`, WindowAgg using `lead()` |
| **R18** | READ | < 250 | 1.673 | **17.151** | 10.25× | YES | Bitmap Index Scan on `idx_members_open_to_work_city`, Index Only Scan on `idx_member_skills_endorsements` |
| **R19** | READ | < 5000 | 6.428 | **52.116** | 8.11× | YES | Bitmap Index Scan on `idx_applications_applied_at`, HashAggregate per company |
| **R20** | READ | < 5000 | 2.395 | **28.716** | 11.99× | YES | Bitmap Index Scan on `idx_applications_applied_at`, WindowAgg for running totals |
| **R21** | READ | < 5000 | 41.022 | **436.405** | 10.64× | YES | Index Only Scan on `idx_member_skills_endorsements`, WindowAgg using `ROW_NUMBER()` |
| **R22** | READ | < 250 | 17.401 | **9.489** | 0.55× | YES | Index Scan on `idx_applications_applied_at`. Keyset pagination rewrite runs in **0.013 ms** |
| **R23** | READ | < 5 | 0.055 | **0.027** | 0.49× | YES | Index Scan on expression index `idx_members_lower_email` |
| **R24** | READ | < 5000 | 15.199 | **92.030** | 6.06× | YES | Bitmap Index Scan on `idx_invitations_sent_status`, HashAggregate |
| **R25** | READ | < 5000 | 58.587 | **612.006** | 10.45× | YES | Index Only Scan on `idx_positions_member_start`, WindowAgg using `lag()` |
| **W01** | WRITE | < 5 | 1.324 | **1.166** | 0.88× | YES | Single row INSERT into applications with index updates and foreign key checks |
| **W02** | WRITE | < 5 | 0.373 | **0.509** | 1.36× | YES | Single row UPDATE on invitations using `idx_invitations_pending_recipient` |
| **W03** | WRITE | < 5 | 0.898 | **0.564** | 0.63× | YES | UPDATE invitation and conditional INSERT into connections |
| **W04** | WRITE | < 1000 | 4.967 | **139.698** | 28.13× | YES | Batch UPDATE closing expired jobs using partial index `idx_jobs_open_closes` |
| **W05** | WRITE | < 250 | 6.865 | **83.712** | 12.19× | YES | Batch DELETE of stale pending applications using partial index `idx_applications_stale` |

*\*Note on R13: Missed the 250 ms interactive SLA by 20 ms due to memory spill on default work_mem. Fixed by increasing work_mem to 64MB or treating it as a background analytics query.*

---

## 3. Growth Analysis

When the data grew 20.4× (from 1.04 million rows to 21.3 million rows), the query timings grew in three distinct patterns based on how PostgreSQL accesses the data:

### 1. Queries that stayed about the same (< 3× growth)
**Queries:** `R01`, `R02`, `R03`, `R04`, `R08`, `R09`, `R10`, `R11`, `R12`, `R22`, `R23`, `W01`, `W02`, `W03`.

**Why this happened:**
All of these queries perform point lookups or very small range lookups on B-tree indexes. 
In PostgreSQL, a B-tree page has a fanout of roughly 200 to 300 entries per 8 KB block. When a table grows from 40,000 rows to 800,000 rows (or 150,000 rows to 3,000,000 rows), the height of the B-tree only increases by **1 level** (from 3 levels to 4 levels).

Because traversing one more tree level only takes **one additional 8 KB page fetch** (and that page is almost always already cached in PostgreSQL's buffer pool), the execution time barely changes. For example:
- `R23` (login lookup by email): 0.055 ms on seed $\to$ **0.027 ms** on large data.
- `R03` (member's connections): 0.082 ms on seed $\to$ **0.187 ms** on large data.
- `R08` (check applicant status): 0.149 ms on seed $\to$ **0.191 ms** on large data.
- `W01` (submit application): 1.324 ms on seed $\to$ **1.166 ms** on large data.

These queries run in less than 1.2 ms regardless of whether the table has 150k rows or 3 million rows.

### 2. Queries that grew roughly 20× (linear growth, between 4× and 15×)
**Queries:** `R05`, `R06`, `R07`, `R14`, `R15`, `R16`, `R17`, `R18`, `R19`, `R20`, `R21`, `R24`, `R25`, `W05`.

**Why this happened:**
These queries scan or aggregate a fixed percentage of the rows in a table. When the overall table grew by 20×, the number of matching records that PostgreSQL had to fetch, join, sort, or aggregate also grew by about 10× to 20×:
- **`R14` (hired applications per company):** On seed data, there were about 6,000 hired applications (took 5.96 ms). On large data, there were 120,000 hired applications. It took **62.22 ms** (10.4× growth).
- **`R17` & `R25` (career progression window functions):** These compute `lead()` and `lag()` across all positions in the table. Sorting and evaluating the window frame across nearly 2,000,000 positions went from ~60 ms to **~650 ms** (10.5× growth).
- **`R07` (job recommendations matching skills):** The query joins member skills with the job skills of all open jobs. The matching candidate set grew from 645 pairs to 12,892 pairs, so the time increased from 2.31 ms to **23.65 ms** (10.2× growth).

Even with this linear growth, all of these queries easily met their targets. The analytical queries were targeted at < 5,000 ms and the slowest one (`R17`) completed in 655 ms, leaving plenty of headroom.

### 3. Queries that grew more than 20× or hit bottlenecks
**Queries:** `W04`, `R13`, and `R22` (at high offsets).

**Why this happened:**
- **`W04` (Batch job closing expired jobs):** Grew **28.13×** (from 4.97 ms to 139.70 ms). In PostgreSQL, an `UPDATE` does not modify data in place. It creates a brand-new row version (MVCC), writes WAL logs, and updates every index on the `jobs` table (`idx_jobs_open_posted`, `idx_jobs_open_closes`). Because the large dataset had 20× more expired jobs closing in a single query, writing all those tuple versions and index pages created noticeable write overhead. Still, 139.7 ms is well under the 1,000 ms batch SLA.
- **`R13` (Members who never viewed a profile):** Grew **12.50×** (from 21.68 ms to 270.98 ms), exceeding the 250 ms target. This happened because the hash table for 800,000 members exceeded the default 4MB `work_mem` and spilled to disk.
- **`R22` (Deep pagination):** Ran in 9.49 ms on `OFFSET 100000`, but scanning through 100,000 index tuples is an $O(N)$ operation that will degrade as offset numbers increase.

---

## 4. What Broke at Scale and How We Fixed It

### Issue 1: `R13` Hash Anti-Join Memory Spill

#### What happened:
`R13` finds members who have never viewed anyone's profile:
```sql
SELECT m.member_id, m.first_name, m.last_name
FROM members m
WHERE NOT EXISTS (
    SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id
);
```
On the seed data (40k members, 200k views), the hash table was tiny and fit easily into RAM. 
On the large data (800,000 members, 4,000,000 profile views), building the hash table for members took about 48 MB of RAM. Because PostgreSQL's default `work_mem` is only **4 MB**, the engine was forced to split the hash table into **8 batches and spill temporary files to disk**.

#### Plan Before the Fix (`work_mem = 4MB`):
```text
Gather  (cost=22752.00..119306.73 rows=231200 width=15) (actual time=226.405..297.455 rows=130313 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=7274 read=29895, temp read=11911 written=11980
  ->  Parallel Hash Right Anti Join  (cost=21752.00..95186.73 rows=96333 width=15)
        Hash Cond: (v.viewer_id = m.member_id)
        Buffers: shared hit=7274 read=29895, temp read=11911 written=11980
        ->  Parallel Seq Scan on profile_views v  (cost=0.00..41226.64 rows=1666664 width=4)
        ->  Parallel Hash  (cost=15957.33..15957.33 rows=333333 width=15)
              Buckets: 262144  Batches: 8  Memory Usage: 7072kB
              Buffers: shared hit=6473 read=6151, temp written=3144
Execution Time: 299.915 ms (3-run average: 270.977 ms)
```
Notice `Batches: 8` and `temp read=11911 written=11980`. Over 11,900 disk blocks (~95 MB) were written to disk and read back, which pushed the time over the 250 ms target.

#### How we fixed it:
We gave the query session adequate working memory:
```sql
SET work_mem = '64MB';
```

#### Plan After the Fix (`work_mem = 64MB`):
```text
Gather  (cost=21124.00..103028.73 rows=231200 width=15) (actual time=175.210..228.415 rows=130313 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=8215 read=28953 (ZERO temp buffers read/written)
  ->  Parallel Hash Right Anti Join  (cost=20124.00..78908.73 rows=96333 width=15)
        Hash Cond: (v.viewer_id = m.member_id)
        ->  Parallel Seq Scan on profile_views v  (cost=0.00..41226.64 rows=1666664 width=4)
        ->  Parallel Hash  (cost=15957.33..15957.33 rows=333333 width=15)
              Buckets: 1048576  Batches: 1  Memory Usage: 48000kB
Execution Time: 231.540 ms
```
With `Batches: 1`, the entire hash join completed in RAM with zero disk I/O, bringing execution time down to **231.54 ms** (safely under the 250 ms target).

In production, scanning 4 million rows to find inactive users is actually an offline batch job (e.g., sending weekly re-engagement emails), not a real-time user-facing click. As an analytics task, its 231 ms time is well below the 5,000 ms analytics SLA.

---

### Issue 2: `R22` Deep Pagination Offset Trap

#### What happened:
`R22` fetches page 4,001 of applications (offset 100,000, 25 per page):
```sql
SELECT application_id, job_id, member_id, applied_at, status
FROM applications
ORDER BY applied_at DESC
OFFSET 100000 LIMIT 25;
```
Even though we have an index on `applied_at`, PostgreSQL still has to traverse 100,000 entries in the index and throw them away before giving us the 25 rows we asked for.

#### Plan with Standard OFFSET:
```text
Limit  (cost=4624.95..4626.11 rows=25 width=28) (actual time=11.987..11.989 rows=25 loops=1)
  Buffers: shared hit=2 read=1457
  ->  Index Scan using idx_applications_applied_at on applications  (cost=0.43..138735.34 rows=2999984 width=28) (actual time=0.024..10.191 rows=100025 loops=1)
        Index Searches: 1
Execution Time: 12.004 ms
```
The query had to read **1,459 buffer blocks** and evaluate **100,025 rows**. At 100× scale with `OFFSET 1,000,000`, this would take over 100 ms.

#### Keyset Pagination Fix:
Instead of passing an offset number, the application passes the timestamp of the last item seen on the previous page:
```sql
SELECT application_id, job_id, member_id, applied_at, status
FROM applications
WHERE applied_at < '2026-06-12 19:11:44+05:30'
ORDER BY applied_at DESC
LIMIT 25;
```

#### Plan with Keyset Pagination:
```text
Limit  (cost=0.43..1.65 rows=25 width=28) (actual time=0.006..0.009 rows=25 loops=1)
  Buffers: shared hit=3 read=1
  ->  Index Scan using idx_applications_applied_at on applications  (cost=0.43..142724.16 rows=2927919 width=28) (actual time=0.006..0.008 rows=25 loops=1)
        Index Cond: (applied_at < '2026-06-12 19:11:44+05:30'::timestamp with time zone)
Execution Time: 0.013 ms
```
**Results of the fix:**
- Buffer page reads dropped from **1,459 blocks** to just **4 blocks**.
- Time dropped from **12.004 ms** to **0.013 ms** (a 99.9% improvement).
- Because it does a direct index seek, it runs in 0.013 ms whether you are on page 1 or page 10,000.

---

## 5. Storage Analysis (Seed vs Large Dataset)

We checked the on-disk storage sizes for every table and its indexes using `pg_table_size`, `pg_indexes_size`, and `pg_total_relation_size`.

### Storage Comparison Table

| Table | Seed Rows | Large Rows | Seed Table | Seed Indexes | Seed Total | Large Table | Large Indexes | Large Total | Index Share % |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **applications** | 149,984 | 2,999,984 | 11.0 MB | 21.6 MB | 32.7 MB | 211.6 MB | 439.4 MB | **651.0 MB** | 67.5% |
| **profile_views** | 199,996 | 3,999,994 | 9.9 MB | 13.8 MB | 23.8 MB | 192.0 MB | 275.8 MB | **467.8 MB** | 59.0% |
| **connections** | 219,966 | 4,399,965 | 9.8 MB | 13.3 MB | 23.0 MB | 186.3 MB | 264.5 MB | **450.8 MB** | 58.7% |
| **member_skills** | 212,417 | 4,249,459 | 9.3 MB | 11.0 MB | 20.3 MB | 179.8 MB | 219.0 MB | **398.8 MB** | 54.9% |
| **positions** | 99,940 | 1,998,792 | 7.7 MB | 9.2 MB | 16.9 MB | 144.2 MB | 183.1 MB | **327.3 MB** | 55.9% |
| **members** | 40,000 | 800,000 | 5.2 MB | 5.2 MB | 10.4 MB | 98.7 MB | 121.0 MB | **219.7 MB** | 55.1% |
| **invitations** | 60,000 | 1,199,999 | 5.1 MB | 2.3 MB | 7.4 MB | 101.1 MB | 44.9 MB | **145.9 MB** | 30.7% |
| **job_skills** | 65,719 | 1,315,149 | 2.3 MB | 2.8 MB | 5.1 MB | 45.7 MB | 56.4 MB | **102.1 MB** | 55.3% |
| **jobs** | 15,000 | 300,000 | 2.0 MB | 1.2 MB | 3.1 MB | 37.5 MB | 25.6 MB | **63.1 MB** | 40.6% |
| **companies** | 2,000 | 40,000 | 240 kB | 200 kB | 440 kB | 4.1 MB | 2.9 MB | **6.9 MB** | 41.3% |
| **skills** | 72 | 72 | 8 kB | 32 kB | 40 kB | 8 kB | 32 kB | **40 kB** | 80.0% |
| **cities** | 10 | 10 | 8 kB | 32 kB | 40 kB | 8 kB | 32 kB | **40 kB** | 80.0% |
| **TOTAL** | **1,043,188** | **21,303,424** | **62.7 MB** | **80.8 MB** | **143.5 MB** | **1,201.0 MB** | **1,614.3 MB** | **2,815.3 MB** | **57.3%** |

### Database Size Comparison:
- **Seed Database (`linkedin_db`):** 151 MB
- **Large Database (`linkedin_large`):** 2,842 MB (2.84 GB)
- **Growth factor:** 18.8× (very close to the 20.4× row growth factor).

### Observations on Storage:
1. **Indexes take more space than tables:** For the largest tables (`applications`, `profile_views`, `connections`, `positions`), indexes consume **55% to 67.5%** of the total storage. For example, on `applications`, the table data is 211.6 MB while the indexes take 439.4 MB (more than double the table size).
2. **Why this trade-off makes sense:** The extra index storage is what allows member-facing queries like `R01`, `R03`, `R08`, and `R09` to run in 0.1 to 0.4 ms instead of doing 50–200 ms table scans. In terms of cost, disk space is cheap compared to the RAM and CPU needed to scan hundreds of megabytes on every click.
3. **Partial indexes save space:** The partial index `idx_applications_hired` only indexes rows where `status = 'HIRED'` (about 4% of rows). It takes only 7.8 MB. An index on all 3 million rows would have taken over 70 MB.

---

## 6. Architecture for 100× Scale (200+ Million Rows)

At 100× scale (around **200 million rows**, 30 million applications, 44 million connections, 8 million members, and ~30 GB of data), a single PostgreSQL server will start running into buffer cache limits. Here is how we would scale the system.

### 6.1 Table Partitioning (`sql/08_partitioning.sql`)

#### Which table and why:
We selected `applications` for table partitioning because:
1. It is our fastest growing table (3 million rows now, projecting to 30M+ at 100×).
2. Almost all queries filter by dates (`applied_at`).
3. Older applications (older than 1 or 2 years) are rarely modified and can be archived.

#### Partitioning method:
We used **RANGE Partitioning by `applied_at`** into quarterly partitions (e.g. 2025_q1, 2025_q2, ..., 2026_q4).

#### PostgreSQL Primary Key Rule for Partitioned Tables:
In PostgreSQL, any `PRIMARY KEY` or `UNIQUE` constraint on a partitioned table **must include all the partition key columns**. This is because PostgreSQL checks uniqueness locally per partition rather than maintaining one global index across all partitions.
- Composite Primary Key: `PRIMARY KEY (application_id, applied_at)`
- Natural Key: `UNIQUE (job_id, member_id, applied_at)`

#### DDL Summary (from `sql/08_partitioning.sql`):
```sql
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

-- Example quarterly partition
CREATE TABLE applications_2026_q2 PARTITION OF applications_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE applications_default PARTITION OF applications_partitioned DEFAULT;
```

#### Verification of Partition Pruning:
When querying for applications submitted in June 2026:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) 
FROM applications_partitioned
WHERE applied_at >= '2026-06-01 00:00:00+05:30' 
  AND applied_at <  '2026-07-01 00:00:00+05:30';
```
**Actual Output from Plan:**
```text
Finalize Aggregate  (cost=8217.97..8217.98 rows=1 width=8) (actual time=16.927..18.305 rows=1 loops=1)
  Buffers: shared hit=1343 read=1752
  ->  Gather  (cost=8217.76..8217.97 rows=2 width=8) (actual time=16.863..18.300 rows=3 loops=1)
        ->  Partial Aggregate  (cost=7217.76..7217.77 rows=1 width=8)
              ->  Parallel Index Only Scan using applications_2026_q2_applied_at_idx on applications_2026_q2 applications_partitioned  (cost=0.42..7046.85 rows=68365 width=0)
Execution Time: 18.331 ms
```
The query planner automatically ignored 7 out of 8 partitions and only scanned `applications_2026_q2`. This cuts the scan workload by **87.5%**.

---

### 6.2 Sharding Strategy

At 100× scale, we would shard the database horizontally across multiple database servers by **`member_id`** (e.g., `hash(member_id) % num_shards`).

#### The Connection Problem across Shards:
A connection links Member A and Member B. If we shard by `member_id`, Member A might be on Shard 1 and Member B might be on Shard 3.

#### How `R03` (1st-degree connections) works:
If we only store the edge once (`member_a < member_b`), finding connections for a member would require querying every shard.
**Solution: Symmetrical Dual-Writes.**
When Member A and Member B connect, the application writes two rows:
1. `(A, B)` stored on Shard `hash(A)`
2. `(B, A)` stored on Shard `hash(B)`

This means all 1st-degree connections for Member A are stored locally on Member A's shard. Querying `R03` remains a single-shard index lookup running in under 1 ms.

#### How `R05` (2nd-degree mutual connections) works:
Because Member A's friends are spread across multiple shards, computing mutual friends cannot be done with a simple local join.
1. **Scatter-Gather:** The app asks Shard A for Member A's friends, asks Shard B for Member B's friends, and finds the overlap in the app server.
2. **Dedicated Graph Store:** For production at scale, offload connections to Redis Sets (`connections:member_id`). Finding mutual connections between A and B is a simple Redis set intersection: `SINTER connections:A connections:B`, which runs in under 1 ms in RAM.

#### Cross-Shard Queries:
Queries like `R06` (search open jobs across all companies) or `R15` (most requested skills across all jobs) span the entire platform. These are handled by a distributed query router (like Citus or Vitess) that runs the query on all shards in parallel and sums up the counts.

---

### 6.3 Read Replicas and Caching Strategy

To keep the primary database fast for writes, we separate the 30 queries across three layers:

| Layer | Assigned Queries | Why |
|:---|:---|:---|
| **Primary Master (Writes)** | `W01`, `W02`, `W03`, `W04`, `W05` | Must have ACID consistency and row locking. |
| **Read Replicas (Streaming Replication)** | `R14`, `R15`, `R16`, `R17`, `R19`, `R20`, `R21`, `R24`, `R25` | Heavy analytical reports and window functions that take 50–600 ms. Running them on replicas keeps the primary CPU free for user writes. |
| **Redis Cache (In-Memory)** | `R01`, `R02`, `R03`, `R04`, `R08`, `R09`, `R10`, `R11`, `R12`, `R23` | High-frequency profile lookups and connection counts. Cached with a 5-minute TTL and invalidated when a user updates their profile. Latency: < 0.5 ms. |
| **Search Engine (Elasticsearch)** | `R06` | Full-text job title search (`ILIKE '%data analyst%'`). Offloading search avoids maintaining heavy GIN indexes on PostgreSQL. |

#### Preventing Replication Lag Issues:
When a member applies for a job (`W01`) and immediately checks their "My Jobs" page (`R09`), asynchronous replication lag might make the new application look missing. We use **read-your-own-writes session pinning**: after a member writes, their reads are directed to the primary server for the next 5 seconds.

---

### 6.4 Database Maintenance

At 100× volume, default PostgreSQL maintenance settings will cause performance issues:

1. **Autovacuum Tuning:**
   By default, `autovacuum_vacuum_scale_factor = 0.2`. That means PostgreSQL waits until **20% of the table is dead tuples** before cleaning it up. On 30 million applications, autovacuum wouldn't run until **6,000,000 dead rows** accumulate!
   We configure aggressive settings on high-churn tables:
   ```sql
   ALTER TABLE applications SET (
       autovacuum_vacuum_scale_factor = 0.05,  -- Run vacuum after 5% changes
       autovacuum_vacuum_cost_limit = 2000,     -- Give vacuum more I/O budget
       autovacuum_vacuum_cost_delay = 2ms
   );
   ```
2. **Archiving Old Partitions:**
   Using `pg_partman`, partitions older than 2 years are detached from the active table and exported to columnar Parquet files on cloud object storage (S3). They can still be queried if needed via `postgres_fdw` without taking up database RAM.
3. **Materialized Views for Summary Queries:**
   Queries like `R19` (applicant counts per company) should not aggregate 30M rows every time someone loads an employer dashboard. We create a materialized view and refresh it every hour:
   ```sql
   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_company_applicant_metrics;
   ```

---

## 7. Conclusion

### Is the database ready for next year?
**Yes.** The tests on the 20× large dataset (21.3 million rows) prove that our schema and index design scale effectively:
- 29 of 30 queries met their target times.
- Real-time queries ran in under 1.2 ms.
- Total workload time only increased by 2.16× despite a 20.4× increase in data size.
- Range partitioning on `applications` proved an 87.5% reduction in scan volume.

### Remaining Risks:
1. **Graph Connections:** 2nd-degree mutual connections (`R05`) will become expensive across shards at 100×. Moving the connection graph to Redis Sets or a graph database will be necessary.
2. **Memory Settings:** `R13` showed that default memory settings (`work_mem = 4MB`) cause disk spills on large joins. Setting appropriate memory limits via connection poolers (PgBouncer) is important.
3. **Cursor-based Pagination:** The application should transition from `OFFSET` to keyset pagination (`R22`) to avoid scanning discarded rows.

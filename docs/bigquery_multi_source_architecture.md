# BigQuery Architecture — Multi-Source Dashboard

## Diagnosis

`NULL AS field` is not the core problem — it only indicates that the tables have different schemas, while `UNION ALL` requires the same number of columns, the same order, and compatible types.

**The architectural problem:** running all that normalization again on every dashboard load.

---

## Layered Architecture

```
Source tables
      ↓
Staging per source
      ↓
Unified incremental table
      ↓
Dashboard-specific aggregated tables
      ↓
Dashboard
```

---

## 1. Define the Grain

First determine what one row represents:

> 1 row = 1 date + 1 artist + 1 track + 1 platform

- If all tables share the same grain → `UNION ALL` is appropriate
- If one table holds daily data per track and another holds monthly data per artist → **do not UNION directly**

In that case, keep separate fact tables:
- `fct_track_daily`
- `fct_artist_monthly`
- `fct_revenue_monthly`

Then combine already-aggregated data in a dashboard-specific table.

---

## 2. Staging per Source

`NULL` handling should be isolated in this layer, not in the dashboard query.

```sql
-- staging/stg_spotify.sql
CREATE OR REPLACE VIEW `project.staging.stg_spotify` AS
SELECT
  DATE(stream_date)                  AS event_date,
  CAST(artist_id AS STRING)          AS artist_id,
  CAST(track_id AS STRING)           AS track_id,
  CAST(streams AS INT64)             AS streams,
  CAST(NULL AS NUMERIC)              AS revenue,
  'spotify'                          AS source,
  updated_at
FROM `project.raw.spotify`;
```

```sql
-- staging/stg_youtube.sql
CREATE OR REPLACE VIEW `project.staging.stg_youtube` AS
SELECT
  DATE(report_date)                        AS event_date,
  CAST(channel_artist_id AS STRING)        AS artist_id,
  CAST(video_track_id AS STRING)           AS track_id,
  CAST(views AS INT64)                     AS streams,
  SAFE_CAST(estimated_revenue AS NUMERIC)  AS revenue,
  'youtube'                                AS source,
  updated_at
FROM `project.raw.youtube`;
```

> **Rule:** always use `CAST(NULL AS NUMERIC) AS revenue` instead of `NULL AS revenue`.
> The explicit CAST locks the schema contract and prevents inconsistent type inference.

---

## 3. Unified Incremental Table

Do not let the dashboard query the views and redo the `UNION ALL`. Write the result to a physical table:

```sql
-- analytics/fct_platform_metrics.sql
CREATE TABLE IF NOT EXISTS `project.analytics.fct_platform_metrics`
(
  event_date  DATE,
  artist_id   STRING,
  track_id    STRING,
  streams     INT64,
  revenue     NUMERIC,
  source      STRING,
  updated_at  TIMESTAMP
)
PARTITION BY event_date
CLUSTER BY artist_id, source, track_id
OPTIONS (
  require_partition_filter = TRUE
);
```

- **Partition** → most-filtered column in date ranges (`event_date`)
- **Clustering** → most-filtered fields in dashboard queries (`artist_id`, `source`, `track_id`)
- Filtering on the partition column lets BigQuery prune partitions and scan less data

---

## 4. Incremental Update with MERGE

If sources can backfill late data, reprocess a rolling window (e.g., last 7 days):

```sql
MERGE `project.analytics.fct_platform_metrics` AS target
USING (
  SELECT *
  FROM `project.staging.stg_spotify`
  WHERE event_date >= DATE_SUB(@run_date, INTERVAL 7 DAY)

  UNION ALL

  SELECT *
  FROM `project.staging.stg_youtube`
  WHERE event_date >= DATE_SUB(@run_date, INTERVAL 7 DAY)
) AS source
ON  target.event_date = source.event_date
AND target.artist_id  = source.artist_id
AND target.track_id   = source.track_id
AND target.source     = source.source

WHEN MATCHED THEN
  UPDATE SET
    streams    = source.streams,
    revenue    = source.revenue,
    updated_at = source.updated_at

WHEN NOT MATCHED THEN
  INSERT (event_date, artist_id, track_id, streams, revenue, source, updated_at)
  VALUES (source.event_date, source.artist_id, source.track_id,
          source.streams, source.revenue, source.source, source.updated_at);
```

> For immutable, append-only sources → a plain incremental `INSERT` is simpler and usually cheaper than `MERGE`.

This query can run as a **Scheduled Query** in BigQuery — the scheduler natively supports DDL and DML.

---

## 5. Dashboard Aggregated Table

The dashboard likely does not need every individual row. Pre-aggregate at the level used by your charts:

```sql
-- marts/dashboard_artist_daily.sql
CREATE OR REPLACE TABLE `project.marts.dashboard_artist_daily`
PARTITION BY event_date
CLUSTER BY artist_id, source
AS
SELECT
  event_date,
  artist_id,
  source,
  SUM(streams)             AS streams,
  SUM(revenue)             AS revenue,
  COUNT(DISTINCT track_id) AS tracks
FROM `project.analytics.fct_platform_metrics`
GROUP BY
  event_date,
  artist_id,
  source;
```

The dashboard then runs only:

```sql
SELECT
  event_date,
  source,
  streams,
  revenue
FROM `project.marts.dashboard_artist_daily`
WHERE event_date BETWEEN @start_date AND @end_date
  AND artist_id = @artist_id;
```

> **This is the key improvement:** the heavy lifting happens during the pipeline run, not during user interaction.

---

## Directory Structure (dbt / Dataform)

```
definitions/
├── staging/
│   ├── stg_spotify.sqlx
│   ├── stg_youtube.sqlx
│   └── stg_apple.sqlx
├── intermediate/
│   └── int_platform_metrics.sqlx
├── marts/
│   └── dashboard_artist_daily.sqlx
└── assertions/
    └── metrics_quality.sqlx
```

---

## Recommended Tooling

| Phase | Tool | Reason |
|-------|------|--------|
| Start now | **Scheduled Query** (BigQuery native) | Zero infra, no extra cost |
| Scale up | **dbt** or **Dataform** | Versioning, tests, dependencies, `ref()` |

---

## What NOT to Choose Initially

### Plain View
Improves organization but **does not necessarily improve speed** — the transformation still runs every time the dashboard queries the view.

### Materialized View
Can help with specific aggregations, but not as a first solution for complex normalization across multiple sources. It has query restrictions and incremental behavior limitations; changes to any join table may invalidate incremental reuse.

### BI Engine as the primary solution
Should come **after** modeling, partitioning, and pre-aggregation. It accelerates the final query layer; it does not fix a poorly modeled pipeline. Wildcard queries do not benefit from BI Engine acceleration.

---

## Decisions to Confirm

| Question | Impact |
|----------|--------|
| Can sources send late data beyond 7 days? | Defines the MERGE window |
| Does the dashboard need `track_id` granularity? | Defines whether the mart aggregates or keeps detail |
| Do sources have important exclusive fields? | Defines whether to use a `JSON` column or separate detail tables |

---

## Final Recommendation

```
Staging views per source
        ↓
Unified physical table — incremental (partitioned + clustered)
        ↓
Dashboard aggregated table
        ↓
BI Engine (optional, later)
```

The unified table should have a **canonical schema** with shared fields plus a `source` column. Fields exclusive to one source should stay in separate detail tables or a `JSON` column, rather than growing a wide table full of null values indefinitely.

> **Trade-off:** slightly more storage and update lag → much simpler, predictable, and fast dashboard queries.

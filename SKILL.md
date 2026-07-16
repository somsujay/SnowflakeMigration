---
name: teradata-migration
description: "Migrate Teradata SQL DDL and stored procedures to Snowflake with Medallion Architecture. Use when: user says 'migrate teradata', 'convert teradata', 'teradata to snowflake', 'migrate ETL', 'convert procedures'. Triggers: teradata, migration, convert, snowflake migration, medallion."
---

# Teradata to Snowflake Migration (Medallion Architecture)

Converts Teradata SQL DDL, stored procedures, and ETL logic into Snowflake-compatible SQL organized in a RAW/CLEAN/CONFORMED Architecture.

## Target Database: FINANCE_CORE_DEV

## Source Scripts

### `Teradata_Scripts/ecom_booking/ECOMM_Teradata_DDL.sql`
1. **1 Staging Table**: FinMADRStage_Prod.Stg_Ecomm_Bookings (57 columns)
2. **1 Final Table**: FinMADR_Prod.Ecomm_Bookings_tbl (45+ columns)
3. **1 Log Table**: FinMADR_Prod.ExecutionLog
4. **5 Views**: gds_Rcpt_item, gds_RcptHdr, Rp_SalesMonitor_IntrnlShpr, vw_Dim_Global_Product, rptOrderDetail
5. **2 Stored Procedures**: usp_LogMessage (logging utility), usp_Load_Ecomm_Bookings (main ETL with business day logic, currency conversion, FX rates)

## Architecture Mapping

| Layer | Schema | Contents |
|-------|--------|----------|
| **Raw** | `RAW` | Raw staging tables (1:1 from source + `_LOADED_AT` metadata), logging infrastructure |
| **Clean** | `CLEAN` | Cleansed dimensions, reference views, transformed/currency-converted intermediate tables |
| **Conformed** | `CONFORMED` | Business-ready facts (transaction detail + pre-aggregated rollups), orchestrator procedures |

## Procedure Layering Pattern

Stored procedures MUST be separated by layer responsibility:

```
CONFORMED.USP_ORCHESTRATE_<name>    ← Entry point / orchestrator
  └─► CLEAN.USP_TRANSFORM_<name>    ← Currency conversion, FX, business rules
        └─► RAW.USP_LOAD_STG_<name> ← Raw data extraction only
```

| Layer | Procedure Prefix | Responsibility |
|-------|-----------------|----------------|
| **Raw** | `RAW.USP_LOAD_STG_*` | Raw extraction from source views, date range logic, NO transformations |
| **Clean** | `CLEAN.USP_TRANSFORM_*` | Calls Raw, then applies currency conversions, FX rates, recalculations |
| **Conformed** | `CONFORMED.USP_ORCHESTRATE_*` | Calls Clean, determines date range, DELETE+INSERT into Conformed final table |

**Logging:** Uses Snowflake native `SYSTEM$LOG_INFO()` / `SYSTEM$LOG_ERROR()` with an event table (`RAW.ETL_EVENTS`). No custom logging procedure.

**Key rules:**
- Raw procs write ONLY to `RAW.*` tables
- Clean procs write ONLY to `CLEAN.*` tables (reads from Raw)
- Conformed procs write ONLY to `CONFORMED.*` tables (reads from Clean)
- The orchestrator in Conformed drives the full pipeline
- Each layer has its own intermediate table (Raw staging → Clean transformed → Conformed final)
- Do NOT use `IN` keyword for procedure parameters in Snowflake SQL scripting

## Workflow

### Step 1: Analyze Source Script

Read the Teradata SQL and identify all platform-specific constructs:

| Teradata Construct | Snowflake Equivalent |
|---|---|
| `PRIMARY INDEX (col)` | Remove entirely (Snowflake uses micro-partitions) |
| `MULTISET TABLE`, `FALLBACK`, `JOURNAL`, `CHECKSUM`, `MAP` | Remove entirely |
| `CHARACTER SET LATIN NOT CASESPECIFIC` | Remove (Snowflake default) |
| `FORMAT 'yyyy-mm-dd'` on DATE/DECIMAL | Remove |
| `BYTEINT` | `TINYINT` |
| `REPLACE PROCEDURE` | `CREATE OR REPLACE PROCEDURE ... RETURNS STRING LANGUAGE SQL` |
| `REPLACE VIEW` / `LOCKING ROW FOR ACCESS` | `CREATE OR REPLACE VIEW` (remove LOCKING) |
| `UPDATE D FROM S WHERE ... SET ...` | `UPDATE D SET ... FROM S WHERE ...` (rewrite join-update) |
| `EXTRACT(DOW FROM date)` | `DAYOFWEEK(date)` |
| `DATE(timestamp)` | `timestamp::DATE` or `TO_DATE(timestamp)` |
| `INTERVAL '1' DAY` | `DATEADD(DAY, 1, date)` |
| `DECLARE var TYPE; SET var = ...` | `LET var TYPE := ...` (Snowflake Scripting) |
| `ADD_MONTHS(date, n)` | `DATEADD(MONTH, n, date)` |
| `date - EXTRACT(DAY FROM date) + 1` | `DATE_TRUNC('MONTH', date)` |
| `SYS_CALENDAR.CalENDar` / `day_of_week` | `DAYOFWEEK()` function inline |
| `DBC.SysExecSQL(sql)` | `EXECUTE IMMEDIATE` or direct SQL |
| `DBC.SessionInfoV` (session user) | `CURRENT_USER()` |
| `ACTIVITY_COUNT` | `SQLROWCOUNT` |
| `COLLECT STATISTICS` | Remove (Snowflake auto-manages) |
| `DELETE FROM table ALL` | `TRUNCATE TABLE table` |
| `oreplace(str, old, new)` | `REPLACE(str, old, new)` |
| `WHILE L1: ... ITERATE L1` | `WHILE ... DO ... CONTINUE ... END WHILE` |
| `DECLARE EXIT HANDLER FOR SQLEXCEPTION` | `EXCEPTION WHEN OTHER THEN` |
| `SIGNAL ProcError` | `RAISE` |
| `IN param_name TYPE` (procedure params) | `param_name TYPE` (no IN keyword) |
| Positional `GROUP BY 1, 2` | Supported in Snowflake (no change needed) |
| `DATE '9999-12-31'` literal | `'9999-12-31'::DATE` |
| `DROP TABLE X;` (no IF EXISTS) | `DROP TABLE IF EXISTS X;` |
| `BEGIN ... END` procedure body | `BEGIN ... END` with `RETURNS STRING LANGUAGE SQL AS $$` wrapper |

**STOP**: Present analysis and confirm which objects to migrate.

### Step 2: Convert DDL (Layers)

Organize tables into schemas:

**Raw** (`RAW.*`):
- `CREATE OR REPLACE TABLE` for staging tables
- Add `_LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()` metadata column
- Remove `PRIMARY INDEX`

**Clean** (`CLEAN.*`):
- Reference views, cleansed/transformed intermediate tables

**Conformed** (`CONFORMED.*`):
- Final business-ready tables with `CLUSTER BY` for partition pruning

**STOP**: Show converted DDL for review.

### Step 3: Convert Stored Procedures

Apply these transformations to each procedure:

#### 3a. Procedure Wrapper
```sql
-- Teradata
REPLACE PROCEDURE proc_name(param TYPE)
BEGIN ... END;

-- Snowflake
CREATE OR REPLACE PROCEDURE SCHEMA.proc_name(param TYPE)
RETURNS STRING LANGUAGE SQL AS
BEGIN ... RETURN 'Success'; END;
```

#### 3b. UPDATE...FROM (Join Update)
```sql
-- Teradata: UPDATE D FROM S WHERE ... SET ...
-- Snowflake: UPDATE D SET ... FROM S WHERE ...
```

#### 3c. Variable References in Procedures
- Parameters/variables use `:param` colon prefix inside SQL statements
- No colon needed in SET assignments or WHILE conditions

#### 3d. Date Functions
- `EXTRACT(DOW FROM date)` -> `DAYOFWEEK(date)`
- `DATE(timestamp)` -> `timestamp::DATE`
- `SET CurrDate = CurrDate + INTERVAL '1' DAY` -> `CurrDate := DATEADD(DAY, 1, :CurrDate);`

#### 3e. Cross-Schema References (Procedure Layering)
- Procedures in RAW read from `CLEAN.*` views, write to `RAW.*`
- Procedures in CLEAN read from `RAW.*`, write to `CLEAN.*`
- Procedures in CONFORMED read from `CLEAN.*`, write to `CONFORMED.*`
- Conformed orchestrator calls Clean proc, which calls Raw proc
- Each layer writes ONLY to its own schema

**STOP**: Show converted procedures for review.

### Step 4: Create Orchestration

Convert the orchestrator procedure:
```sql
CREATE OR REPLACE PROCEDURE CONFORMED.USP_ORCHESTRATE_ECOMM_BOOKINGS(...)
RETURNS STRING LANGUAGE SQL AS
BEGIN
    -- Clean layer (calls Raw internally)
    CALL CLEAN.USP_TRANSFORM_ECOMM_BOOKINGS(...);
    -- Conformed: DELETE+INSERT into final table
    ...
    RETURN 'Orchestration completed successfully';
END;
```

**STOP**: Confirm orchestration approach.

### Step 5: Generate Output Files

Write all converted SQL to `Snowflake_Scripts/ecom_booking/`:

| File | Contents |
|------|----------|
| `ECOMM_01_setup_schemas.sql` | CREATE SCHEMA for RAW, CLEAN, CONFORMED |
| `ECOMM_02_raw_tables.sql` | STG_ECOMM_BOOKINGS DDL |
| `ECOMM_03_clean_views.sql` | 5 source views + ECOMM_BOOKINGS_TRANSFORMED table |
| `ECOMM_04_conformed_tables.sql` | ECOMM_BOOKINGS_TBL with CLUSTER BY |
| `ECOMM_05a_raw_procedures.sql` | USP_LOAD_STG_ECOMM_BOOKINGS (raw extract) |
| `ECOMM_05b_clean_procedures.sql` | USP_TRANSFORM_ECOMM_BOOKINGS (currency/FX transforms) |
| `ECOMM_05c_conformed_procedures.sql` | USP_ORCHESTRATE_ECOMM_BOOKINGS (final load orchestrator) |

**STOP**: Confirm file output location.

### Step 6: Deploy and Validate

1. Set target database: `USE DATABASE FINANCE_CORE_DEV`
2. Set warehouse: `USE WAREHOUSE <wh_name>`
3. Execute scripts in order (ECOMM_01 -> ECOMM_05c)
4. Verify with `SHOW TABLES`, `SHOW PROCEDURES`, `SHOW VIEWS`
5. Run ETL: `CALL CONFORMED.USP_ORCHESTRATE_ECOMM_BOOKINGS(...)`

**STOP**: Get explicit approval before executing DDL against Snowflake.

## Conversion Reference

### Procedure Conversion Checklist

- [ ] `REPLACE PROCEDURE` -> `CREATE OR REPLACE PROCEDURE`
- [ ] Added `RETURNS STRING LANGUAGE SQL AS $$`
- [ ] Removed `IN` keyword from parameter declarations
- [ ] `UPDATE...FROM` rewritten with SET before FROM
- [ ] All parameter references use `:param` inside SQL statements
- [ ] All variable references use `:var` inside SQL statements
- [ ] `DATE(x)` -> `x::DATE`
- [ ] `EXTRACT(DOW FROM x)` -> `DAYOFWEEK(x)`
- [ ] `INTERVAL '1' DAY` -> `DATEADD()`
- [ ] `ADD_MONTHS(date, n)` -> `DATEADD(MONTH, n, date)`
- [ ] `ACTIVITY_COUNT` -> `SQLROWCOUNT`
- [ ] `SYS_CALENDAR` lookups -> `DAYOFWEEK()` inline
- [ ] `DBC.SysExecSQL` -> direct SQL or `EXECUTE IMMEDIATE`
- [ ] `DBC.SessionInfoV` -> `CURRENT_USER()`
- [ ] `COLLECT STATISTICS` -> removed
- [ ] `DELETE ... ALL` -> `TRUNCATE TABLE`
- [ ] `oreplace()` -> `REPLACE()`
- [ ] `WHILE L1: ... ITERATE L1` -> `WHILE ... DO ... CONTINUE ... END WHILE`
- [ ] `DECLARE EXIT HANDLER` -> `EXCEPTION WHEN OTHER THEN`
- [ ] `SIGNAL ProcError` -> `RAISE`
- [ ] Added `RETURN 'Success';` before final `END;`
- [ ] Cross-schema references qualified (`RAW.*`, `CLEAN.*`, `CONFORMED.*`)
- [ ] Procedure placed in correct layer (Raw=extract, Clean=transform, Conformed=orchestrate)
- [ ] Semicolons correct (no double `;;`)

## Stopping Points

- After Step 1: Confirm which objects to migrate
- After Step 2: Review converted DDL
- After Step 3: Review converted procedures
- After Step 4: Confirm orchestration approach
- After Step 5: Confirm output file locations
- After Step 6: Approve before deploying to Snowflake

## Output

- SQL files in `Snowflake_Scripts/ecom_booking/` implementing full architecture:
  - `ECOMM_01`–`ECOMM_05c` prefixed files (staging, views, transforms, orchestrator)
- Procedures separated by layer:
  - Raw: raw extraction (`USP_LOAD_STG_*`)
  - Clean: transformation (`USP_TRANSFORM_*`)
  - Conformed: orchestration (`USP_ORCHESTRATE_*`)
- Native logging via `SYSTEM$LOG_INFO`/`SYSTEM$LOG_ERROR` → `RAW.ETL_EVENTS` event table
- Target database: `FINANCE_CORE_DEV`
- Validated syntax and deployed objects in target Snowflake database

---
name: teradata-migration
description: "Migrate Teradata SQL DDL and stored procedures to Snowflake with Medallion Architecture. Use when: user says 'migrate teradata', 'convert teradata', 'teradata to snowflake', 'migrate ETL', 'convert procedures'. Triggers: teradata, migration, convert, snowflake migration, medallion."
---

# Teradata to Snowflake Migration (Medallion Architecture)

Converts Teradata SQL DDL, stored procedures, and ETL logic into Snowflake-compatible SQL organized in a Bronze/Silver/Gold Medallion Architecture with Snowpipe ingestion and PII masking policies.

## Source Script Structure

The Teradata source (`Teradata_Scripts/teradata_dwh_etl.sql`) contains:
1. **3 Staging Tables**: T_Customer, T_Account, T_Transaction
2. **4 Dimension Tables**: DimCustomer (SCD-2), DimAccount (SCD-1), DimTransactionType, DimDate
3. **2 Fact Tables**: FactDailyTransaction, FactDailyAgg
4. **7 Stored Procedures**: SCD-2 customer load (2 procs), SCD-1 account merge, transaction type load, date dimension population, fact loads, and master orchestration

## Medallion Architecture Mapping

| Layer | Schema | Contents |
|-------|--------|----------|
| **Bronze** | `BRONZE` | Raw staging tables (1:1 from source + `_LOADED_AT` metadata) |
| **Silver** | `SILVER` | Cleansed dimensions (SCD-2 customer, SCD-1 account, lookup dims) |
| **Gold** | `GOLD` | Business-ready facts (transaction detail + pre-aggregated rollups) |
| **Governance** | `GOVERNANCE` | Masking policies, data quality log, cleansing & validation procedures |

## Workflow

### Step 1: Analyze Source Script

Read the Teradata SQL and identify all platform-specific constructs:

| Teradata Construct | Snowflake Equivalent |
|---|---|
| `PRIMARY INDEX (col)` | Remove entirely (Snowflake uses micro-partitions) |
| `REPLACE PROCEDURE` | `CREATE OR REPLACE PROCEDURE ... RETURNS STRING LANGUAGE SQL` |
| `UPDATE D FROM S WHERE ...` | `UPDATE D SET ... FROM S WHERE ...` (rewrite join-update) |
| `EXTRACT(DOW FROM date)` | `DAYOFWEEK(date)` |
| `DATE(timestamp)` | `timestamp::DATE` or `TO_DATE(timestamp)` |
| `INTERVAL '1' DAY` | `DATEADD(DAY, 1, date)` |
| `DECLARE var TYPE; SET var = ...` | `LET var TYPE := ...` (Snowflake Scripting) |
| Positional `GROUP BY 1, 2` | Supported in Snowflake (no change needed) |
| `DATE '9999-12-31'` literal | `'9999-12-31'::DATE` |
| `DROP TABLE X;` (no IF EXISTS) | `DROP TABLE IF EXISTS X;` |
| `BEGIN ... END` procedure body | `BEGIN ... END` with `RETURNS STRING LANGUAGE SQL AS` wrapper |

**STOP**: Present analysis and confirm which objects to migrate.

### Step 2: Convert DDL (Medallion Layers)

Organize tables into schemas:

**Bronze** (`BRONZE.*`):
- `CREATE OR REPLACE TABLE` for staging tables
- Add `_LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()` metadata column
- Remove `PRIMARY INDEX`

**Silver** (`SILVER.*`):
- Dimension tables with optional `CLUSTER BY` on DimDate
- Add `AUTOINCREMENT` surrogate key to DimCustomer (SCD-2)

**Gold** (`GOLD.*`):
- Fact tables with `CLUSTER BY (Date_Key)` for partition pruning

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

#### 3e. Date Dimension (Generator-Based)
Replace WHILE loop with `TABLE(GENERATOR(...))` for set-based performance:
```sql
CREATE OR REPLACE PROCEDURE SILVER.Populate_DimDate(StartDate DATE, EndDate DATE)
RETURNS STRING LANGUAGE SQL AS
BEGIN
    INSERT INTO SILVER.DimDate (Date_Key, Year, Month, Day, Day_Of_Week)
    SELECT
        DATEADD(DAY, seq.seq_val, :StartDate) AS Date_Key,
        YEAR(DATEADD(DAY, seq.seq_val, :StartDate)),
        MONTH(DATEADD(DAY, seq.seq_val, :StartDate)),
        DAY(DATEADD(DAY, seq.seq_val, :StartDate)),
        DAYOFWEEK(DATEADD(DAY, seq.seq_val, :StartDate))
    FROM (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS seq_val
        FROM TABLE(GENERATOR(ROWCOUNT => DATEDIFF(DAY, :StartDate, :EndDate) + 1))
    ) AS seq;
    RETURN 'Populate_DimDate completed';
END;
```

#### 3f. Cross-Schema References
- Procedures in SILVER read from `BRONZE.*`, write to `SILVER.*`
- Procedures in GOLD read from `BRONZE.*`, write to `GOLD.*`

**STOP**: Show converted procedures for review.

### Step 4: Create Orchestration

Convert `Daily_ETL_Run` with cross-schema calls:
```sql
CREATE OR REPLACE PROCEDURE Daily_ETL_Run()
RETURNS STRING LANGUAGE SQL AS
BEGIN
    -- Silver layer
    CALL SILVER.Close_Current_DimCustomer_Record();
    CALL SILVER.Insert_New_DimCustomer_Record();
    CALL SILVER.Load_DimAccount_SCD1();
    CALL SILVER.Load_DimTransactionType();
    -- Gold layer
    CALL GOLD.Load_FactDailyTransaction(CURRENT_DATE);
    CALL GOLD.Load_FactDailyAgg(CURRENT_DATE);
    RETURN 'Daily ETL completed successfully';
END;
```

Optional Snowflake Task for scheduling:
```sql
CREATE OR REPLACE TASK daily_etl_task
  WAREHOUSE = '<warehouse_name>'
  SCHEDULE = 'USING CRON 0 6 * * * America/Toronto'
AS CALL Daily_ETL_Run();
```

**STOP**: Confirm orchestration approach.

### Step 5: Configure Named Stage + Directory Stream Ingestion

Set up automated ingestion into the Bronze layer using a single shared
Named Stage with path-based organization (no cloud event notifications required):

1. Create a shared `FILE FORMAT` (CSV with headers, quoted fields)
2. Create a single named stage with `DIRECTORY = (ENABLE = TRUE)`:
   - `BRONZE.DATA_STAGE` with subdirectories: `/customer/`, `/account/`, `/transaction/`
3. Create a directory table stream to detect new files across all paths:
   - `BRONZE.STREAM_DATA_FILES`
4. Create Tasks (every 5 min, fires only when stream has data):
   - `BRONZE.TASK_LOAD_CUSTOMER` → loads from `@BRONZE.DATA_STAGE/customer/`
   - `BRONZE.TASK_LOAD_ACCOUNT` → loads from `@BRONZE.DATA_STAGE/account/`
   - `BRONZE.TASK_LOAD_TRANSACTION` → loads from `@BRONZE.DATA_STAGE/transaction/`
5. `ALTER TASK ... RESUME` to enable
6. For initial loads: PUT files to subpaths + `ALTER STAGE BRONZE.DATA_STAGE REFRESH` + `EXECUTE TASK ...`
7. For ongoing: PUT files to subpaths + `ALTER STAGE ... REFRESH` (task auto-fires)
8. Clean up: `REMOVE @BRONZE.DATA_STAGE/<subpath>/` after successful loads

**STOP**: Confirm ingestion approach.

### Step 6: Implement Data Quality Framework

Create a `GOVERNANCE` data quality framework with:

1. **Audit Table** (`GOVERNANCE.DATA_QUALITY_LOG`):
   - `log_id`, `run_id`, `check_timestamp`, `table_name`, `check_name`, `severity` (ERROR/WARNING/INFO), `records_failed`, `sample_ids`, `details`

2. **Cleansing Procedure** (`GOVERNANCE.Cleanse_Bronze_Data()`):
   - Trims whitespace from all VARCHAR columns
   - Lowercases email addresses
   - Defaults NULL Currency_Code to 'CAD'
   - Deduplicates rows per PK (keeps latest `_LOADED_AT` using DELETE...USING with MAX)

3. **Validation Procedure** (`GOVERNANCE.Run_Data_Quality_Checks()`):
   - 17 checks across 9 categories: NULL checks, duplicate PKs, email regex, FK integrity (Account→Customer, Transaction→Account), domain validation (Account_Type, Status), amount > 0, no future dates, SCD-2 single-active integrity, fact-dim join orphans
   - Logs all results to `DATA_QUALITY_LOG` with severity classification

4. **Wire into orchestration**:
   - `Daily_ETL_Run()` calls `Cleanse_Bronze_Data()` before Silver processing and `Run_Data_Quality_Checks()` after Gold processing
   - End-to-end shell script has phases 2b, 4b, 5b for validation at each checkpoint

**File**: `Snowflake_Scripts/10_data_quality.sql`

**STOP**: Confirm data quality approach.

### Step 7: Implement PII Masking

Create a `GOVERNANCE` schema with masking policies:

| Policy | Style | Applies To |
|--------|-------|-----------|
| `MASK_NAME` | `J***` (first char + `***`) | FIRST_NAME, LAST_NAME |
| `MASK_EMAIL` | `j***@domain.com` | EMAIL_ADDRESS |
| `MASK_PHONE` | `***-***-0101` (last 4 visible) | PHONE_NUMBER |
| `MASK_LOCATION` | `T***` (first char + `***`) | CITY, STATE_PROVINCE |
| `MASK_FINANCIAL_ID` | `ACCT-***` (prefix + `***`) | ACCOUNT_ID |
| `MASK_AMOUNT` | `0.00` (zeroed) | AMOUNT, TOTAL_AMOUNT |

Access control:
- **SYSADMIN / ACCOUNTADMIN**: See full unmasked data
- **All other roles**: See partially masked values

Apply via:
```sql
ALTER TABLE <table> MODIFY COLUMN <col> SET MASKING POLICY GOVERNANCE.<policy>;
```

**STOP**: Confirm masking approach and which columns to protect.

### Step 7: Generate Output Files

Write all converted SQL to `Snowflake_Scripts/`:

| File | Contents |
|------|----------|
| `01_setup_schemas.sql` | CREATE SCHEMA for BRONZE, SILVER, GOLD, GOVERNANCE |
| `02_bronze_tables.sql` | Staging table DDL with `_LOADED_AT` metadata |
| `03_silver_tables.sql` | Dimension table DDL (SCD-2/SCD-1) |
| `04_gold_tables.sql` | Fact table DDL with clustering |
| `05_silver_procedures.sql` | Dimension load procedures |
| `06_gold_procedures.sql` | Fact load procedures |
| `07_orchestration.sql` | Daily_ETL_Run + optional Task |
| `08_seed_data.sql` | Snowpipe setup (stages, file format, pipes) |
| `09_masking_policies.sql` | PII governance policies + ALTER TABLE assignments |
| `10_data_quality.sql` | Data quality log table, cleansing + validation procedures |

**STOP**: Confirm file output location.

### Step 8: Deploy and Validate

1. Set target database: `USE DATABASE <db_name>`
2. Set warehouse: `USE WAREHOUSE <wh_name>`
3. Execute scripts in order (01 -> 09)
4. Verify with `SHOW TABLES`, `SHOW PROCEDURES`, `SHOW PIPES`
5. Seed DimDate: `CALL SILVER.Populate_DimDate('2020-01-01'::DATE, '2030-12-31'::DATE)`
6. Run ETL: `CALL Daily_ETL_Run()`
7. Validate masking: query as non-admin role

**STOP**: Get explicit approval before executing DDL against Snowflake.

## Conversion Reference

### Procedure Conversion Checklist

- [ ] `REPLACE PROCEDURE` -> `CREATE OR REPLACE PROCEDURE`
- [ ] Added `RETURNS STRING LANGUAGE SQL AS`
- [ ] `UPDATE...FROM` rewritten with SET before FROM
- [ ] All parameter references use `:param` inside SQL statements
- [ ] All variable references use `:var` inside SQL statements
- [ ] `DATE(x)` -> `x::DATE`
- [ ] `EXTRACT(DOW FROM x)` -> `DAYOFWEEK(x)`
- [ ] `INTERVAL '1' DAY` -> `DATEADD()`
- [ ] Added `RETURN 'Success';` before final `END;`
- [ ] Cross-schema references qualified (`BRONZE.*`, `SILVER.*`, `GOLD.*`)
- [ ] Semicolons correct (no double `;;`)

### Sample Data

CSV files in `sample_data_file/`:
- `T_Customer_history.csv` (20 rows) + `T_Customer_incremental.csv` (10 rows)
- `T_Account_history.csv` (35 rows) + `T_Account_incremental.csv` (13 rows)
- `T_Transaction_history.csv` (101 rows) + `T_Transaction_incremental.csv` (31 rows)

### Step 9: Build Gold Views

Create analytical views on top of the Gold fact tables:

| View | Purpose |
|------|---------|
| `GOLD.MonthlySpendProfile` | Monthly spend by customer + type (joins DimCustomer for attributes) |
| `GOLD.TxnTypeTrend` | Portfolio-level transaction type trends (volume, avg spend, unique customers) |

These views inherit masking policies from underlying columns automatically.

### Step 10: Create Streamlit Dashboard

Build a local Streamlit multipage app (`streamlit_app/`) with a main Analytics page and additional pages:

#### Main Page: Analytics (`streamlit_app/Analytics.py`)

4 tabs for Gold layer reporting:

| Tab | Gold Object | Visualizations |
|-----|-------------|---------------|
| **Overview** | FactDailyTransaction | KPI cards, daily volume area chart, type donut |
| **Spend Profile** | MonthlySpendProfile | Top spenders bar chart, detail table |
| **Type Trends** | TxnTypeTrend | Stacked area, grouped bar, avg spend line |
| **Rollup Explorer** | FactDailyAgg | Rollup level selector, daily bar chart, raw data |

#### Page 2: Data Load Stats (`streamlit_app/pages/2_Data_Load_Stats.py`)

2 tabs comparing pipeline load metrics:

| Tab | Content |
|-----|---------|
| **Historical Load** | Baseline row counts from initial history CSV load via internal stages |
| **Incremental Load** | Before/After/Delta comparison with live Snowflake row counts |

#### Page 3: Iceberg Explorer (`streamlit_app/pages/3_Iceberg_Explorer.py`)

4 tabs for local Apache Iceberg table inspection:

| Tab | Content |
|-----|---------|
| **Table Overview** | Summary table + expandable per-table details (metrics, columns, data files) |
| **Snapshot Timeline** | Snapshot history with visual timeline (history vs incremental loads) |
| **Data Files** | All Parquet files with load type labels, row counts, sizes + data preview |
| **Schema Details** | Full Iceberg schema per table (field ID, name, type, required) |

#### Page 4: Data Masking (`streamlit_app/pages/4_Data_Masking.py`)

4 tabs for PII masking policy inspection:

| Tab | Content |
|-----|---------|
| **Policy Overview** | All 6 masking policies with category, style, examples, column counts |
| **Column Assignments** | Full mapping of policies to columns across Bronze/Silver/Gold layers |
| **Policy Details** | Expandable CASE logic body, signature, masked vs unmasked examples |
| **Access Control** | Role matrix, live data preview (current role), simulated masked view |

#### Page 5: Data Quality (`streamlit_app/pages/5_Data_Quality.py`)

3 tabs for data quality monitoring:

| Tab | Content |
|-----|---------|
| **Latest Results** | Dataframe of `DATA_QUALITY_LOG` filtered to latest `run_id`, color-coded by severity |
| **History & Trends** | Stacked bar chart of check results by run + line chart of records flagged over time |
| **By Table** | Per-table quality summary with donut chart of severity distribution |

Action buttons: Run Cleansing, Run Checks, Refresh. Summary metrics: Total Checks, Passed, Warnings, Errors.

Stack: `streamlit`, `snowflake-connector-python`, `pandas`, `plotly`, `pyiceberg[pyarrow]`
Connection: Snowflake Connector via `.streamlit/secrets.toml` (externalbrowser SSO)
Theme: Professional adaptive (gradient banners, styled metrics, themed tabs)

**STOP**: Confirm dashboard requirements with user.

### Step 11: Create Apache Iceberg Tables

Convert sample CSV files into local Apache Iceberg tables using PyIceberg + PyArrow:

**Script**: `scripts/create_iceberg_tables.py`

| Table | Source Files | Total Rows |
|-------|-------------|-----------|
| `t_customer` | T_Customer_history.csv + T_Customer_incremental.csv | 30 |
| `t_account` | T_Account_history.csv + T_Account_incremental.csv | 47 |
| `t_transaction` | T_Transaction_history.csv + T_Transaction_incremental.csv | 130 |

Features:
- Local SQLite file catalog (`iceberg_warehouse/catalog.db`)
- Proper Iceberg schemas (string, date, timestamp, double types)
- Separate snapshots for history and incremental loads (time-travel capable)
- Snapshot-based identification of which Parquet file is history vs incremental
- Output: `iceberg_warehouse/` with Parquet data + Iceberg JSON metadata + Avro manifests

**STOP**: Confirm Iceberg table creation approach.

## Stopping Points

- After Step 1: Confirm which objects to migrate
- After Step 2: Review converted DDL
- After Step 3: Review converted procedures
- After Step 4: Confirm orchestration approach
- After Step 5: Confirm ingestion setup (Task + Directory Stream)
- After Step 6: Confirm data quality approach
- After Step 7: Confirm PII masking approach
- After Step 7: Confirm output file locations
- After Step 8: Approve before deploying to Snowflake
- After Step 9: Review Gold views
- After Step 10: Confirm dashboard requirements
- After Step 11: Confirm Iceberg table creation approach

## Output

- 10 SQL files in `Snowflake_Scripts/` implementing full Medallion Architecture + Data Quality
- Task + Directory Stream for automated Bronze ingestion (no cloud events needed)
- PII masking policies for data governance
- Gold analytical views (MonthlySpendProfile, TxnTypeTrend)
- Streamlit multipage app (`streamlit_app/`):
  - `Analytics.py` — Gold layer reporting dashboard (4 tabs)
  - `pages/2_Data_Load_Stats.py` — Pipeline load statistics (historical + incremental)
  - `pages/3_Iceberg_Explorer.py` — Iceberg table explorer (overview, snapshots, files, schema)
  - `pages/4_Data_Masking.py` — PII masking policy viewer (policies, assignments, access control)
  - `pages/5_Data_Quality.py` — Data quality dashboard (latest results, trends, by-table breakdown)
- Apache Iceberg tables (`scripts/create_iceberg_tables.py` → `iceberg_warehouse/`)
- Validated syntax and deployed objects in target Snowflake database

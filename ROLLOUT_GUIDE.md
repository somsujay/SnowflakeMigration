# New Environment Rollout Guide

## Overview

This guide provides step-by-step instructions to deploy the Finance Data Platform (Teradata-to-Snowflake migration) into a brand new Snowflake environment. The deployment uses **schemachange** for version-controlled migrations with Jinja2 templating for multi-environment support.

**Promotion path:** `dev → qa → preprod → prod`

---

## Prerequisites

### 1. Snowflake Account Access

| Requirement | Detail |
|-------------|--------|
| Account | Snowflake Trial or Enterprise account |
| Role | See role options below |
| Warehouse | At least one X-Small warehouse available |
| Authentication | See authentication options below |

#### Authentication Options

Choose one based on your environment:

**Option A: Key-Pair Authentication (Recommended for CI/CD)**

Most secure for automated deployments. No passwords stored in secrets.

```bash
# Generate RSA key pair
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/ci_key.p8 -nocrypt

# Extract public key
openssl rsa -in ~/.snowflake/ci_key.p8 -pubout -out ~/.snowflake/ci_key.pub

# Assign to Snowflake user
# Run in Snowflake:
# ALTER USER DEPLOY_USER SET RSA_PUBLIC_KEY='<paste public key without headers>';
```

Connection config (`~/.snowflake/connections.toml`):
```toml
[MY_ACCOUNT]
account = "abc12345.us-east-1"
user = "DEPLOY_USER"
authenticator = "SNOWFLAKE_JWT"
private_key_path = "~/.snowflake/ci_key.p8"
warehouse = "COMPUTE_WH"
```

**Option B: Okta SSO (Recommended for Interactive/Enterprise Use)**

Federated authentication via Okta for environments where corporate identity is required. Supports both browser-based (interactive) and programmatic (service account) flows.

*Interactive (developer workstations):*
```toml
[MY_ACCOUNT]
account = "abc12345.us-east-1"
user = "user@company.com"
authenticator = "externalbrowser"
warehouse = "COMPUTE_WH"
```

When a command runs, it opens a browser for Okta SSO login. The session token is cached.

*Programmatic via Okta (CI/CD with Okta service account):*
```toml
[MY_ACCOUNT]
account = "abc12345.us-east-1"
user = "deploy-svc@company.com"
authenticator = "https://your-company.okta.com"
password = "<okta-service-account-password>"
warehouse = "COMPUTE_WH"
```

*Snowflake-side configuration required:*
```sql
-- As ACCOUNTADMIN
-- 1. Create security integration for Okta
CREATE OR REPLACE SECURITY INTEGRATION OKTA_SSO
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'http://www.okta.com/<your-okta-app-id>'
    SAML2_SSO_URL = 'https://your-company.okta.com/app/snowflake/<app-id>/sso/saml'
    SAML2_PROVIDER = 'OKTA'
    SAML2_X509_CERT = '<paste certificate from Okta app>'
    SAML2_SP_INITIATED_LOGIN_PAGE_LABEL = 'Okta SSO'
    SAML2_ENABLE_SP_INITIATED = TRUE;

-- 2. Map Okta user to Snowflake user
CREATE USER IF NOT EXISTS "user@company.com"
    LOGIN_NAME = 'user@company.com'
    DEFAULT_ROLE = DEPLOY_ROLE
    DEFAULT_WAREHOUSE = COMPUTE_WH;

GRANT ROLE DEPLOY_ROLE TO USER "user@company.com";
```

*Okta-side configuration:*
1. Create a SAML 2.0 app in Okta Admin Console for Snowflake
2. Set the ACS URL to: `https://<account>.snowflakecomputing.com/fed/login`
3. Set the Audience URI to: `https://<account>.snowflakecomputing.com`
4. Assign users/groups to the Okta app

> **CI/CD note:** For automated pipelines, Okta native auth (`authenticator = "https://your-company.okta.com"`) works without a browser but requires the Okta service account password in CI secrets. Key-pair auth (Option A) is preferred for CI/CD as it avoids password rotation concerns.

**Option C: Password Authentication (Development Only)**

Simplest but least secure. Avoid for production or CI/CD.

```toml
[MY_ACCOUNT]
account = "abc12345.us-east-1"
user = "DEPLOY_USER"
password = "your-password"
warehouse = "COMPUTE_WH"
```

**Comparison:**

| Method | Interactive | CI/CD | Security | Password Rotation |
|--------|:-----------:|:-----:|----------|-------------------|
| Key-Pair (A) | No | Yes | High — no secrets in transit | No — key-based |
| Okta SSO (B) — browser | Yes | No | High — federated identity | Managed by Okta |
| Okta SSO (B) — programmatic | No | Yes | Medium — password in CI secrets | Okta policy |
| Password (C) | Yes | Possible | Low — password in plaintext | Manual |

#### Role Options

Choose one of the following approaches based on your organization's security posture:

**Option A: Built-in Roles (Simplest)**

Use `SYSADMIN` for object creation and `SECURITYADMIN` for grants. Suitable for trial accounts, dev environments, and small teams.

**Option B: Database Ownership (Recommended)**

A custom role with `OWNERSHIP` on the target database. Provides full DDL control within one database without account-level power. Only 3 grants needed:

```sql
-- As ACCOUNTADMIN (one-time setup)
CREATE ROLE IF NOT EXISTS DEPLOY_ROLE COMMENT = 'Schemachange deployment role';
GRANT OWNERSHIP ON DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEPLOY_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DEPLOY_ROLE;
GRANT ROLE DEPLOY_ROLE TO USER <DEPLOY_USER>;
```

> Note: Add `MANAGE GRANTS ON ACCOUNT` only if `A__grants.sql` assigns privileges to other roles.

**Option C: Least-Privilege Custom Role (Most Secure)**

A fine-grained role with only the specific privileges needed per object type. Use this for production environments with strict audit requirements.

```sql
-- As ACCOUNTADMIN (one-time setup)
CREATE ROLE IF NOT EXISTS DEPLOY_ROLE COMMENT = 'Schemachange deployment role - least privilege';

-- Warehouse access
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEPLOY_ROLE;

-- Database-level (if database already exists)
GRANT ALL PRIVILEGES ON DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE SCHEMA ON DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;

-- Schema-level object creation (existing schemas)
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE PROCEDURE ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE TASK ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE STAGE ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE STREAM ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE FILE FORMAT ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE SEQUENCE ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE FUNCTION ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE MASKING POLICY ON ALL SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;

-- Future schemas (auto-inherit for schemas created by migrations)
GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE PROCEDURE ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE TASK ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE STAGE ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE STREAM ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE FILE FORMAT ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE SEQUENCE ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE FUNCTION ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;
GRANT CREATE MASKING POLICY ON FUTURE SCHEMAS IN DATABASE <TARGET_DB> TO ROLE DEPLOY_ROLE;

-- Account-level privileges
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DEPLOY_ROLE;
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE DEPLOY_ROLE;

-- For A__grants.sql (only if granting to other roles)
-- GRANT MANAGE GRANTS ON ACCOUNT TO ROLE DEPLOY_ROLE;

-- Assign to user
GRANT ROLE DEPLOY_ROLE TO USER <DEPLOY_USER>;
```

**Privilege-to-Script Mapping:**

| Migration Script | Privileges Required |
|-----------------|---------------------|
| `V1.000.100__setup_schemas.sql` | `CREATE SCHEMA ON DATABASE` |
| `V1.050.1xx__create_*_tables.sql` | `USAGE ON SCHEMA` + `CREATE TABLE ON SCHEMA` |
| `V1.900.100__create_masking_policies.sql` | `CREATE MASKING POLICY ON SCHEMA` |
| `R__*_procedures.sql` | `CREATE PROCEDURE ON SCHEMA` |
| `R__*_views.sql` | `CREATE VIEW ON SCHEMA` + `SELECT ON` source tables |
| `R__orchestration.sql` | `CREATE STAGE` + `CREATE STREAM` + `CREATE FILE FORMAT` |
| `R__ingestion_tasks.sql` | `CREATE TASK ON SCHEMA` + `EXECUTE TASK ON ACCOUNT` |
| `R__masking_policies.sql` | `CREATE MASKING POLICY` + `APPLY MASKING POLICY ON ACCOUNT` |
| `A__grants.sql` | `MANAGE GRANTS ON ACCOUNT` (or ownership of granted objects) |

**Comparison:**

| Approach | Grants Needed | Scope | Best For |
|----------|--------------|-------|----------|
| Option A: SYSADMIN | 0 (built-in) | Full account DDL | Dev, trial, small teams |
| Option B: DB Ownership | 3 | Single database | Most production teams |
| Option C: Least-Privilege | ~25 | Specific object types | Regulated/audited environments |

### 2. Local Tooling

```bash
# Python 3.11+
python3 --version

# Install dependencies
pip install -r requirements.txt
# Installs: schemachange>=3.6.0, pyyaml, jinja2

# Snowflake CLI (for smoke tests)
pip install snowflake-cli-labs

# SQL linter (for CI)
pip install sqlfluff
```

### 3. Repository Clone

```bash
git clone <repository-url>
cd SnowflakeMigration
```

---

## Step 1: Configure the New Environment

### 1.1 Add Environment to `environments.yml`

Edit `environments.yml` and add the new environment block:

```yaml
# Example: adding a new "staging" environment
staging:
  database: FINANCE_DB_STAGING
  warehouse: COMPUTE_WH
  connection: MY_STAGING_ACCOUNT
```

**Required fields:**
- `database`: Target database name (will be created if it doesn't exist)
- `warehouse`: Warehouse for running migrations
- `connection`: Snowflake CLI connection name (matches `~/.snowflake/connections.toml`)

### 1.2 Configure Snowflake CLI Connection

Create or edit `~/.snowflake/connections.toml`:

```toml
[MY_STAGING_ACCOUNT]
account = "your-account-locator"
user = "your-username"
authenticator = "SNOWFLAKE_JWT"
private_key_path = "~/.snowflake/rsa_key.p8"
warehouse = "COMPUTE_WH"
```

**For password-based auth** (development only):

```toml
[MY_STAGING_ACCOUNT]
account = "your-account-locator"
user = "your-username"
password = "your-password"
warehouse = "COMPUTE_WH"
```

### 1.3 Set Environment Variables (CI/CD)

For automated deployments, set these in your CI secrets:

```bash
export SNOWFLAKE_ACCOUNT="your-account-locator"
export SNOWFLAKE_USER="your-service-user"
export SNOWFLAKE_PRIVATE_KEY_PATH="~/.snowflake/ci_key.p8"
export SNOWFLAKE_ROLE="SYSADMIN"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
```

---

## Step 2: Create the Target Database

The database must exist before schemachange runs (it cannot create databases via Jinja `{{ database }}`):

```sql
-- Connect as SYSADMIN
USE ROLE SYSADMIN;

-- Create the database
CREATE DATABASE IF NOT EXISTS FINANCE_DB_STAGING
COMMENT = 'Finance Data Platform - Staging Environment';

-- Grant ownership
GRANT OWNERSHIP ON DATABASE FINANCE_DB_STAGING TO ROLE SYSADMIN;
```

Or via Snowflake CLI:

```bash
snow sql -c MY_STAGING_ACCOUNT -q "
  USE ROLE SYSADMIN;
  CREATE DATABASE IF NOT EXISTS FINANCE_DB_STAGING
  COMMENT = 'Finance Data Platform - Staging Environment';
"
```

---

## Step 3: Bootstrap Change History (Optional)

Schemachange auto-creates the history table if `--create-change-history-table` is set (which it is in `deploy_schemachange.sh`). However, for visibility you can pre-create it:

```bash
snow sql -c MY_STAGING_ACCOUNT \
  --database FINANCE_DB_STAGING \
  -f scripts/bootstrap_change_history.sql
```

This creates:
- `METADATA` schema
- `METADATA.SCHEMACHANGE_HISTORY` tracking table

---

## Step 4: Dry-Run Deployment

Always perform a dry-run first to validate all migrations will apply correctly:

```bash
bash scripts/deploy_schemachange.sh --env=staging --dry-run
```

**Expected output:**
```
============================================================
  SCHEMACHANGE DEPLOY TO STAGING (FINANCE_DB_STAGING)
============================================================

Environment:  staging
Database:     FINANCE_DB_STAGING
Warehouse:    COMPUTE_WH
Role:         SYSADMIN
Dry-run:      true

>> Running schemachange...

Scripts to apply:
  V1.000.100__create_infrastructure.sql
  V1.050.100__create_raw_tables.sql          (ecomm)
  V1.050.200__create_clean_tables.sql        (ecomm)
  V1.050.300__create_conformed_tables.sql    (ecomm)
  V1.051.100__create_raw_tables.sql          (ecomm_budget)
  V1.051.200__create_clean_tables.sql        (ecomm_budget)
  V1.051.300__create_conformed_tables.sql    (ecomm_budget)
  V1.052.100__create_raw_tables.sql          (ecomm_actuals)
  V1.052.200__create_clean_tables.sql        (ecomm_actuals)
  V1.052.300__create_conformed_tables.sql    (ecomm_actuals)
  V1.150.100__create_raw_tables.sql          (aftermarket)
  V1.150.200__create_clean_tables.sql        (aftermarket)
  V1.150.300__create_conformed_tables.sql    (aftermarket)
  V1.200.100__create_raw_tables.sql          (uds)
  V1.200.200__create_clean_tables.sql        (uds)
  V1.200.300__create_conformed_tables.sql    (uds)
  V1.800.100__create_orchestration_framework.sql
  V1.900.100__create_masking_policies.sql
  V1.900.101__create_data_quality.sql

============================================================
  DRY-RUN COMPLETE
============================================================
```

**Verify:**
- All versioned scripts (V__) are listed in correct numeric order
- Domain order is respected: platform (000) → ecomm (050) → ecomm_budget (051) → ecomm_actuals (052) → aftermarket (150) → uds (200) → orchestration (800) → governance (900)
- Within each domain: raw (1xx) → clean (2xx) → conformed (3xx)
- No errors about missing variables or syntax issues
- The change history table location is correct

---

## Step 5: Deploy

### 5.1 Run the Deployment

```bash
bash scripts/deploy_schemachange.sh --env=staging
```

**What happens (in order):**

| Step | Version | Domain | Action |
|------|---------|--------|--------|
| 1 | V1.000.100 | _platform | Creates env-prefixed schemas: RAW_DEV, CLEAN_DEV, CONFORMED_DEV, GOVERNANCE_DEV, METADATA |
| 2 | V1.050.100 | ecomm/raw | Creates raw tables: Ecomm_Bookings, BookingsConsol, BookingsConsol_fdm, Raw_ads_bill_line, fdm_forecast_bill_line, fdm_forecast_bill_line_consol_src, Ecomm_Bookings, PDS_Renewals, PDS_Renewals_Daily (9 tables) |
| 3 | V1.050.200 | ecomm/clean | Creates clean tables: Ecomm_Bookings_clean, BookingsConsol_clean, BookingsConsol_fdm_clean, Actuals_Model_Refunds_FDM_clean, rptNewCustomerUpdate_clean, PDS_Renewals_clean (6 tables) |
| 4 | V1.050.300 | ecomm/conformed | Creates conformed tables: Ecomm_Bookings, BookingsConsol, BookingsConsol_fdm, Actuals_Model_Bookings_FDM, Raw_ads_bill_line, fdm_forecast_bill_line, fdm_forecast_bill_line_consol_src, Actuals_Model_Refunds_FDM, rptNewCustomerUpdate, PDS_Renewals, PDS_Renewals_Daily (11 tables) |
| 5 | V1.051.100 | ecomm_budget/raw | Creates raw tables: FinBudget_ImpNonGCR_Prod, POP_Calc_Alloc_IR, FinBudget_ImpCOGS_Prod, FinBudgetView_CalcForecast (4 tables) |
| 6 | V1.051.200 | ecomm_budget/clean | Creates clean tables: FinBudget_ImpNonGCR_Prod_clean, FinBudget_ImpCOGS_Prod_clean, FinBudgetView_CalcForecast_clean (3 tables) |
| 7 | V1.051.300 | ecomm_budget/conformed | Creates conformed tables: Create_BudgetCase, POP_Calc_Alloc_IR, publish_daily_budget, FinBudgetView_CalcForecast (4 tables) |
| 8 | V1.052.200 | ecomm_actuals/clean | Creates clean tables: Sandbox_Model_Bookings_clean (1 table) |
| 9 | V1.052.300 | ecomm_actuals/conformed | Creates conformed tables: Sandbox_Model_Bookings_conformed (1 table) |
| 10 | V1.150.100 | aftermarket/raw | Creates raw tables: Aftermarket_Comprehensive, Aftermarket_Orders, Aftermarket_Refunds (3 tables) |
| 11 | V1.150.200 | aftermarket/clean | Creates clean tables: Aftermarket_Comprehensive_clean, Aftermarket_Orders_clean, Aftermarket_Refunds_clean (3 tables) |
| 12 | V1.150.300 | aftermarket/conformed | Creates conformed tables: Aftermarket_Comprehensive, Aftermarket_ConsTbl, Aftermarket_Orders, Aftermarket_Refunds (4 tables) |
| 13 | V1.200.100 | uds/raw | Creates raw tables: UDSOrder, UDSRefund (2 tables) |
| 14 | V1.200.200 | uds/clean | Creates clean tables: UDSOrder_clean, UDSRefund_clean (2 tables) |
| 15 | V1.200.300 | uds/conformed | Creates conformed tables: UDSOrder_conformed, UDSRefund_conformed (2 tables) |
| 16 | V1.800.100 | orchestration | Creates orchestration framework (tasks, streams, pipes) |
| 17 | V1.900.100 | governance | Creates masking policies |
| 18 | V1.900.101 | governance | Creates DATA_QUALITY_LOG table |
| 19 | R__*.sql | all | Applies all repeatable scripts (67 procedures/views) |
| 20 | A__grants.sql | governance | Applies grants (runs every deployment) |

**Total objects deployed:** 55 versioned table scripts + 67 repeatable procedure/view scripts = 122 scripts

> **Reference:** See `finance_data_platform_file_renaming_map.xlsx` for the complete file-by-file mapping from source to target paths.

### 5.2 Verify Deployment

Check the change history table to confirm all scripts were applied:

```sql
SELECT SCRIPT, VERSION, STATUS, INSTALLED_ON
FROM FINANCE_DB_STAGING.METADATA.SCHEMACHANGE_HISTORY
ORDER BY INSTALLED_ON;
```

---

## Step 6: Run Smoke Tests

```bash
bash scripts/run_smoke_tests.sh --env=staging
```

**Tests validate:**

| Domain | Layer | Objects Validated |
|--------|-------|-------------------|
| ecomm | raw | Ecomm_Bookings, BookingsConsol, Raw_ads_bill_line, fdm_forecast_bill_line tables |
| ecomm | clean | Ecomm_Bookings_clean, BookingsConsol_clean, Refunds_clean, Customer_clean tables |
| ecomm | conformed | Ecomm_Bookings_conformed, BookingsConsol_conformed, Actuals_Model_Bookings_FDM tables |
| ecomm_budget | raw | FinBudget_ImpNonGCR_Prod, POP_Calc_Alloc_IR, FinBudget_ImpCOGS_Prod tables |
| ecomm_budget | conformed | BudgetCase, publish_daily_budget, Forecast tables |
| aftermarket | raw | Aftermarket_Orders, Aftermarket_Comprehensive, Aftermarket_Refunds tables |
| aftermarket | conformed | Aftermarket_ConsTbl_conformed, Aftermarket_Orders_conformed tables |
| uds | raw | UDSOrder, UDSRefund tables |
| uds | conformed | UDSOrder_conformed, UDSRefund_conformed tables |
| orchestration | — | Tasks, streams, stages |
| governance | — | Masking policies, DATA_QUALITY_LOG |

**Expected output:**
```
============================================================
  SMOKE TESTS: staging (FINANCE_DB_STAGING)
============================================================

>> Executing smoke tests...

============================================================
  SMOKE TESTS PASSED
============================================================
```

---

## Step 7: Load Seed Data (Optional)

If the environment needs reference/seed data:

```bash
# Seed data is a repeatable script — it runs automatically during deploy.
# If you need to reload manually:
snow sql -c MY_STAGING_ACCOUNT \
  --database FINANCE_DB_STAGING \
  -f banking/reference/R__seed_data.sql
```

---

## Step 8: Resume Tasks (If Applicable)

Tasks are created in suspended state by default. Resume them to enable scheduled ingestion:

```sql
USE DATABASE FINANCE_DB_STAGING;
ALTER TASK RAW_DEV.TASK_LOAD_CUSTOMER RESUME;
ALTER TASK RAW_DEV.TASK_LOAD_ACCOUNT RESUME;
ALTER TASK RAW_DEV.TASK_LOAD_TRANSACTION RESUME;
```

---

## Rollout Checklist

Use this checklist to track deployment progress:

| # | Step | Command | Status |
|---|------|---------|--------|
| 1 | Add environment to `environments.yml` | Edit file | ☐ |
| 2 | Configure Snowflake CLI connection | Edit `~/.snowflake/connections.toml` | ☐ |
| 3 | Set CI/CD secrets (if automated) | GitHub/GitLab settings | ☐ |
| 4 | Create target database | `CREATE DATABASE ...` | ☐ |
| 5 | Dry-run deployment | `deploy_schemachange.sh --env=X --dry-run` | ☐ |
| 6 | Review dry-run output | Verify script order and variables | ☐ |
| 7 | Deploy | `deploy_schemachange.sh --env=X` | ☐ |
| 8 | Verify change history | Query `METADATA.SCHEMACHANGE_HISTORY` | ☐ |
| 9 | Run smoke tests | `run_smoke_tests.sh --env=X` | ☐ |
| 10 | Load seed data (if needed) | R__seed_data.sql | ☐ |
| 11 | Resume tasks (if needed) | `ALTER TASK ... RESUME` | ☐ |
| 12 | Run integration tests | `tests/integration_test.sql` | ☐ |

---

## Execution Order Reference

Schemachange applies scripts globally in version-sorted order, regardless of folder location:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  DEPLOYMENT EXECUTION ORDER                                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Versioned (V__) — run once, in numeric order:                       │
│                                                                          │
│     V1.000.100  _platform        → create infrastructure (schemas)       │
│                                                                          │
│     V1.050.100  ecomm/raw        → 9 raw tables                         │
│     V1.050.200  ecomm/clean      → 6 clean tables                       │
│     V1.050.300  ecomm/conformed  → 11 conformed tables                  │
│                                                                          │
│     V1.051.100  ecomm_budget/raw       → 4 raw tables                   │
│     V1.051.200  ecomm_budget/clean     → 3 clean tables                 │
│     V1.051.300  ecomm_budget/conformed → 4 conformed tables             │
│                                                                          │
│     V1.052.200  ecomm_actuals/clean     → 1 clean table                 │
│     V1.052.300  ecomm_actuals/conformed → 1 conformed table             │
│                                                                          │
│     V1.150.100  aftermarket/raw        → 3 raw tables                   │
│     V1.150.200  aftermarket/clean      → 3 clean tables                 │
│     V1.150.300  aftermarket/conformed  → 4 conformed tables             │
│                                                                          │
│     V1.200.100  uds/raw        → 2 raw tables                           │
│     V1.200.200  uds/clean      → 2 clean tables                         │
│     V1.200.300  uds/conformed  → 2 conformed tables                     │
│                                                                          │
│     V1.800.100  orchestration  → task framework                          │
│     V1.900.100  governance     → masking policies                        │
│     V1.900.101  governance     → data quality table                      │
│                                                                          │
│  2. Repeatable (R__) — run on content change (67 scripts):              │
│     R__ecomm_procedures.sql                                              │
│     R__budget_procedures.sql                                             │
│     R__actuals_procedures.sql                                            │
│     R__aftermarket_procedures.sql                                        │
│     R__uds_procedures.sql                                                │
│     R__ingestion_tasks.sql                                               │
│     ... (see Excel mapping for full list)                                │
│                                                                          │
│  3. Always (A__) — run every deployment:                                │
│     A__grants.sql                                                        │
│                                                                          │
│  TOTALS: 55 versioned + 67 repeatable + 1 always = 123 scripts          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

> **Full mapping:** See `finance_data_platform_file_renaming_map.xlsx` (Sheet: "Execution Order") for the complete breakdown by domain and layer with script counts.

---

## Troubleshooting

### Error: "Table does not exist"

**Cause:** A script references an object that hasn't been created yet (version ordering issue).

**Fix:** Verify the version numbers follow the strategy: infrastructure (000) → raw (1xx) → clean (2xx) → conformed (3xx) → governance (900). Lower versions must create objects before higher versions reference them.

### Error: "Schema does not exist"

**Cause:** The database exists but schemas haven't been created (V1.000.100 didn't run).

**Fix:**
```bash
# Check what's been applied
snow sql -c MY_STAGING_ACCOUNT --database FINANCE_DB_STAGING -q "
  SELECT SCRIPT, STATUS FROM METADATA.SCHEMACHANGE_HISTORY ORDER BY INSTALLED_ON;
"
```

If METADATA.SCHEMACHANGE_HISTORY doesn't exist, the deploy never started successfully. Re-run from step 4.

### Error: "Object already exists"

**Cause:** A versioned script was modified after it was already applied. Schemachange detects checksum changes and refuses to re-run.

**Fix:** Never modify already-applied V__ scripts. Create a new V__ script with the next version number for the change.

### Error: "Insufficient privileges"

**Cause:** The deployment role doesn't have permission to create objects.

**Fix:**
```sql
-- Ensure SYSADMIN owns the database
GRANT OWNERSHIP ON DATABASE FINANCE_DB_STAGING TO ROLE SYSADMIN;
GRANT ALL ON DATABASE FINANCE_DB_STAGING TO ROLE SYSADMIN;
```

### Starting Fresh (Nuclear Option)

If the environment is corrupted and you need a clean slate:

```sql
-- Drop and recreate (CAUTION: destroys all data)
DROP DATABASE IF EXISTS FINANCE_DB_STAGING;
CREATE DATABASE FINANCE_DB_STAGING;
```

Then re-run from Step 4. Schemachange will apply all migrations from scratch since the history table no longer exists.

---

## CI/CD Integration

### GitHub Actions (Automated)

Deployments are triggered automatically by the CI/CD pipeline:

| Workflow | Trigger | Target Environment |
|----------|---------|-------------------|
| `deploy-dev.yml` | Push to `develop` | dev |
| `deploy-qa.yml` | Push to `release/*` | qa |
| `deploy-preprod.yml` | Push to `main` | preprod |
| `deploy-prod.yml` | Tag `v*` or manual dispatch | prod |

### Manual Deployment

For ad-hoc or first-time deployments:

```bash
# Set credentials
export SNOWFLAKE_ACCOUNT="abc12345.us-east-1"
export SNOWFLAKE_USER="DEPLOY_USER"
export SNOWFLAKE_PRIVATE_KEY_PATH="~/.snowflake/ci_key.p8"

# Deploy
bash scripts/deploy_schemachange.sh --env=staging
```

---

## Post-Deployment Validation Queries

Run these after deployment to confirm the environment is healthy:

```sql
USE DATABASE FINANCE_DB_STAGING;

-- 1. Object counts by schema
SELECT TABLE_SCHEMA, TABLE_TYPE, COUNT(*) AS object_count
FROM INFORMATION_SCHEMA.TABLES
GROUP BY TABLE_SCHEMA, TABLE_TYPE
ORDER BY TABLE_SCHEMA, TABLE_TYPE;

-- 2. Procedure counts by schema
SELECT PROCEDURE_SCHEMA, COUNT(*) AS proc_count
FROM INFORMATION_SCHEMA.PROCEDURES
GROUP BY PROCEDURE_SCHEMA
ORDER BY PROCEDURE_SCHEMA;

-- 3. Task status
SHOW TASKS IN DATABASE FINANCE_DB_STAGING;

-- 4. Stage existence
SHOW STAGES IN SCHEMA RAW_DEV;

-- 5. Migration history
SELECT VERSION, SCRIPT, STATUS, INSTALLED_ON
FROM METADATA.SCHEMACHANGE_HISTORY
ORDER BY INSTALLED_ON;
```

---

## Environment Comparison

After deploying to a new environment, compare it against an existing one:

```sql
-- Compare object counts between environments
-- Run in each environment and compare results:
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'METADATA')
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

---

## Rollback Strategy

Since schemachange does not support native rollback, use one of these approaches:

1. **Forward-fix:** Create a new versioned migration that reverses the change
2. **Full redeploy:** Drop database, recreate, and run schemachange from scratch
3. **Point-in-time:** Use Snowflake Time Travel (within retention period)

```sql
-- Time Travel example (within 24 hours on Standard Edition)
CREATE TABLE RAW.T_CUSTOMER_ROLLBACK
AS SELECT * FROM RAW.T_CUSTOMER AT(OFFSET => -3600);
```

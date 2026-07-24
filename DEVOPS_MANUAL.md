# DevOps Operations Manual

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
├─────────────────────────────────────────────────────────────────┤
│  feature/* ──PR──► develop ──PR──► release/* ──PR──► main ──tag──► v*  │
│       │                                │              │              │  │
│       ▼                                ▼              ▼              ▼  │
│   CI Lint                         Deploy QA     Deploy PreProd  Deploy Prod │
└─────────────────────────────────────────────────────────────────┘
                                         │              │              │
                                         ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Snowflake (KXAXARZ-GW22129)                  │
├─────────────────────────────────────────────────────────────────┤
│  SSOM_COCO_DB_QA  │  SSOM_COCO_DB_PREPROD  │  SSOM_COCO_DB_PROD │
│                   │                         │                     │
│  Warehouse: COMPUTE_WH (shared, XS)                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Project Structure

The SQL codebase uses **schemachange** for migration management, organized under the `banking/` root folder:

```
banking/
├── _platform/
│   └── V1.0.0__setup_schemas.sql         # Schema creation (BRONZE, SILVER, GOLD, etc.)
├── bronze/retail/
│   └── V1.1.0__bronze_tables.sql         # Bronze tables, stages, streams, tasks
├── silver/retail/
│   ├── V1.2.0__silver_tables.sql         # Silver dimension tables
│   └── R__silver_procedures.sql          # Repeatable: Silver ETL procedures (SCD-2, SCD-1)
├── gold/retail/
│   ├── V1.3.0__gold_tables.sql           # Gold fact tables
│   ├── R__gold_procedures.sql            # Repeatable: Gold ETL procedures
│   └── R__gold_views.sql                 # Repeatable: Gold views (re-run every deploy)
├── orchestration/
│   ├── R__orchestration.sql              # Repeatable: Daily_ETL_Run() orchestrator
│   └── R__ingestion_tasks.sql            # Repeatable: Ingestion task definitions
├── reference/
│   ├── R__seed_data.sql                  # Repeatable: Seed/reference data
│   └── R__iceberg_objects.sql            # Repeatable: Iceberg/Parquet ingestion objects
└── governance/
    ├── V1.4.0__masking_policies.sql      # Masking policy table/setup
    ├── V1.5.0__data_quality.sql          # DATA_QUALITY_LOG table creation
    ├── R__masking_policies.sql           # Repeatable: Masking policy definitions & assignments
    ├── R__data_quality_procedures.sql    # Repeatable: Data quality procedures
    └── A__grants.sql                     # Always-run: grants (re-applied every deploy)
```

### 2.1 Schemachange Naming Conventions

| Prefix | Meaning | Behavior |
|--------|---------|----------|
| `V<ver>__<name>.sql` | Versioned migration | Runs once, tracked in change history |
| `R__<name>.sql` | Repeatable migration | Re-runs if file content changes |
| `A__<name>.sql` | Always-run migration | Runs on every deployment |

### 2.2 Schemachange Configuration

File: `schemachange-config.yml`

```yaml
root-folder: banking
modules-folder: null
vars:
  database: "SSOM_COCO_DB"
  warehouse: "COMPUTE_WH"
  role: "SYSADMIN"
  environment: "dev"

create-change-history-table: true
change-history-table: "{{database}}.METADATA.SCHEMACHANGE_HISTORY"
autocommit: true
dry-run: false
```

### 2.3 Change History

Schemachange tracks all applied migrations in `<database>.METADATA.SCHEMACHANGE_HISTORY`. Query it to see deployment state:

```sql
SELECT * FROM SSOM_COCO_DB.METADATA.SCHEMACHANGE_HISTORY ORDER BY INSTALLED_ON DESC;
```

---

## 3. CI/CD Pipeline

### 3.1 Workflow Files

| File | Purpose | Trigger |
|------|---------|---------|
| `.github/workflows/ci.yml` | Lint + validate | PR to `develop`, `release/*`, `main` |
| `.github/workflows/deploy-qa.yml` | Deploy + test QA | Push to `release/*` |
| `.github/workflows/deploy-preprod.yml` | Deploy + test PreProd | Push to `main` |
| `.github/workflows/deploy-prod.yml` | Deploy + validate Prod | Tag `v*` or manual dispatch |

### 3.2 Pipeline Stages

```
┌──────────────┐    ┌───────────────────┐    ┌─────────────────┐    ┌──────────────┐
│ SQL Lint     │───►│ Deploy via        │───►│ Smoke Tests     │───►│ Integration  │
│ (sqlfluff)   │    │ schemachange      │    │ (object exists) │    │ Tests        │
└──────────────┘    └───────────────────┘    └─────────────────┘    └──────────────┘
```

### 3.3 CI Lint Job Details

The CI workflow:
1. Lints `banking/` with sqlfluff
2. Validates versioned migration files (`V*.sql`) exist and are non-empty
3. Checks `environments.yml` has all required environments
4. Runs shellcheck on deployment scripts

Path triggers: `banking/**`, `scripts/**`, `tests/**`, `environments.yml`, `schemachange-config.yml`, `.sqlfluff`

### 3.4 Concurrency Controls

All deploy workflows use concurrency groups to prevent parallel deployments:

```yaml
concurrency:
  group: deploy-<env>
  cancel-in-progress: false   # Never cancel an in-flight deploy
```

---

## 4. Secrets Management

### 4.1 Required GitHub Secrets

#### Non-Production (QA, PreProd)

| Secret | Value | Used By |
|--------|-------|---------|
| `SNOWFLAKE_ACCOUNT` | `KXAXARZ-GW22129` | deploy-qa, deploy-preprod |
| `SNOWFLAKE_USER` | `SOMSUJAY` | deploy-qa, deploy-preprod |
| `SNOWFLAKE_PRIVATE_KEY` | RSA private key (PEM) | deploy-qa, deploy-preprod |

#### Production

| Secret | Value | Used By |
|--------|-------|---------|
| `SNOWFLAKE_PROD_ACCOUNT` | `KXAXARZ-GW22129` | deploy-prod |
| `SNOWFLAKE_PROD_USER` | `SOMSUJAY` | deploy-prod |
| `SNOWFLAKE_PROD_PRIVATE_KEY` | RSA private key (PEM) | deploy-prod |

### 4.2 Key Rotation Procedure

1. Generate new key pair:
   ```bash
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out new_key.p8 -nocrypt
   openssl rsa -in new_key.p8 -pubout -out new_key.pub
   ```

2. Register new key in Snowflake (use RSA_PUBLIC_KEY_2 for zero-downtime rotation):
   ```sql
   ALTER USER SOMSUJAY SET RSA_PUBLIC_KEY_2='<new-public-key>';
   ```

3. Update GitHub secret `SNOWFLAKE_PRIVATE_KEY` with new key contents.

4. Verify CI passes with new key.

5. Remove old key:
   ```sql
   ALTER USER SOMSUJAY SET RSA_PUBLIC_KEY='<new-public-key>';
   ALTER USER SOMSUJAY UNSET RSA_PUBLIC_KEY_2;
   ```

### 4.3 Key Rotation Schedule

- Rotate every 90 days
- Rotate immediately if any key exposure is suspected

---

## 5. Deployment Procedures

### 5.1 Primary Deployment: Schemachange

The primary deployment method uses `scripts/deploy_schemachange.sh`, which invokes schemachange against the `banking/` root folder:

```bash
# Deploy to dev (local)
export SNOWFLAKE_ACCOUNT=KXAXARZ-GW22129
export SNOWFLAKE_USER=SOMSUJAY
bash scripts/deploy_schemachange.sh --env=dev

# Deploy to QA
bash scripts/deploy_schemachange.sh --env=qa

# Dry-run (no changes made)
bash scripts/deploy_schemachange.sh --env=prod --dry-run
```

The script:
1. Reads database/warehouse/connection from `environments.yml`
2. Authenticates via RSA private key (`SNOWFLAKE_PRIVATE_KEY_PATH` or `~/.snowflake/ci_key.p8`)
3. Runs `schemachange deploy` against the `banking/` folder
4. Passes `database`, `warehouse`, `role`, and `environment` as template variables
5. Tracks history in `<database>.METADATA.SCHEMACHANGE_HISTORY`

### 5.2 Legacy Deployment: deploy.sh

`scripts/deploy.sh` is the legacy deployer that executes numbered SQL scripts from a `Snowflake_Scripts/` directory. It is still referenced by the preprod workflow but will be migrated to schemachange.

### 5.3 Standard Release (QA → PreProd → Prod)

```bash
# 1. Create release branch from develop
git checkout develop && git pull
git checkout -b release/v1.3.0

# 2. Push triggers deploy-qa.yml automatically (schemachange)
git push -u origin release/v1.3.0

# 3. After QA passes, merge to main (triggers deploy-preprod.yml)
gh pr create --base main --title "Release v1.3.0"
gh pr merge <pr-number> --merge

# 4. After PreProd passes, tag for production (triggers deploy-prod.yml)
git checkout main && git pull
git tag v1.3.0
git push origin v1.3.0
```

### 5.4 Hotfix Release

```bash
# 1. Branch from main
git checkout main && git pull
git checkout -b hotfix/fix-critical-bug

# 2. Apply fix, push, create PR to main
git push -u origin hotfix/fix-critical-bug
gh pr create --base main --title "Hotfix: fix critical bug"

# 3. Merge to main (deploys to PreProd)
gh pr merge <pr-number> --merge

# 4. After PreProd validates, tag for prod
git checkout main && git pull
git tag v1.2.1
git push origin v1.2.1

# 5. Back-merge to develop
git checkout develop && git merge main && git push
```

### 5.5 Manual Deployment (Production)

Via GitHub Actions UI or CLI:
```bash
gh workflow run deploy-prod.yml -f action=deploy
```

### 5.6 Adding a New Migration

```bash
# 1. Create a new versioned migration file
#    Use the next version number and a descriptive name
touch banking/<layer>/<domain>/V1.11.0__add_new_table.sql

# 2. Write your SQL (use Jinja vars for database targeting)
#    Available vars: {{database}}, {{warehouse}}, {{role}}, {{environment}}

# 3. Test locally with dry-run
bash scripts/deploy_schemachange.sh --env=dev --dry-run

# 4. Deploy to dev
bash scripts/deploy_schemachange.sh --env=dev
```

---

## 6. Rollback Procedures

### 6.1 Automated Rollback (Production)

```bash
# Via GitHub CLI
gh workflow run deploy-prod.yml \
  -f action=rollback \
  -f rollback_version=v1.2.0

# Via GitHub Actions UI
# Navigate to Actions > Deploy to PROD > Run workflow
# Select action=rollback, enter version tag
```

### 6.2 Manual Rollback (Any Environment)

```bash
# Rollback PreProd to a specific version
bash scripts/rollback.sh --env=preprod --version=v1.2.0

# Rollback Prod to a specific commit SHA
bash scripts/rollback.sh --env=prod --version=abc123f
```

### 6.3 Rollback Process

The `rollback.sh` script:
1. Validates the target git ref exists
2. Extracts `Snowflake_Scripts/` from that version (legacy format)
3. Re-deploys all SQL scripts from the old version
4. Runs smoke tests to confirm rollback success

**Note:** The rollback script currently operates on the legacy `Snowflake_Scripts/` directory. For schemachange-based rollbacks, create a new migration that reverses the changes.

### 6.4 Schemachange Rollback Strategy

Since schemachange tracks applied versions, rolling back requires one of:
- **Fix-forward**: Create a new `V<next>__revert_<change>.sql` migration
- **Manual revert**: Drop/alter objects directly, then update the change history table
- **Full redeploy**: Drop the database, recreate, and run schemachange from scratch

### 6.5 Rollback Decision Matrix

| Severity | Detection | Action |
|----------|-----------|--------|
| Data corruption | Integration tests fail | Immediate rollback + incident |
| Procedure failure | Smoke tests fail | Rollback, investigate |
| Performance degradation | Monitoring alert | Assess, rollback if SLA breach |
| Cosmetic / non-blocking | Manual observation | Fix-forward in next release |

---

## 7. Environment Management

### 7.1 Configuration File

`environments.yml` is the single source of truth:

```yaml
dev:
  database: SSOM_COCO_DB
  warehouse: COMPUTE_WH
  connection: MY_TRIAL_ACCOUNT

qa:
  database: SSOM_COCO_DB_QA
  warehouse: COMPUTE_WH
  connection: MY_TRIAL_ACCOUNT

preprod:
  database: SSOM_COCO_DB_PREPROD
  warehouse: COMPUTE_WH
  connection: MY_TRIAL_ACCOUNT

prod:
  database: SSOM_COCO_DB_PROD
  warehouse: COMPUTE_WH
  connection: MY_TRIAL_ACCOUNT
```

### 7.2 Environment Variable Overrides

Scripts accept runtime overrides:

| Variable | Default | Description |
|----------|---------|-------------|
| `SNOWFLAKE_ACCOUNT` | (required in CI) | Snowflake account identifier |
| `SNOWFLAKE_USER` | (required in CI) | Snowflake user name |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | `~/.snowflake/ci_key.p8` | Path to RSA private key |
| `SNOWFLAKE_ROLE` | `SYSADMIN` | Role for schemachange |
| `SNOWFLAKE_WAREHOUSE` | From environments.yml | Compute warehouse override |

### 7.3 Provisioning a New Environment

```sql
-- 1. Create database
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_<ENV>;
GRANT OWNERSHIP ON DATABASE SSOM_COCO_DB_<ENV> TO ROLE ACCOUNTADMIN;

-- 2. Grant warehouse usage
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ACCOUNTADMIN;
```

```bash
# 3. Deploy with schemachange
bash scripts/deploy_schemachange.sh --env=<env>

# 4. Verify
bash scripts/run_smoke_tests.sh --env=<env>
```

---

## 8. Monitoring and Alerting

### 8.1 Deployment Health Checks

After every deployment, the pipeline validates:

| Check | Test File | Validates |
|-------|-----------|-----------|
| Schema existence | `tests/smoke_test.sql` | BRONZE, SILVER, GOLD, GOVERNANCE schemas |
| Object existence | `tests/smoke_test.sql` | All tables, views, stages, tasks |
| Object counts | `tests/integration_test.sql` | Minimum expected objects per schema |
| Procedure availability | `tests/integration_test.sql` | All ETL procedures callable |
| Masking policies | `tests/integration_test.sql` | Governance policies deployed |
| Data quality table | `tests/integration_test.sql` | DATA_QUALITY_LOG exists |

### 8.2 GitHub Actions Notifications

- **Success**: `::notice` annotation on the workflow run
- **Failure**: `::error` annotation with rollback instructions

### 8.3 Manual Health Check

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "
  SELECT TABLE_SCHEMA, COUNT(*) AS object_count
  FROM SSOM_COCO_DB.INFORMATION_SCHEMA.TABLES
  GROUP BY TABLE_SCHEMA
  ORDER BY TABLE_SCHEMA;
"
```

### 8.4 Checking Migration State

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "
  SELECT VERSION, SCRIPT, INSTALLED_ON, STATUS
  FROM SSOM_COCO_DB.METADATA.SCHEMACHANGE_HISTORY
  ORDER BY INSTALLED_ON DESC
  LIMIT 20;
"
```

---

## 9. Incident Response

### 9.1 Severity Levels

| Level | Definition | Response Time | Examples |
|-------|------------|---------------|----------|
| SEV1 | Production data loss or corruption | Immediate | ETL writing bad data, tables dropped |
| SEV2 | Production pipeline broken | 30 minutes | Procedures failing, tasks stuck |
| SEV3 | Non-prod broken or degraded performance | 4 hours | QA deploy failure, slow queries |
| SEV4 | Cosmetic or documentation issue | Next sprint | Lint warnings, README outdated |

### 9.2 SEV1/SEV2 Response Playbook

```
1. ASSESS
   - Check GitHub Actions run logs
   - Check Snowflake query history: SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
   - Check migration state: SELECT * FROM <DB>.METADATA.SCHEMACHANGE_HISTORY ORDER BY INSTALLED_ON DESC;

2. CONTAIN
   - Suspend tasks if ETL is producing bad data:
     ALTER TASK BRONZE.TASK_LOAD_CUSTOMER SUSPEND;
     ALTER TASK BRONZE.TASK_LOAD_ACCOUNT SUSPEND;
     ALTER TASK BRONZE.TASK_LOAD_TRANSACTION SUSPEND;

3. ROLLBACK (if needed)
   gh workflow run deploy-prod.yml -f action=rollback -f rollback_version=<last-good-tag>

4. VALIDATE
   bash scripts/run_smoke_tests.sh --env=prod

5. COMMUNICATE
   - Post incident summary
   - Create follow-up ticket for root cause analysis
```

### 9.3 Common Failure Scenarios

| Scenario | Symptoms | Resolution |
|----------|----------|------------|
| Warehouse suspended | `Warehouse COMPUTE_WH cannot be resumed` | `ALTER WAREHOUSE COMPUTE_WH RESUME;` |
| Key expired | `JWT token is invalid` | Rotate key (Section 4.2) |
| Account locked | `Authentication failed` | Unlock via Snowflake UI, check login attempts |
| Quota exceeded | `Exceeded resource limit` | Check `SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY` |
| Task stuck | Task shows EXECUTING indefinitely | `ALTER TASK ... SUSPEND;` then `RESUME;` |
| Migration already applied | `Version already exists in change history` | Check if script was already run; bump version if content changed |

---

## 10. Maintenance Tasks

### 10.1 Regular Maintenance Schedule

| Task | Frequency | Procedure |
|------|-----------|-----------|
| Key rotation | Every 90 days | Section 4.2 |
| Review query history | Weekly | Check long-running queries |
| Warehouse sizing | Monthly | Analyze `WAREHOUSE_LOAD_HISTORY` |
| Stale data check | Daily (automated) | `Run_Data_Quality_Checks()` |
| GitHub Actions cleanup | Monthly | Delete old workflow runs |

### 10.2 Cleaning Up Failed Deployments

If a deployment partially completed:

```bash
# Option A: Re-run schemachange (idempotent for already-applied versions)
bash scripts/deploy_schemachange.sh --env=<env>

# Option B: Nuclear option - drop everything and redeploy from scratch
bash scripts/drop_objects.sh --confirm
bash scripts/deploy_schemachange.sh --env=<env>
```

### 10.3 Database Cloning (For Testing)

```sql
-- Clone prod to a test database
CREATE DATABASE SSOM_COCO_DB_TEST CLONE SSOM_COCO_DB_PROD;
```

---

## 11. Access Control

### 11.1 Current Setup

| Role | Access | Usage |
|------|--------|-------|
| `ACCOUNTADMIN` | Full access | Deployments, DDL, grants |
| `SYSADMIN` | Database management | Object creation (schemachange default) |
| `PUBLIC` | Read-only on views | Dashboards, reporting |

### 11.2 Principle of Least Privilege (Recommended)

For production hardening, create dedicated roles:

```sql
-- Deployment role (used by CI/CD)
CREATE ROLE IF NOT EXISTS DEPLOY_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEPLOY_ROLE;
GRANT ALL ON DATABASE SSOM_COCO_DB_PROD TO ROLE DEPLOY_ROLE;
GRANT ROLE DEPLOY_ROLE TO USER SOMSUJAY;

-- Read-only role (for dashboards)
CREATE ROLE IF NOT EXISTS READER_ROLE;
GRANT USAGE ON DATABASE SSOM_COCO_DB_PROD TO ROLE READER_ROLE;
GRANT USAGE ON SCHEMA SSOM_COCO_DB_PROD.GOLD TO ROLE READER_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA SSOM_COCO_DB_PROD.GOLD TO ROLE READER_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA SSOM_COCO_DB_PROD.GOLD TO ROLE READER_ROLE;
```

---

## 12. Linting and Code Quality

### 12.1 SQLFluff Configuration

File: `.sqlfluff`

```ini
[sqlfluff]
dialect = snowflake
templater = raw
max_line_length = 120
exclude_rules = LT05, RF04, LT02

[sqlfluff:indentation]
indent_unit = space
tab_space_size = 4

[sqlfluff:rules:capitalisation.keywords]
capitalisation_policy = upper

[sqlfluff:rules:capitalisation.functions]
extended_capitalisation_policy = upper

[sqlfluff:rules:capitalisation.types]
extended_capitalisation_policy = upper

[sqlfluff:paths]
ignore = Teradata_Scripts
```

### 12.2 Rule Exclusions

| Rule | Reason for Exclusion |
|------|---------------------|
| `LT05` | Allow lines up to 120 chars (SQL DDL can be verbose) |
| `RF04` | Column names like STATUS, DATE, TYPE are valid Snowflake identifiers |
| `LT02` | DDL property indentation is intentional for readability |

### 12.3 Running Lint Locally

```bash
# Check for issues
sqlfluff lint banking/ --dialect snowflake --config .sqlfluff

# Auto-fix issues
sqlfluff fix banking/ --dialect snowflake --config .sqlfluff --force
```

### 12.4 Pre-Commit Hook (Optional)

```bash
# .git/hooks/pre-commit
#!/bin/bash
sqlfluff lint banking/ --dialect snowflake --config .sqlfluff
```

---

## 13. Disaster Recovery

### 13.1 Snowflake Time Travel

All tables have default 1-day retention. To recover dropped/modified data:

```sql
-- Query data as of 1 hour ago
SELECT * FROM BRONZE.T_CUSTOMER AT(OFFSET => -3600);

-- Restore a dropped table
UNDROP TABLE SILVER.DIMCUSTOMER;

-- Clone table from a point in time
CREATE TABLE SILVER.DIMCUSTOMER_BACKUP CLONE SILVER.DIMCUSTOMER
  AT(TIMESTAMP => '2026-07-15 10:00:00'::TIMESTAMP);
```

### 13.2 Full Environment Recovery

```bash
# 1. Recreate database
snow sql -c MY_TRIAL_ACCOUNT -q "CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_PROD;"

# 2. Redeploy all migrations from scratch
git checkout $(git describe --tags --abbrev=0)
bash scripts/deploy_schemachange.sh --env=prod

# 3. Reload data (if needed)
bash scripts/run_historical.sh
bash scripts/run_incremental.sh
```

---

## 14. Contacts and Escalation

| Role | Responsibility |
|------|----------------|
| DevOps Engineer | Pipeline failures, secret rotation, infra |
| Data Engineer | ETL logic, procedure bugs, data quality |
| DBA | Warehouse sizing, access control, performance |
| Product Owner | Release approval, rollback decisions |

---

## 15. Detailed Configuration Steps

### 15.1 Snowflake Account Setup

#### Step 1: Verify Account Access

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE()"
```

#### Step 2: Create Warehouse (if not exists)

```sql
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Shared compute for ETL pipeline';
```

#### Step 3: Create Databases for Each Environment

```sql
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB;          -- dev
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_QA;       -- qa
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_PREPROD;  -- preprod
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_PROD;     -- prod
```

#### Step 4: Grant Permissions

```sql
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE SYSADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_QA TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_PREPROD TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_PROD TO ROLE ACCOUNTADMIN;
```

---

### 15.2 Local Development Environment Setup

#### Step 1: Install Prerequisites

```bash
# Snowflake CLI
pip install snowflake-cli-labs

# SQL linting
pip install sqlfluff

# Schemachange
pip install schemachange

# Verify installations
snow --version
sqlfluff version
schemachange --version
```

#### Step 2: Generate RSA Key Pair

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/trial_key.p8 -nocrypt
chmod 600 ~/.snowflake/trial_key.p8
openssl rsa -in ~/.snowflake/trial_key.p8 -pubout -out ~/.snowflake/trial_key.pub
```

#### Step 3: Register Public Key in Snowflake

```bash
grep -v "^---" ~/.snowflake/trial_key.pub | tr -d '\n'
```

```sql
ALTER USER SOMSUJAY SET RSA_PUBLIC_KEY='<paste-key-body-here>';
```

#### Step 4: Configure connections.toml

Create/edit `~/.snowflake/connections.toml`:

```toml
[MY_TRIAL_ACCOUNT]
account = "KXAXARZ-GW22129"
user = "SOMSUJAY"
authenticator = "SNOWFLAKE_JWT"
private_key_path = "/Users/<your-username>/.snowflake/trial_key.p8"
warehouse = "COMPUTE_WH"
database = "SSOM_COCO_DB"
```

```bash
chmod 600 ~/.snowflake/connections.toml
```

#### Step 5: Verify Connection

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT 'Connection OK' AS status, CURRENT_WAREHOUSE() AS wh"
```

---

### 15.3 GitHub Repository Configuration

#### Step 1: Create GitHub Environments

Navigate to **Settings > Environments** and create:

| Environment | Protection Rules |
|-------------|-----------------|
| `qa` | None (auto-deploy) |
| `preprod` | None (auto-deploy) |
| `production` | Required reviewers, wait timer (optional) |

#### Step 2: Configure Repository Secrets

```
SNOWFLAKE_ACCOUNT        = KXAXARZ-GW22129
SNOWFLAKE_USER           = SOMSUJAY
SNOWFLAKE_PRIVATE_KEY    = <contents of ~/.snowflake/trial_key.p8>

SNOWFLAKE_PROD_ACCOUNT   = KXAXARZ-GW22129
SNOWFLAKE_PROD_USER      = SOMSUJAY
SNOWFLAKE_PROD_PRIVATE_KEY = <contents of ~/.snowflake/trial_key.p8>
```

#### Step 3: Configure Branch Protection Rules

| Branch Pattern | Rules |
|----------------|-------|
| `main` | Require PR, require status checks (CI Lint), no force push |
| `develop` | Require PR, require status checks (CI Lint) |
| `release/*` | Require PR from develop only |

---

### 15.4 CI/CD Connection Configuration (How It Works)

In GitHub Actions, there is no `~/.snowflake/connections.toml`. The deploy workflows create credentials at runtime:

```
SNOWFLAKE_ACCOUNT + SNOWFLAKE_USER + SNOWFLAKE_PRIVATE_KEY
                          │
                          ▼
         Write private key to ~/.snowflake/ci_key.p8
                          │
                          ▼
         scripts/deploy_schemachange.sh
                          │
                          ▼
         schemachange deploy --root-folder banking/
           --snowflake-account <ACCOUNT>
           --snowflake-user <USER>
           --snowflake-private-key-path ~/.snowflake/ci_key.p8
           --snowflake-database <DB from environments.yml>
           --change-history-table <DB>.METADATA.SCHEMACHANGE_HISTORY
```

---

### 15.5 Streamlit Dashboard Configuration

#### Step 1: Create Streamlit secrets file

```bash
mkdir -p streamlit_app/.streamlit
cat > streamlit_app/.streamlit/secrets.toml << 'EOF'
[snowflake]
account = "KXAXARZ-GW22129"
user = "SOMSUJAY"
authenticator = "externalbrowser"
warehouse = "COMPUTE_WH"
database = "SSOM_COCO_DB"
EOF
chmod 600 streamlit_app/.streamlit/secrets.toml
```

#### Step 2: Start Dashboard

```bash
bash scripts/streamlit_start.sh
# Dashboard runs at http://localhost:8501
```

#### Step 3: Stop Dashboard

```bash
bash scripts/streamlit_stop.sh
```

---

### 15.6 End-to-End Verification Checklist

```bash
# 1. Verify Snowflake connection
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT 1 AS connected"

# 2. Verify warehouse exists
snow sql -c MY_TRIAL_ACCOUNT -q "SHOW WAREHOUSES LIKE 'COMPUTE_WH'"

# 3. Deploy to dev with schemachange
bash scripts/deploy_schemachange.sh --env=dev

# 4. Run smoke tests
bash scripts/run_smoke_tests.sh --env=dev

# 5. Load historical data
bash scripts/run_historical.sh

# 6. Run incremental data
bash scripts/run_incremental.sh

# 7. Verify ETL results
snow sql -c MY_TRIAL_ACCOUNT -q "
  SELECT 'T_Customer' AS tbl, COUNT(*) AS rows FROM SSOM_COCO_DB.BRONZE.T_CUSTOMER
  UNION ALL
  SELECT 'DimCustomer', COUNT(*) FROM SSOM_COCO_DB.SILVER.DIMCUSTOMER
  UNION ALL
  SELECT 'FactDailyTransaction', COUNT(*) FROM SSOM_COCO_DB.GOLD.FACTDAILYTRANSACTION;
"

# 8. Run lint
sqlfluff lint banking/ --dialect snowflake --config .sqlfluff

# 9. Verify GitHub secrets (requires gh CLI authenticated)
gh secret list

# 10. Trigger a CI run
git checkout -b test/verify-pipeline
git commit --allow-empty -m "test: verify CI pipeline"
git push -u origin test/verify-pipeline
gh pr create --base develop --title "Test: verify CI pipeline" --body "Testing CI"
```

---

### 15.7 Configuration Reference Summary

| Component | File/Location | Purpose |
|-----------|---------------|---------|
| Snowflake connection | `~/.snowflake/connections.toml` | Local CLI authentication |
| RSA private key | `~/.snowflake/trial_key.p8` | Key-pair auth credential |
| RSA public key | Registered on Snowflake user | Validates JWT tokens |
| Environment config | `environments.yml` | Database/warehouse/connection per env |
| Schemachange config | `schemachange-config.yml` | Migration tool settings |
| GitHub secrets | Repository Settings | CI/CD authentication |
| Lint config | `.sqlfluff` | SQL formatting rules |
| Migration scripts | `banking/` | Versioned SQL migrations |
| Streamlit secrets | `streamlit_app/.streamlit/secrets.toml` | Dashboard auth |
| CI workflows | `.github/workflows/*.yml` | Pipeline definitions |
| Deploy script | `scripts/deploy_schemachange.sh` | Schemachange deployment orchestrator |
| Legacy deploy | `scripts/deploy.sh` | Legacy numbered-script deployer |
| Rollback script | `scripts/rollback.sh` | Reverts to prior version |
| Smoke tests | `tests/smoke_test.sql` | Post-deploy object checks |
| Integration tests | `tests/integration_test.sql` | Deep validation checks |

---

## 16. Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/deploy_schemachange.sh` | Primary deployment via schemachange | `--env=<env> [--dry-run]` |
| `scripts/deploy.sh` | Legacy deployment (numbered scripts) | `--env=<env> [--dry-run]` |
| `scripts/rollback.sh` | Rollback to a git version | `--env=<env> --version=<tag>` |
| `scripts/run_smoke_tests.sh` | Post-deploy smoke tests | `--env=<env>` |
| `scripts/run_historical.sh` | Load historical data | — |
| `scripts/run_incremental.sh` | Load incremental data | — |
| `scripts/run_etl_end_to_end.sh` | Full ETL pipeline run | — |
| `scripts/create_objects.sh` | Create all Snowflake objects | — |
| `scripts/drop_objects.sh` | Drop all Snowflake objects | `--confirm` |
| `scripts/bootstrap_change_history.sql` | Initialize schemachange history table | — |
| `scripts/streamlit_start.sh` | Start Streamlit dashboard | — |
| `scripts/streamlit_stop.sh` | Stop Streamlit dashboard | — |

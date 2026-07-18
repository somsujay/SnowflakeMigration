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

## 2. CI/CD Pipeline

### 2.1 Workflow Files

| File | Purpose | Trigger |
|------|---------|---------|
| `.github/workflows/ci.yml` | Lint + validate | PR to `develop`, `release/*`, `main` |
| `.github/workflows/deploy-qa.yml` | Deploy + test QA | Push to `release/*` |
| `.github/workflows/deploy-preprod.yml` | Deploy + test PreProd | Push to `main` |
| `.github/workflows/deploy-prod.yml` | Deploy + validate Prod | Tag `v*` or manual dispatch |

### 2.2 Pipeline Stages

```
┌──────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│ SQL Lint │───►│ Deploy SQL   │───►│ Smoke Tests     │───►│ Integration  │
│ (CI)     │    │ (11 scripts) │    │ (object exists) │    │ Tests        │
└──────────┘    └──────────────┘    └─────────────────┘    └──────────────┘
```

### 2.3 Concurrency Controls

All deploy workflows use concurrency groups to prevent parallel deployments:

```yaml
concurrency:
  group: deploy-<env>
  cancel-in-progress: false   # Never cancel an in-flight deploy
```

---

## 3. Secrets Management

### 3.1 Required GitHub Secrets

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

### 3.2 Key Rotation Procedure

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

### 3.3 Key Rotation Schedule

- Rotate every 90 days
- Rotate immediately if any key exposure is suspected

---

## 4. Deployment Procedures

### 4.1 Standard Release (QA → PreProd → Prod)

```bash
# 1. Create release branch from develop
git checkout develop && git pull
git checkout -b release/v1.3.0

# 2. Push triggers deploy-qa.yml automatically
git push -u origin release/v1.3.0

# 3. After QA passes, merge to main (triggers deploy-preprod.yml)
gh pr create --base main --title "Release v1.3.0"
gh pr merge <pr-number> --merge

# 4. After PreProd passes, tag for production (triggers deploy-prod.yml)
git checkout main && git pull
git tag v1.3.0
git push origin v1.3.0
```

### 4.2 Hotfix Release

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

### 4.3 Manual Deployment (Production)

Via GitHub Actions UI or CLI:
```bash
gh workflow run deploy-prod.yml -f action=deploy
```

### 4.4 Dry-Run Deployment

Test what would be deployed without executing:
```bash
bash scripts/deploy.sh --env=prod --dry-run
```

---

## 5. Rollback Procedures

### 5.1 Automated Rollback (Production)

```bash
# Via GitHub CLI
gh workflow run deploy-prod.yml \
  -f action=rollback \
  -f rollback_version=v1.2.0

# Via GitHub Actions UI
# Navigate to Actions > Deploy to PROD > Run workflow
# Select action=rollback, enter version tag
```

### 5.2 Manual Rollback (Any Environment)

```bash
# Rollback PreProd to a specific version
bash scripts/rollback.sh --env=preprod --version=v1.2.0

# Rollback Prod to a specific commit SHA
bash scripts/rollback.sh --env=prod --version=abc123f
```

### 5.3 Rollback Process

1. Validates the target git ref exists
2. Extracts `Snowflake_Scripts/` from that version
3. Re-deploys all 11 SQL scripts from the old version
4. Runs smoke tests to confirm rollback success

### 5.4 Rollback Decision Matrix

| Severity | Detection | Action |
|----------|-----------|--------|
| Data corruption | Integration tests fail | Immediate rollback + incident |
| Procedure failure | Smoke tests fail | Rollback, investigate |
| Performance degradation | Monitoring alert | Assess, rollback if SLA breach |
| Cosmetic / non-blocking | Manual observation | Fix-forward in next release |

---

## 6. Environment Management

### 6.1 Configuration File

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

### 6.2 Environment Variable Overrides

Scripts accept runtime overrides (useful for testing against different targets):

| Variable | Default | Description |
|----------|---------|-------------|
| `SNOWFLAKE_CONNECTION` | `MY_TRIAL_ACCOUNT` | Connection profile name |
| `SNOWFLAKE_DATABASE` | `SSOM_COCO_DB` | Target database |
| `SNOWFLAKE_WAREHOUSE` | `COMPUTE_WH` | Compute warehouse |

### 6.3 Provisioning a New Environment

```sql
-- 1. Create database
CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_<ENV>;
GRANT OWNERSHIP ON DATABASE SSOM_COCO_DB_<ENV> TO ROLE ACCOUNTADMIN;

-- 2. Grant warehouse usage
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ACCOUNTADMIN;
```

```bash
# 3. Deploy
bash scripts/deploy.sh --env=<env>

# 4. Verify
bash scripts/run_smoke_tests.sh --env=<env>
```

---

## 7. Monitoring and Alerting

### 7.1 Deployment Health Checks

After every deployment, the pipeline validates:

| Check | Test File | Validates |
|-------|-----------|-----------|
| Schema existence | `tests/smoke_test.sql` | BRONZE, SILVER, GOLD, GOVERNANCE schemas |
| Object existence | `tests/smoke_test.sql` | All tables, views, stages, tasks |
| Object counts | `tests/integration_test.sql` | Minimum expected objects per schema |
| Procedure availability | `tests/integration_test.sql` | All ETL procedures callable |
| Masking policies | `tests/integration_test.sql` | Governance policies deployed |
| Data quality table | `tests/integration_test.sql` | DATA_QUALITY_LOG exists |

### 7.2 GitHub Actions Notifications

- **Success**: `::notice` annotation on the workflow run
- **Failure**: `::error` annotation with rollback instructions

### 7.3 Manual Health Check

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "
  SELECT TABLE_SCHEMA, COUNT(*) AS object_count
  FROM SSOM_COCO_DB.INFORMATION_SCHEMA.TABLES
  GROUP BY TABLE_SCHEMA
  ORDER BY TABLE_SCHEMA;
"
```

---

## 8. Incident Response

### 8.1 Severity Levels

| Level | Definition | Response Time | Examples |
|-------|------------|---------------|----------|
| SEV1 | Production data loss or corruption | Immediate | ETL writing bad data, tables dropped |
| SEV2 | Production pipeline broken | 30 minutes | Procedures failing, tasks stuck |
| SEV3 | Non-prod broken or degraded performance | 4 hours | QA deploy failure, slow queries |
| SEV4 | Cosmetic or documentation issue | Next sprint | Lint warnings, README outdated |

### 8.2 SEV1/SEV2 Response Playbook

```
1. ASSESS
   - Check GitHub Actions run logs
   - Check Snowflake query history: SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

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

### 8.3 Common Failure Scenarios

| Scenario | Symptoms | Resolution |
|----------|----------|------------|
| Warehouse suspended | `Warehouse COMPUTE_WH cannot be resumed` | `ALTER WAREHOUSE COMPUTE_WH RESUME;` |
| Key expired | `JWT token is invalid` | Rotate key (Section 3.2) |
| Account locked | `Authentication failed` | Unlock via Snowflake UI, check login attempts |
| Quota exceeded | `Exceeded resource limit` | Check `SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY` |
| Task stuck | Task shows EXECUTING indefinitely | `ALTER TASK ... SUSPEND;` then `RESUME;` |

---

## 9. Maintenance Tasks

### 9.1 Regular Maintenance Schedule

| Task | Frequency | Procedure |
|------|-----------|-----------|
| Key rotation | Every 90 days | Section 3.2 |
| Review query history | Weekly | Check long-running queries |
| Warehouse sizing | Monthly | Analyze `WAREHOUSE_LOAD_HISTORY` |
| Stale data check | Daily (automated) | `Run_Data_Quality_Checks()` |
| GitHub Actions cleanup | Monthly | Delete old workflow runs |

### 9.2 Cleaning Up Failed Deployments

If a deployment partially completed:

```bash
# Option A: Re-run the full deployment (idempotent - uses CREATE OR REPLACE)
bash scripts/deploy.sh --env=<env>

# Option B: Nuclear option - drop everything and redeploy
bash scripts/drop_objects.sh --confirm
bash scripts/create_objects.sh
```

### 9.3 Database Cloning (For Testing)

```sql
-- Clone prod to a test database
CREATE DATABASE SSOM_COCO_DB_TEST CLONE SSOM_COCO_DB_PROD;
```

---

## 10. Access Control

### 10.1 Current Setup

| Role | Access | Usage |
|------|--------|-------|
| `ACCOUNTADMIN` | Full access | Deployments, DDL, grants |
| `SYSADMIN` | Database management | Object creation |
| `PUBLIC` | Read-only on views | Dashboards, reporting |

### 10.2 Principle of Least Privilege (Recommended)

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

## 11. Linting and Code Quality

### 11.1 SQLFluff Configuration

File: `.sqlfluff`

```ini
[sqlfluff]
dialect = snowflake
templater = raw
max_line_length = 120
exclude_rules = LT05, RF04, LT02
```

Excluded rules:
- `LT05` — long lines (allowed up to 120)
- `RF04` — keywords as identifiers (e.g., `STATUS`, `DATE` columns are valid)
- `LT02` — indentation (DDL alignment is intentional)

### 11.2 Running Lint Locally

```bash
# Check for issues
sqlfluff lint Snowflake_Scripts/ --dialect snowflake --config .sqlfluff

# Auto-fix issues
sqlfluff fix Snowflake_Scripts/ --dialect snowflake --config .sqlfluff --force
```

### 11.3 Pre-Commit Hook (Optional)

```bash
# .git/hooks/pre-commit
#!/bin/bash
sqlfluff lint Snowflake_Scripts/ --dialect snowflake --config .sqlfluff
```

---

## 12. Disaster Recovery

### 12.1 Snowflake Time Travel

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

### 12.2 Full Environment Recovery

```bash
# 1. Recreate database
snow sql -c MY_TRIAL_ACCOUNT -q "CREATE DATABASE IF NOT EXISTS SSOM_COCO_DB_PROD;"

# 2. Redeploy from latest tag
git checkout $(git describe --tags --abbrev=0)
bash scripts/deploy.sh --env=prod

# 3. Reload data (if needed)
bash scripts/run_historical.sh
bash scripts/run_incremental.sh
```

---

## 13. Contacts and Escalation

| Role | Responsibility |
|------|----------------|
| DevOps Engineer | Pipeline failures, secret rotation, infra |
| Data Engineer | ETL logic, procedure bugs, data quality |
| DBA | Warehouse sizing, access control, performance |
| Product Owner | Release approval, rollback decisions |

---

## 14. Detailed Configuration Steps

This section provides step-by-step instructions for configuring the entire DevOps pipeline from scratch.

---

### 14.1 Snowflake Account Setup

#### Step 1: Verify Account Access

```bash
# Confirm you can reach the account
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE()"
```

Expected output:
```
| CURRENT_ACCOUNT_NAME() | CURRENT_USER() | CURRENT_ROLE() |
|------------------------|----------------|----------------|
| GW22129                | SOMSUJAY       | ACCOUNTADMIN   |
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
-- Grant warehouse usage
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ACCOUNTADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE SYSADMIN;

-- Grant database ownership (repeat for each DB)
GRANT ALL ON DATABASE SSOM_COCO_DB TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_QA TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_PREPROD TO ROLE ACCOUNTADMIN;
GRANT ALL ON DATABASE SSOM_COCO_DB_PROD TO ROLE ACCOUNTADMIN;
```

---

### 14.2 Local Development Environment Setup

#### Step 1: Install Prerequisites

```bash
# Snowflake CLI
pip install snowflake-cli-labs

# SQL linting
pip install sqlfluff

# Verify installations
snow --version
sqlfluff version
```

#### Step 2: Generate RSA Key Pair

```bash
# Generate private key (PKCS#8 format, unencrypted)
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/trial_key.p8 -nocrypt

# Set strict permissions
chmod 600 ~/.snowflake/trial_key.p8

# Generate public key
openssl rsa -in ~/.snowflake/trial_key.p8 -pubout -out ~/.snowflake/trial_key.pub
```

#### Step 3: Register Public Key in Snowflake

Extract the key body (without BEGIN/END headers):
```bash
grep -v "^---" ~/.snowflake/trial_key.pub | tr -d '\n'
```

Run in Snowflake:
```sql
ALTER USER SOMSUJAY SET RSA_PUBLIC_KEY='<paste-key-body-here>';
```

Verify:
```sql
DESC USER SOMSUJAY;
-- Look for RSA_PUBLIC_KEY_FP (fingerprint should be populated)
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

Set file permissions:
```bash
chmod 600 ~/.snowflake/connections.toml
```

#### Step 5: Verify Connection

```bash
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT 'Connection OK' AS status, CURRENT_WAREHOUSE() AS wh"
```

Expected:
```
| STATUS        | WH         |
|---------------|------------|
| Connection OK | COMPUTE_WH |
```

---

### 14.3 GitHub Repository Configuration

#### Step 1: Create GitHub Environments

Navigate to **Settings > Environments** and create:

| Environment | Protection Rules |
|-------------|-----------------|
| `qa` | None (auto-deploy) |
| `preprod` | None (auto-deploy) |
| `production` | Required reviewers, wait timer (optional) |

#### Step 2: Configure Repository Secrets

Navigate to **Settings > Secrets and variables > Actions > New repository secret**:

```
SNOWFLAKE_ACCOUNT        = KXAXARZ-GW22129
SNOWFLAKE_USER           = SOMSUJAY
SNOWFLAKE_PRIVATE_KEY    = <contents of ~/.snowflake/trial_key.p8>

SNOWFLAKE_PROD_ACCOUNT   = KXAXARZ-GW22129
SNOWFLAKE_PROD_USER      = SOMSUJAY
SNOWFLAKE_PROD_PRIVATE_KEY = <contents of ~/.snowflake/trial_key.p8>
```

To copy the private key:
```bash
cat ~/.snowflake/trial_key.p8 | pbcopy   # macOS
cat ~/.snowflake/trial_key.p8 | xclip    # Linux
```

#### Step 3: Verify Secrets Are Set

```bash
gh secret list
```

Expected output:
```
SNOWFLAKE_ACCOUNT           Updated 2026-07-17
SNOWFLAKE_USER              Updated 2026-07-17
SNOWFLAKE_PRIVATE_KEY       Updated 2026-07-17
SNOWFLAKE_PROD_ACCOUNT      Updated 2026-07-17
SNOWFLAKE_PROD_USER         Updated 2026-07-17
SNOWFLAKE_PROD_PRIVATE_KEY  Updated 2026-07-17
```

#### Step 4: Configure Branch Protection Rules

Navigate to **Settings > Branches > Add rule**:

| Branch Pattern | Rules |
|----------------|-------|
| `main` | Require PR, require status checks (CI Lint), no force push |
| `develop` | Require PR, require status checks (CI Lint) |
| `release/*` | Require PR from develop only |

---

### 14.4 environments.yml Configuration

This file drives all deployment scripts. Located at project root.

```yaml
# environments.yml
# Promotion path: dev → qa → preprod → prod

dev:
  database: SSOM_COCO_DB        # Development database
  warehouse: COMPUTE_WH          # Warehouse (overridable via SNOWFLAKE_WAREHOUSE)
  connection: MY_TRIAL_ACCOUNT   # Connection profile in connections.toml

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

**Key rules:**
- `connection` must match a section name in `~/.snowflake/connections.toml` (local) or the connection name written by CI scripts
- `warehouse` must exist in the target Snowflake account
- `database` is created during initial deployment if it doesn't exist (by `01_setup_schemas.sql` using `USE DATABASE`)

---

### 14.5 CI/CD Connection Configuration (How It Works)

In GitHub Actions, there is no `~/.snowflake/connections.toml`. The deploy scripts auto-create one from secrets:

```
SNOWFLAKE_ACCOUNT + SNOWFLAKE_USER + SNOWFLAKE_PRIVATE_KEY
                          │
                          ▼
         scripts/deploy.sh (python3 block)
                          │
                          ▼
         ~/.snowflake/connections.toml (created at runtime)
         [MY_TRIAL_ACCOUNT]
         account = "<from SNOWFLAKE_ACCOUNT>"
         user = "<from SNOWFLAKE_USER>"
         authenticator = "SNOWFLAKE_JWT"
         private_key_path = "~/.snowflake/ci_key.p8"
         warehouse = "<from SNOWFLAKE_WAREHOUSE or default COMPUTE_WH>"
                          │
                          ▼
         snow sql -c MY_TRIAL_ACCOUNT --database <DB> -f <script.sql>
```

The same pattern is used by `rollback.sh` and `run_smoke_tests.sh`.

---

### 14.6 SQLFluff Lint Configuration

File: `.sqlfluff` (project root)

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

**Rule exclusions explained:**

| Rule | Reason for Exclusion |
|------|---------------------|
| `LT05` | Allow lines up to 120 chars (SQL DDL can be verbose) |
| `RF04` | Column names like STATUS, DATE, TYPE are valid Snowflake identifiers |
| `LT02` | DDL property indentation is intentional for readability |

**Conventions enforced:**
- Keywords: UPPER CASE (`SELECT`, `CREATE`, `FROM`)
- Functions: UPPER CASE (`COUNT`, `IFF`, `CURRENT_TIMESTAMP`)
- Types: UPPER CASE (`VARCHAR`, `INTEGER`, `TIMESTAMP`)
- Indentation: 4 spaces
- Max line length: 120 characters

---

### 14.7 Streamlit Dashboard Configuration

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

### 14.8 End-to-End Verification Checklist

After completing all configuration steps, run this checklist:

```bash
# 1. Verify Snowflake connection
snow sql -c MY_TRIAL_ACCOUNT -q "SELECT 1 AS connected"

# 2. Verify warehouse exists
snow sql -c MY_TRIAL_ACCOUNT -q "SHOW WAREHOUSES LIKE 'COMPUTE_WH'"

# 3. Deploy to dev
bash scripts/deploy.sh --env=dev

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
sqlfluff lint Snowflake_Scripts/ --dialect snowflake --config .sqlfluff

# 9. Verify GitHub secrets (requires gh CLI authenticated)
gh secret list

# 10. Trigger a CI run
git checkout -b test/verify-pipeline
git commit --allow-empty -m "test: verify CI pipeline"
git push -u origin test/verify-pipeline
gh pr create --base develop --title "Test: verify CI pipeline" --body "Testing CI"
# Check that CI Lint passes, then close the PR
```

If all 10 steps pass, the environment is fully configured and operational.

---

### 14.9 Configuration Reference Summary

| Component | File/Location | Purpose |
|-----------|---------------|---------|
| Snowflake connection | `~/.snowflake/connections.toml` | Local CLI authentication |
| RSA private key | `~/.snowflake/trial_key.p8` | Key-pair auth credential |
| RSA public key | Registered on Snowflake user | Validates JWT tokens |
| Environment config | `environments.yml` | Database/warehouse/connection per env |
| GitHub secrets | Repository Settings | CI/CD authentication |
| Lint config | `.sqlfluff` | SQL formatting rules |
| Streamlit secrets | `streamlit_app/.streamlit/secrets.toml` | Dashboard auth |
| CI workflows | `.github/workflows/*.yml` | Pipeline definitions |
| Deploy script | `scripts/deploy.sh` | Orchestrates SQL deployment |
| Rollback script | `scripts/rollback.sh` | Reverts to prior version |
| Smoke tests | `tests/smoke_test.sql` | Post-deploy object checks |
| Integration tests | `tests/integration_test.sql` | Deep validation checks |

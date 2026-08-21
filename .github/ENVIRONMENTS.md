# GitHub Environments Setup Guide

This document describes how to configure GitHub Environments for the multi-stage deployment pipeline.

## Branching & Promotion Strategy

```
feature/* ──► develop ──► release/* ──► tag v*
                │              │            │
              [DEV]         [STAGE]       [PROD]
              (auto)       (auto)      (2 approvals)
```

## GitHub Environments to Create

Configure these in **Settings → Environments** in your GitHub repository.

### 1. `dev`

| Setting | Value |
|---------|-------|
| Deployment branches | `develop` |
| Required reviewers | None |
| Wait timer | None |

**Secrets:**
- `SNOWFLAKE_ACCOUNT` — Snowflake account identifier
- `SNOWFLAKE_USER` — Service account username
- `SNOWFLAKE_PRIVATE_KEY` — RSA private key for key pair auth

### 2. `stage`

| Setting | Value |
|---------|-------|
| Deployment branches | `release/*` |
| Required reviewers | 1 reviewer minimum |
| Wait timer | None |

**Secrets:**
- `SNOWFLAKE_ACCOUNT` — Snowflake account identifier
- `SNOWFLAKE_USER` — Service account username
- `SNOWFLAKE_PRIVATE_KEY` — RSA private key for key pair auth

### 3. `production`

| Setting | Value |
|---------|-------|
| Deployment branches | `main` only (tags) |
| Required reviewers | 2 reviewers minimum |
| Wait timer | 5 minutes (optional cool-down) |

**Secrets:**
- `SNOWFLAKE_PROD_ACCOUNT` — Production Snowflake account
- `SNOWFLAKE_PROD_USER` — Production service account username
- `SNOWFLAKE_PROD_PRIVATE_KEY` — Production RSA private key

## Snowflake Databases (per environment)

| Environment | Database | Schemas | Warehouse |
|-------------|----------|---------|-----------|
| DEV | `FINANCE_CORE_DEV` | RAW, CLEAN, CONFORMED, GOVERNANCE, METADATA | `COMPUTE_WH` |
| STAGE | `FINANCE_CORE_STAGE` | RAW, CLEAN, CONFORMED, GOVERNANCE, METADATA | `COMPUTE_WH` |
| PROD | `FINANCE_CORE_PROD` | RAW, CLEAN, CONFORMED, GOVERNANCE, METADATA | `COMPUTE_WH` |

Each environment is a fully isolated database. Schemas are identical across environments (no suffixes).

## Workflow Triggers

| Workflow | Trigger | Target |
|----------|---------|--------|
| `ci.yml` | PR to develop/release/main | Lint + validate only |
| `deploy-dev.yml` | Push to `develop` | DEV environment |
| `deploy-stage.yml` | Push to `release/*` | STAGE environment |
| `deploy-prod.yml` | Tag `v*` push | PROD environment |
| `deploy-prod.yml` (dispatch) | Manual trigger | PROD rollback |

## Deployment Commands (local)

```bash
# Deploy to any environment locally
bash scripts/deploy.sh --env=dev
bash scripts/deploy.sh --env=stage
bash scripts/deploy.sh --env=prod --dry-run   # always dry-run first for prod

# Rollback (stage/prod only)
bash scripts/rollback.sh --env=prod --version=v1.2.0

# Run tests
bash scripts/run_smoke_tests.sh --env=stage
```

## Rollback Procedure

### Via GitHub Actions (recommended for PROD):
1. Go to **Actions → Deploy to PROD**
2. Click **Run workflow**
3. Select action: `rollback`
4. Enter the target version tag (e.g., `v1.1.0`)
5. Two reviewers must approve the environment gate

### Via CLI (emergency):
```bash
bash scripts/rollback.sh --env=prod --version=v1.1.0
```

## Required Repository Secrets (non-environment-scoped)

If not using per-environment secrets, set these at the repository level:
- `SNOWFLAKE_ACCOUNT`
- `SNOWFLAKE_USER`
- `SNOWFLAKE_PRIVATE_KEY`
- `SNOWFLAKE_PROD_ACCOUNT` (for PROD isolation)
- `SNOWFLAKE_PROD_USER`
- `SNOWFLAKE_PROD_PRIVATE_KEY`

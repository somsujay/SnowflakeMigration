# GitHub Environments Setup Guide

This document describes how to configure GitHub Environments for the multi-stage deployment pipeline.

## Branching & Promotion Strategy

```
feature/* ──► develop ──► release/* ──► main ──► tag v*
                │              │            │          │
              [DEV]          [QA]      [Pre-PROD]   [PROD]
              (auto)        (auto)    (1 approval) (2 approvals)
```

## GitHub Environments to Create

Configure these in **Settings → Environments** in your GitHub repository.

### 1. `qa`

| Setting | Value |
|---------|-------|
| Deployment branches | `release/*` |
| Required reviewers | None |
| Wait timer | None |

**Secrets:**
- `SNOWFLAKE_ACCOUNT` — Snowflake account identifier
- `SNOWFLAKE_USER` — Service account username
- `SNOWFLAKE_PASSWORD` — Service account password

### 2. `preprod`

| Setting | Value |
|---------|-------|
| Deployment branches | `main` only |
| Required reviewers | 1 reviewer minimum |
| Wait timer | None |

**Secrets:**
- `SNOWFLAKE_ACCOUNT` — Snowflake account identifier
- `SNOWFLAKE_USER` — Service account username
- `SNOWFLAKE_PASSWORD` — Service account password

### 3. `production`

| Setting | Value |
|---------|-------|
| Deployment branches | `main` only (tags) |
| Required reviewers | 2 reviewers minimum |
| Wait timer | 5 minutes (optional cool-down) |

**Secrets:**
- `SNOWFLAKE_PROD_ACCOUNT` — Production Snowflake account
- `SNOWFLAKE_PROD_USER` — Production service account username
- `SNOWFLAKE_PROD_PASSWORD` — Production service account password

## Snowflake Databases (per environment)

| Environment | Database | Warehouse |
|-------------|----------|-----------|
| DEV | `SSOM_COCO_DB` | `SSOM_COCO_WH` |
| QA | `SSOM_COCO_DB_QA` | `SSOM_COCO_WH` |
| Pre-PROD | `SSOM_COCO_DB_PREPROD` | `SSOM_COCO_WH` |
| PROD | `SSOM_COCO_DB_PROD` | `PROD_WH` |

## Workflow Triggers

| Workflow | Trigger | Target |
|----------|---------|--------|
| `ci.yml` | PR to develop/release/main | Lint + validate only |
| `deploy-qa.yml` | Push to `release/*` | QA environment |
| `deploy-preprod.yml` | Push to `main` | Pre-PROD environment |
| `deploy-prod.yml` | Tag `v*` push | PROD environment |
| `deploy-prod.yml` (dispatch) | Manual trigger | PROD rollback |

## Deployment Commands (local)

```bash
# Deploy to any environment locally
bash scripts/deploy.sh --env=dev
bash scripts/deploy.sh --env=qa
bash scripts/deploy.sh --env=preprod
bash scripts/deploy.sh --env=prod --dry-run   # always dry-run first for prod

# Rollback (preprod/prod only)
bash scripts/rollback.sh --env=prod --version=v1.2.0

# Run tests
bash scripts/run_smoke_tests.sh --env=qa
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
- `SNOWFLAKE_PASSWORD`
- `SNOWFLAKE_PROD_ACCOUNT` (for PROD isolation)
- `SNOWFLAKE_PROD_USER`
- `SNOWFLAKE_PROD_PASSWORD`

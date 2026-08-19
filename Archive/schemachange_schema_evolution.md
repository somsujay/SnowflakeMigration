# Schemachange for Schema Evolution in Snowflake

## What is schemachange?

[schemachange](https://github.com/Snowflake-Labs/schemachange) is an open-source, lightweight Python-based database change management tool for Snowflake. It follows a similar approach to Flyway or Liquibase, providing version-controlled, repeatable database migrations.

It is distinct from Snowflake's built-in `ENABLE_SCHEMA_EVOLUTION` feature, which automatically adapts table schemas during data ingestion.

## Script Types

### Versioned Migrations (V scripts)

- Named like `V1.0.0__create_tables.sql`, `V1.1.0__add_column.sql`
- Run exactly once, in order, and tracked in a change history table
- Ideal for DDL changes such as `ALTER TABLE ADD COLUMN`, type changes, or constraint modifications

### Repeatable Migrations (R scripts)

- Named like `R__views.sql` or `R__stored_procs.sql`
- Re-run whenever their content changes (checksum-based)
- Ideal for views, stored procedures, and functions that should always reflect the latest definition

### Always-Run Scripts (A scripts)

- Named like `A__grants.sql`
- Run on every deployment regardless of whether content has changed
- Suitable for permissions, grants, and other idempotent operations

## Directory Structure Example

```
migrations/
  V1.0.0__initial_schema.sql
  V1.1.0__add_customer_email.sql
  V1.2.0__create_orders_table.sql
  V1.3.0__widen_product_name.sql
  R__reporting_views.sql
  A__grants.sql
```

## Schema Evolution Workflow

1. A developer writes a new versioned SQL script for the schema change.
2. The script is committed to version control and reviewed via PR.
3. CI/CD pipeline runs schemachange against the target environment.
4. schemachange checks the change history table and applies only new scripts.
5. The change history table is updated with the applied script metadata.

## Key Benefits for Schema Evolution

| Concern | How schemachange helps |
|---------|----------------------|
| Tracking what changed | Change history table records every applied script with timestamps |
| Ordering | Version numbers enforce strict execution order |
| Idempotency | Each versioned script runs exactly once per environment |
| Multi-environment support | Jinja templating + environment variables for dev/staging/prod |
| CI/CD integration | CLI-based, fits into GitHub Actions, Azure DevOps, Jenkins, etc. |
| Rollback awareness | Explicit rollback scripts can be written by convention |
| Auditability | Full history of who deployed what and when |

## Installation

```bash
pip install schemachange
```

## Basic Usage

```bash
schemachange deploy \
  --snowflake-account <account> \
  --snowflake-user <user> \
  --snowflake-role <role> \
  --snowflake-warehouse <warehouse> \
  --snowflake-database <database> \
  --root-folder migrations/ \
  --change-history-table METADATA.SCHEMACHANGE.CHANGE_HISTORY
```

## Jinja Templating for Multi-Environment Deployments

schemachange supports Jinja2 templating in SQL scripts, allowing environment-specific configurations:

```sql
-- V1.0.0__create_schema.sql
CREATE SCHEMA IF NOT EXISTS {{ env }}_ANALYTICS;

CREATE TABLE IF NOT EXISTS {{ env }}_ANALYTICS.CUSTOMERS (
    customer_id NUMBER,
    name VARCHAR(256),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Pass variables at deploy time:

```bash
schemachange deploy \
  --vars '{"env": "PROD"}' \
  ...
```

## schemachange vs. Snowflake Built-in Schema Evolution

| Feature | schemachange | Built-in ENABLE_SCHEMA_EVOLUTION |
|---------|-------------|----------------------------------|
| Use case | Planned DDL changes across environments | Auto-adapting to new file columns during ingestion |
| Trigger | Developer deploys migration scripts | COPY INTO / Snowpipe detects new columns in source files |
| Control | Full developer control over changes | Automatic (adds columns, drops NOT NULL) |
| Scope | Any DDL (tables, views, procedures, grants, etc.) | Table columns only |
| Environments | Multi-environment (dev/staging/prod) | Per-table setting |
| Audit trail | Change history table with full metadata | SchemaEvolutionRecord on column metadata |
| Rollback | Manual rollback scripts | No built-in rollback |

## When to Use schemachange

- Managing schema changes across multiple environments (dev, staging, prod)
- Needing a full audit trail of all DDL changes
- CI/CD-driven, repeatable deployments
- Intentional schema evolution (not just reacting to incoming data drift)
- Team collaboration where schema changes need code review

## When to Use Built-in Schema Evolution Instead

- Ingesting semi-structured data with frequently changing schemas
- Snowpipe or COPY INTO workflows where new columns appear in source files
- Scenarios where manual DDL intervention is impractical due to high schema change frequency

## CI/CD Integration Example (GitHub Actions)

```yaml
name: Deploy Schema Changes

on:
  push:
    branches: [main]
    paths:
      - 'migrations/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install schemachange
        run: pip install schemachange

      - name: Deploy to Snowflake
        env:
          SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
        run: |
          schemachange deploy \
            --snowflake-account $SNOWFLAKE_ACCOUNT \
            --snowflake-user $SNOWFLAKE_USER \
            --snowflake-password $SNOWFLAKE_PASSWORD \
            --snowflake-warehouse DEPLOY_WH \
            --snowflake-database MY_DB \
            --root-folder migrations/ \
            --change-history-table METADATA.SCHEMACHANGE.CHANGE_HISTORY
```

## Best Practices

1. **One change per script** - Keep each versioned migration focused on a single logical change.
2. **Never modify deployed scripts** - Once a versioned script has been applied, create a new script for corrections.
3. **Use repeatable scripts for views and procedures** - These are safe to recreate and benefit from always reflecting the latest logic.
4. **Test migrations in lower environments first** - Use the multi-environment support to validate changes before production.
5. **Include rollback scripts** - For critical changes, maintain a corresponding undo script by convention.
6. **Use descriptive names** - `V1.3.0__add_email_to_customers.sql` is clearer than `V1.3.0__update.sql`.

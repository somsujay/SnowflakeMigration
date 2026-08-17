# Schemachange Versioning Strategy

## Overview

This document defines the versioning convention for schemachange migrations across multiple domains. The strategy ensures collision-free parallel development, predictable execution order, and clear traceability.

## Key Principle

**One script per layer per domain per release** for initial table creation. All related tables within a medallion layer are grouped into a single versioned script. Subsequent changes (ALTERs, new tables) in later releases get individual scripts per change.

## Version Format

```
V<release>.<domain_id>.<layer><sequence>__<description>.sql
```

| Segment | Purpose | Range |
|---------|---------|-------|
| Release | Deployment wave / sprint | 1–999 |
| Domain ID | Owning domain (see registry) | 00–99 |
| Layer + Sequence | Medallion layer prefix + script order | 1xx=bronze, 2xx=silver, 3xx=gold |

### Layer Prefix Convention

Within each domain's sequence, the hundreds digit encodes the medallion layer:

| Range | Layer | Purpose |
|-------|-------|---------|
| 100–199 | Bronze | Raw ingestion, staging tables |
| 200–299 | Silver | Cleansed dimensions, SCD tables |
| 300–399 | Gold | Facts, aggregates, business views |

This guarantees bronze objects are created before silver references them, and silver before gold — within every domain.

### Script Granularity

| Scenario | Approach | Example |
|----------|----------|---------|
| Initial creation (release 1) | One script per layer, all tables bundled | `V1.10.100__create_bronze_tables.sql` |
| Subsequent ALTERs (release 2+) | One script per ALTER statement | `V2.10.100__add_country_to_customers.sql` |
| Adding new table later | Individual script for the new table | `V2.10.101__create_returns_table.sql` |

## Domain Registry

Domains are ordered by **dependency chain** — independent source domains first, aggregation domains last.

| ID | Domain | Scope | Dependency | Execution Priority |
|----|--------|-------|------------|--------------------|
| 00 | _platform | Databases, schemas, warehouses, integrations | None | First (infrastructure) |
| 10 | ecomm | Orders, products, customers, payments | Independent source | Source tier |
| 20 | bookings | Reservations, availability, scheduling | Independent source | Source tier |
| 30 | aftermarket | Service orders, parts, warranties | Depends on ecomm (post-sale) | Dependent tier |
| 40 | uds | Unified customer, cross-domain events, master data | Depends on all source domains | Aggregation tier |
| 80 | orchestration | Tasks, streams, pipes | Depends on all domain objects | Late |
| 90 | governance | Roles, grants, masking policies, data quality | Depends on all objects | Last |

**Why gaps of 10?** Allows inserting related sub-domains without renumbering:
- 11 = ecomm_loyalty, 12 = ecomm_marketplace
- 21 = bookings_hotels, 22 = bookings_flights
- 31 = aftermarket_warranty, 32 = aftermarket_recalls

Reserve IDs 50–79 for future independent or dependent domains.

## Dependency Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXECUTION ORDER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  00 _platform ─────────────────────────────────────────────────  │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────┐    ┌──────────┐                                    │
│  │10 ecomm │    │20 bookings│   ← Independent sources            │
│  └────┬────┘    └─────┬────┘                                    │
│       │               │                                          │
│       ▼               │                                          │
│  ┌─────────────┐      │                                          │
│  │30 aftermarket│ ◄───┘         ← Depends on ecomm + bookings   │
│  └──────┬──────┘                                                 │
│         │                                                        │
│         ▼                                                        │
│  ┌─────────┐                                                     │
│  │ 40 uds  │                    ← Aggregates all domains         │
│  └────┬────┘                                                     │
│       │                                                          │
│       ▼                                                          │
│  80 orchestration ─────────────────────────────────────────────  │
│       │                                                          │
│       ▼                                                          │
│  90 governance ────────────────────────────────────────────────  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Folder Structure

One script per layer per domain per release. All tables for a layer are grouped in a single file.

```
migrations/
├── _platform/
│   ├── V1.00.100__create_databases.sql
│   ├── V1.00.101__create_schemas.sql
│   └── V1.00.102__create_warehouses.sql
├── ecomm/
│   ├── bronze/  V1.10.100__create_bronze_tables.sql
│   ├── silver/  V1.10.200__create_silver_tables.sql
│   ├── gold/    V1.10.300__create_gold_tables.sql
│   └── gold/    R__ecomm_views.sql
├── bookings/
│   ├── bronze/  V1.20.100__create_bronze_tables.sql
│   ├── silver/  V1.20.200__create_silver_tables.sql
│   ├── gold/    V1.20.300__create_gold_tables.sql
│   └── gold/    R__bookings_views.sql
├── aftermarket/
│   ├── bronze/  V1.30.100__create_bronze_tables.sql
│   ├── silver/  V1.30.200__create_silver_tables.sql
│   ├── gold/    V1.30.300__create_gold_tables.sql
│   └── gold/    R__aftermarket_views.sql
├── uds/
│   ├── bronze/  V1.40.100__create_bronze_tables.sql
│   ├── silver/  V1.40.200__create_silver_tables.sql
│   ├── gold/    V1.40.300__create_gold_tables.sql
│   └── gold/    R__uds_views.sql
├── orchestration/
│   ├── V1.80.100__create_orchestration_framework.sql
│   └── R__ingestion_tasks.sql
└── governance/
    ├── V1.90.100__create_roles.sql
    ├── V1.90.101__create_masking_policies.sql
    └── A__grants.sql
```

**Convention:** Initial table creation uses one script per layer (bronze, silver, gold). Subsequent ALTERs in later releases get individual scripts (see [Handling Multiple ALTERs](#handling-multiple-alters)).

## Execution Order Example

For release 1, scripts execute globally in this order:

```
V1.00.100  _platform    → create databases
V1.00.101  _platform    → create schemas
V1.00.102  _platform    → create warehouses
V1.10.100  ecomm        → all bronze tables (orders, products, customers)
V1.10.200  ecomm        → all silver tables (dim_product, dim_customer)
V1.10.300  ecomm        → all gold tables (fact_orders, fact_revenue)
V1.20.100  bookings     → all bronze tables (reservations, availability)
V1.20.200  bookings     → all silver tables (dim_location, dim_channel)
V1.20.300  bookings     → all gold tables (fact_bookings, fact_occupancy)
V1.30.100  aftermarket  → all bronze tables (service_orders, parts, warranty)
V1.30.200  aftermarket  → all silver tables (dim_parts, dim_service_type)
V1.30.300  aftermarket  → all gold tables (fact_service, fact_warranty)
V1.40.100  uds          → all bronze tables (unified_customer, events)
V1.40.200  uds          → all silver tables (master_customer, timeline)
V1.40.300  uds          → all gold tables (customer_360, cross_domain)
V1.80.100  orchestration → orchestration framework
V1.90.100  governance   → create roles
V1.90.101  governance   → masking policies
```

## Handling Multiple ALTERs

Initial creation bundles all tables into one script per layer. Subsequent releases use individual scripts per change:

```
-- Release 1: initial creation (one script per layer)
V1.10.100__create_bronze_tables.sql    ← all ecomm bronze tables
V1.10.200__create_silver_tables.sql    ← all ecomm silver dimensions
V1.10.300__create_gold_tables.sql      ← all ecomm gold facts

-- Release 2: individual ALTERs and additions
V2.10.100__add_shipping_address_to_orders.sql
V2.10.101__add_discount_code_to_orders.sql
V2.10.102__add_loyalty_tier_to_customers.sql
V2.10.103__create_returns_table.sql

-- Release 2: silver/gold changes
V2.10.200__add_return_flag_to_dim_order_status.sql
V2.10.300__add_returns_to_fact_orders.sql
```

**Rule:** Initial creation = bundled. Changes after release 1 = one script per change (never bundle unrelated ALTERs).

## Rules

### Naming Conventions

- Use lowercase with underscores in descriptions
- Initial creation scripts: `V1.10.100__create_bronze_tables.sql` (layer-level name)
- ALTER scripts: `V2.10.100__add_<column>_to_<table>.sql` (specific change)
- New table additions: `V2.10.101__create_<table_name>.sql`

### Version Number Rules

1. **Never reuse a version number** — even if the script failed and was removed
2. **Never insert a version below the current max** — schemachange will skip it
3. **Always increment the sequence** within your domain and layer for new changes
4. **Increment the release** at sprint/deployment boundaries (coordinated across teams)
5. **Respect layer boundaries** — bronze (1xx), silver (2xx), gold (3xx)

### Cross-Domain Dependencies

Domain IDs are assigned by dependency tier:

| Tier | Domain IDs | Rule |
|------|-----------|------|
| Infrastructure | 00–09 | Runs first, no dependencies |
| Source (independent) | 10–29 | Independent data sources, no cross-domain refs |
| Dependent | 30–49 | May reference source-tier domains |
| Aggregation | 50–79 | May reference any lower-tier domain |
| Orchestration | 80–89 | References all domain objects |
| Governance | 90–99 | References all objects, runs last |

Rules:
- A domain may only reference objects from domains with a **lower** ID
- If a new domain depends on an existing one, assign it a higher ID
- If two domains are independent, assign them within the same tier (any order)

### Release Boundaries

Increment the release number when:

- Starting a new sprint or deployment cycle
- A coordinated cross-domain change is required
- Rolling back to a clean boundary is desirable

### Repeatable (R__) and Always (A__) Scripts

These are unversioned and run based on content changes (R) or every time (A):

```
migrations/ecomm/gold/R__ecomm_views.sql              → recreated on change
migrations/uds/gold/R__uds_views.sql                   → recreated on change
migrations/orchestration/R__ingestion_tasks.sql        → recreated on change
migrations/governance/A__grants.sql                    → runs every deployment
```

Use R__ for: views, procedures, tasks, dynamic table definitions
Use A__ for: grants, permissions that must be reapplied

### Script Header Template

```sql
/* ============================================================
   Domain   : ecomm
   Layer    : bronze
   Release  : 2
   Sequence : 102
   Purpose  : Add loyalty_tier column to T_CUSTOMER for
              segmentation pipeline
   Author   : team-ecomm
   Date     : 2026-07-29
   ============================================================ */
```

## Anti-Patterns

| Avoid | Why | Do Instead |
|-------|-----|------------|
| Inserting versions below current max | Schemachange skips them | Use next available sequence |
| Multiple domains sharing a domain ID range | Collisions in parallel dev | Strict domain ID ownership |
| Splitting initial tables into separate scripts | Unnecessary fragmentation | Bundle all tables per layer in release 1 |
| Bundling unrelated ALTERs in one file (release 2+) | Hard to debug, no partial rollback | One change per file for ALTERs |
| Using sequential integers (V1, V2, V3) | No domain separation, conflicts at scale | Use 3-part versioning |
| Hardcoding database names in scripts | Breaks multi-environment | Use `{{ database }}` Jinja vars |
| Gold scripts in 1xx sequence range | Layer ordering violated | Use 3xx for gold |
| Dependent domain with lower ID than source | Runs before dependency exists | Assign higher domain ID |
| Skipping layer prefix for "small" scripts | Inconsistency causes confusion | Always use layer prefix |

## Onboarding a New Domain

1. Determine the dependency tier (source, dependent, or aggregation)
2. Pick the next available domain ID within that tier
3. Update this document with the new domain entry
4. Create the folder structure: `migrations/<domain>/{bronze,silver,gold}/`
5. Create three initial scripts:
   - `V<release>.<id>.100__create_bronze_tables.sql`
   - `V<release>.<id>.200__create_silver_tables.sql`
   - `V<release>.<id>.300__create_gold_tables.sql`
6. Add R__ scripts for repeatable objects (views, procedures)

## Quick Reference Card

```
Format:  V<release>.<domain>.<layer><seq>__<description>.sql

Domain tiers:          Layer prefixes:
  00-09  platform        1xx  bronze
  10-29  source          2xx  silver
  30-49  dependent       3xx  gold
  50-79  aggregation
  80-89  orchestration
  90-99  governance

Script granularity:
  Release 1:  One script per layer  (create_bronze_tables.sql)
  Release 2+: One script per change (add_column_to_table.sql)

Example: V2.30.201__add_warranty_flag_to_dim_parts.sql
         │  │   │
         │  │   └── silver (2xx), 1st ALTER
         │  └────── aftermarket (domain 30)
         └───────── release 2
```

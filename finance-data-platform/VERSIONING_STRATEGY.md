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
| Layer + Sequence | Medallion layer prefix + script order | 1xx=raw, 2xx=clean, 3xx=conformed |

### Layer Prefix Convention

Within each domain's sequence, the hundreds digit encodes the medallion layer:

| Range | Layer | Purpose |
|-------|-------|---------|
| 100–199 | Raw | Raw ingestion, staging tables |
| 200–299 | Clean | Cleansed dimensions, SCD tables |
| 300–399 | Conformed | Facts, aggregates, business views |

This guarantees raw objects are created before clean references them, and clean before conformed — within every domain.

### Script Granularity

| Scenario | Approach | Example |
|----------|----------|---------|
| Initial creation (release 1) | One script per layer, all tables bundled | `V1.050.100__create_raw_tables.sql` |
| Subsequent ALTERs (release 2+) | One script per ALTER statement | `V2.050.100__add_country_to_customers.sql` |
| Adding new table later | Individual script for the new table | `V2.050.101__create_returns_table.sql` |

## Domain Registry

Domains are ordered by **dependency chain** — independent source domains first, aggregation domains last.

| ID | Domain | Scope | Dependency | Execution Priority |
|----|--------|-------|------------|--------------------|
| 000 | _platform | Databases, schemas, warehouses, integrations | None | First (infrastructure) |
| 050 | ecomm | Orders, products, customers, payments | Independent source | Source tier |
| 100 | bookings | Reservations, availability, scheduling | Independent source | Source tier |
| 150 | aftermarket | Service orders, parts, warranties | Depends on ecomm (post-sale) | Dependent tier |
| 200 | uds | Unified customer, cross-domain events, master data | Depends on all source domains | Aggregation tier |
| 800 | orchestration | Tasks, streams, pipes | Depends on all domain objects | Late |
| 900 | governance | Roles, grants, masking policies, data quality | Depends on all objects | Last |

**Why multiples of 50?** Allows inserting up to 49 sub-domains per parent without renumbering:
- 051 = ecomm_loyalty, 052 = ecomm_marketplace
- 101 = bookings_hotels, 102 = bookings_flights
- 151 = aftermarket_warranty, 152 = aftermarket_recalls

Reserve IDs 250–799 for future independent or dependent domains.

## Dependency Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXECUTION ORDER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  000 _platform ──────────────────────────────────────────────── │
│       │                                                          │
│       ▼                                                          │
│  ┌───────────┐    ┌────────────┐                                 │
│  │050 ecomm  │    │100 bookings│   ← Independent sources         │
│  └─────┬─────┘    └──────┬─────┘                                 │
│        │                 │                                        │
│        ▼                 │                                        │
│  ┌───────────────┐       │                                        │
│  │150 aftermarket│ ◄─────┘         ← Depends on ecomm + bookings │
│  └───────┬───────┘                                                │
│          │                                                        │
│          ▼                                                        │
│  ┌──────────┐                                                     │
│  │ 200 uds  │                    ← Aggregates all domains         │
│  └─────┬────┘                                                     │
│        │                                                          │
│        ▼                                                          │
│  800 orchestration ──────────────────────────────────────────── │
│        │                                                          │
│        ▼                                                          │
│  900 governance ─────────────────────────────────────────────── │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Folder Structure

Organized by **layer first**, then domain, then subdomain. All tables for a layer are grouped in a single file.

```
migrations/
├── _platform/
│   ├── V1.000.100__create_databases.sql
│   ├── V1.000.101__create_schemas.sql
│   └── V1.000.102__create_warehouses.sql
├── raw/
│   ├── ecomm/
│   │   ├── V1.050.100__create_raw_tables.sql
│   │   └── R__ecomm_raw_views.sql
│   ├── bookings/
│   │   └── V1.100.100__create_raw_tables.sql
│   ├── aftermarket/
│   │   └── V1.150.100__create_raw_tables.sql
│   └── uds/
│       └── V1.200.100__create_raw_tables.sql
├── clean/
│   ├── ecomm/
│   │   ├── V1.050.200__create_clean_tables.sql
│   │   └── R__ecomm_clean_views.sql
│   ├── bookings/
│   │   └── V1.100.200__create_clean_tables.sql
│   ├── aftermarket/
│   │   └── V1.150.200__create_clean_tables.sql
│   └── uds/
│       └── V1.200.200__create_clean_tables.sql
├── conformed/
│   ├── ecomm/
│   │   ├── V1.050.300__create_conformed_tables.sql
│   │   └── R__ecomm_views.sql
│   ├── bookings/
│   │   ├── V1.100.300__create_conformed_tables.sql
│   │   └── R__bookings_views.sql
│   ├── aftermarket/
│   │   ├── V1.150.300__create_conformed_tables.sql
│   │   └── R__aftermarket_views.sql
│   └── uds/
│       ├── V1.200.300__create_conformed_tables.sql
│       └── R__uds_views.sql
├── orchestration/
│   ├── V1.800.100__create_orchestration_framework.sql
│   └── R__ingestion_tasks.sql
└── governance/
    ├── V1.900.100__create_roles.sql
    ├── V1.900.101__create_masking_policies.sql
    └── A__grants.sql
```

**Convention:** Initial table creation uses one script per layer (raw, clean, conformed). Subsequent ALTERs in later releases get individual scripts (see [Handling Multiple ALTERs](#handling-multiple-alters)).

## Execution Order Example

For release 1, scripts execute globally in this order:

```
V1.000.100  _platform    → create databases
V1.000.101  _platform    → create schemas
V1.000.102  _platform    → create warehouses
V1.050.100  ecomm        → all raw tables (orders, products, customers)
V1.050.200  ecomm        → all clean tables (dim_product, dim_customer)
V1.050.300  ecomm        → all conformed tables (fact_orders, fact_revenue)
V1.100.100  bookings     → all raw tables (reservations, availability)
V1.100.200  bookings     → all clean tables (dim_location, dim_channel)
V1.100.300  bookings     → all conformed tables (fact_bookings, fact_occupancy)
V1.150.100  aftermarket  → all raw tables (service_orders, parts, warranty)
V1.150.200  aftermarket  → all clean tables (dim_parts, dim_service_type)
V1.150.300  aftermarket  → all conformed tables (fact_service, fact_warranty)
V1.200.100  uds          → all raw tables (unified_customer, events)
V1.200.200  uds          → all clean tables (master_customer, timeline)
V1.200.300  uds          → all conformed tables (customer_360, cross_domain)
V1.800.100  orchestration → orchestration framework
V1.900.100  governance   → create roles
V1.900.101  governance   → masking policies
```

## Handling Multiple ALTERs

Initial creation bundles all tables into one script per layer. Subsequent releases use individual scripts per change:

```
-- Release 1: initial creation (one script per layer)
V1.050.100__create_raw_tables.sql    ← all ecomm raw tables
V1.050.200__create_clean_tables.sql    ← all ecomm clean dimensions
V1.050.300__create_conformed_tables.sql      ← all ecomm conformed facts

-- Release 2: individual ALTERs and additions
V2.050.100__add_shipping_address_to_orders.sql
V2.050.101__add_discount_code_to_orders.sql
V2.050.102__add_loyalty_tier_to_customers.sql
V2.050.103__create_returns_table.sql

-- Release 2: clean/conformed changes
V2.050.200__add_return_flag_to_dim_order_status.sql
V2.050.300__add_returns_to_fact_orders.sql
```

**Rule:** Initial creation = bundled. Changes after release 1 = one script per change (never bundle unrelated ALTERs).

## Rules

### Naming Conventions

- Use lowercase with underscores in descriptions
- Initial creation scripts: `V1.050.100__create_raw_tables.sql` (layer-level name)
- ALTER scripts: `V2.050.100__add_<column>_to_<table>.sql` (specific change)
- New table additions: `V2.050.101__create_<table_name>.sql`

### Version Number Rules

1. **Never reuse a version number** — even if the script failed and was removed
2. **Never insert a version below the current max** — schemachange will skip it
3. **Always increment the sequence** within your domain and layer for new changes
4. **Increment the release** at sprint/deployment boundaries (coordinated across teams)
5. **Respect layer boundaries** — raw (1xx), clean (2xx), conformed (3xx)

### Cross-Domain Dependencies

Domain IDs are assigned by dependency tier:

| Tier | Domain IDs | Rule |
|------|-----------|------|
| Infrastructure | 000–049 | Runs first, no dependencies |
| Source (independent) | 050–149 | Independent data sources, no cross-domain refs |
| Dependent | 150–199 | May reference source-tier domains |
| Aggregation | 200–799 | May reference any lower-tier domain |
| Orchestration | 800–899 | References all domain objects |
| Governance | 900–999 | References all objects, runs last |

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
migrations/conformed/ecomm/R__ecomm_views.sql              → recreated on change
migrations/conformed/uds/R__uds_views.sql                   → recreated on change
migrations/orchestration/R__ingestion_tasks.sql        → recreated on change
migrations/governance/A__grants.sql                    → runs every deployment
```

Use R__ for: views, procedures, tasks, dynamic table definitions
Use A__ for: grants, permissions that must be reapplied

### Script Header Template

```sql
/* ============================================================
   Domain   : ecomm
   Layer    : raw
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
| Conformed scripts in 1xx sequence range | Layer ordering violated | Use 3xx for conformed |
| Dependent domain with lower ID than source | Runs before dependency exists | Assign higher domain ID |
| Skipping layer prefix for "small" scripts | Inconsistency causes confusion | Always use layer prefix |

## Onboarding a New Domain

1. Determine the dependency tier (source, dependent, or aggregation)
2. Pick the next available domain ID within that tier
3. Update this document with the new domain entry
4. Create the folder structure: `migrations/<domain>/{raw,clean,conformed}/`
5. Create three initial scripts:
   - `V<release>.<id>.100__create_raw_tables.sql`
   - `V<release>.<id>.200__create_clean_tables.sql`
   - `V<release>.<id>.300__create_conformed_tables.sql`
6. Add R__ scripts for repeatable objects (views, procedures)

## Quick Reference Card

```
Format:  V<release>.<domain>.<layer><seq>__<description>.sql

Domain tiers:          Layer prefixes:
  000-049  platform        1xx  raw
  050-149  source          2xx  clean
  150-199  dependent       3xx  conformed
  200-799  aggregation
  800-899  orchestration
  900-999  governance

Script granularity:
  Release 1:  One script per layer  (create_raw_tables.sql)
  Release 2+: One script per change (add_column_to_table.sql)

Example: V2.150.201__add_warranty_flag_to_dim_parts.sql
         │  │    │
         │  │    └── clean (2xx), 1st ALTER
         │  └─────── aftermarket (domain 150)
         └────────── release 2
```

## Scenario: Finance Data Platform with Subdomains

This scenario is derived from a real Teradata-to-Snowflake migration (finance-data-platform) that uses a 3-layer architecture (raw → clean → conformed) with two top-level domains (ecomm, aftermarket), each containing multiple functional subdomains (Bookings, Refunds, Budget, etc.).

### Source Platform Structure (Before Migration)

The original platform organizes SQL by layer first, then domain, then subdomain:

```
finance-data-platform/
├── raw/                          ← Layer 1: Raw ingestion
│   ├── ecomm/
│   │   ├── Bookings/            ← Subdomain with tables + procedures
│   │   ├── Budget/
│   │   ├── COGS/
│   │   ├── Forecast/
│   │   ├── Refunds/
│   │   └── Renewals/
│   └── aftermarket/
│       ├── Bookings/
│       └── Refunds/
├── clean/                        ← Layer 2: Cleansed/transformed
│   ├── ecomm/
│   │   ├── Actuals/
│   │   ├── Bookings/
│   │   ├── Budget/
│   │   ├── COGS/
│   │   ├── Customer/
│   │   ├── Forecast/
│   │   ├── Refunds/
│   │   ├── Renewals/
│   │   └── Sandbox/
│   └── aftermarket/
│       ├── Bookings/
│       └── Refunds/
└── conformed/                    ← Layer 3: Business-ready
    ├── ecomm/
    │   ├── Bookings/
    │   ├── Budget/
    │   ├── COGS/
    │   ├── Customer/
    │   ├── Forecast/
    │   ├── Refunds/
    │   ├── Renewals/
    │   └── Sandbox/
    └── aftermarket/
        ├── Bookings/
        └── Refunds/
```

Each subdomain folder contains `*_tables.sql` and `*_procedures.sql` (and optionally `*_views.sql`) files.

### Layer Mapping

The source platform uses `raw → clean → conformed` which maps to the versioning strategy's layer prefixes:

| Source Layer | Versioning Layer | Prefix | Purpose |
|--------------|-----------------|--------|---------|
| raw | Raw | 1xx | Raw ingestion, staging tables |
| clean | Clean | 2xx | Cleansed, transformed dimensions |
| conformed | Conformed | 3xx | Business-ready facts, consolidated views |

### Domain Registry (Finance Data Platform)

| ID | Domain | Subdomains | Dependency | Tier |
|----|--------|-----------|------------|------|
| 000 | _platform | — | None | Infrastructure |
| 050 | ecomm | Bookings, Refunds, Renewals, Customer | Independent source | Source |
| 051 | ecomm_budget | Budget, COGS, Forecast | Depends on ecomm | Source |
| 052 | ecomm_actuals | Actuals, Sandbox | Depends on ecomm + ecomm_budget | Source |
| 150 | aftermarket | Bookings, Refunds | Depends on ecomm (post-sale) | Dependent |
| 200 | uds | UDSOrder, UDSRefund | Aggregates ecomm + aftermarket | Aggregation |
| 800 | orchestration | Tasks, streams | Depends on all domain objects | Late |
| 900 | governance | Roles, masking, data quality | Depends on all objects | Last |

**Why this grouping:**
- `ecomm (050)`: Core transactional data — Bookings, Refunds, Renewals, Customer
- `ecomm_budget (051)`: Financial planning — Budget imports, COGS, Forecast calculations
- `ecomm_actuals (052)`: Actuals consolidation — depends on both bookings and budget data
- `aftermarket (150)`: Post-sale service — references ecomm order data
- `uds (200)`: Unified Data Store — consolidates across all domains (UDSOrder, UDSRefund)

### Dependency Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                         EXECUTION ORDER                                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  000 _platform ────────────────────────────────────────────────────   │
│       │                                                                │
│       ▼                                                                │
│  ┌───────────────────────────────────────────┐                         │
│  │ 050 ecomm (Bookings, Refunds,            │  ← Independent source   │
│  │           Renewals, Customer)             │                         │
│  └──┬────────────────────────────────────────┘                         │
│     │                                                                  │
│     ▼                                                                  │
│  ┌───────────────────────────────────────────┐                         │
│  │ 051 ecomm_budget (Budget, COGS,          │  ← Depends on ecomm    │
│  │                    Forecast)              │                         │
│  └──┬────────────────────────────────────────┘                         │
│     │                                                                  │
│     ▼                                                                  │
│  ┌───────────────────────────────────────────┐                         │
│  │ 052 ecomm_actuals (Actuals, Sandbox)     │  ← Depends on 050+051  │
│  └──┬────────────────────────────────────────┘                         │
│     │                                                                  │
│     ▼                                                                  │
│  ┌───────────────────────────────────────────┐                         │
│  │ 150 aftermarket (Bookings, Refunds)      │  ← Depends on ecomm    │
│  └──┬────────────────────────────────────────┘                         │
│     │                                                                  │
│     ▼                                                                  │
│  ┌───────────────────────────────────────────┐                         │
│  │ 200 uds (UDSOrder, UDSRefund)            │  ← Aggregates all      │
│  └──┬────────────────────────────────────────┘                         │
│     │                                                                  │
│     ▼                                                                  │
│  800 orchestration ────────────────────────────────────────────────   │
│       ▼                                                                │
│  900 governance ───────────────────────────────────────────────────   │
│                                                                        │
└──────────────────────────────────────────────────────────────────────┘
```

### Execution Order (Release 1)

```
V1.000.100  _platform              → create databases, schemas, warehouses

V1.050.100  ecomm/raw              → Ecomm_Bookings, BookingsConsol, Raw_ads_bill_line,
                                     fdm_forecast_bill_line tables
V1.050.200  ecomm/clean            → Ecomm_Bookings_clean, BookingsConsol_clean,
                                     Refunds_clean, Renewals_clean, Customer_clean
V1.050.300  ecomm/conformed        → Ecomm_Bookings_conformed, BookingsConsol_conformed,
                                     Refunds_conformed, Renewals_conformed, Customer_conformed

V1.051.100  ecomm_budget/raw       → FinBudget_ImpNonGCR_Prod, POP_Calc_Alloc_IR,
                                     FinBudget_ImpCOGS_Prod, FinBudgetView_CalcForecast
V1.051.200  ecomm_budget/clean     → Budget_clean, COGS_clean, Forecast_clean
V1.051.300  ecomm_budget/conformed → BudgetCase_conformed, publish_daily_budget,
                                     COGS_conformed, Forecast_conformed

V1.052.100  ecomm_actuals/raw      → CreateBC_Staging_ActualsOnly tables
V1.052.200  ecomm_actuals/clean    → Actuals_clean, Sandbox_Model_Bookings_clean
V1.052.300  ecomm_actuals/conformed→ Create_CombinedBudgetCase, Sandbox_conformed

V1.100.100  aftermarket/raw        → Aftermarket_Orders, Aftermarket_Comprehensive,
                                     Aftermarket_Refunds tables
V1.100.200  aftermarket/clean      → Aftermarket_Orders_clean, Comprehensive_clean,
                                     Refunds_clean
V1.100.300  aftermarket/conformed  → Aftermarket_Orders_conformed, ConsTbl_conformed,
                                     Comprehensive_conformed, Refunds_conformed

V1.200.100  uds/raw                → UDSOrder, UDSRefund tables
V1.200.200  uds/clean              → UDSOrder_clean, UDSRefund_clean
V1.200.300  uds/conformed          → UDSOrder_conformed, UDSRefund_conformed

V1.800.100  orchestration          → task framework, streams, pipes
V1.900.100  governance             → roles, masking policies
V1.900.101  governance             → data quality
```

### Migrated Folder Structure

```
migrations/
├── _platform/
│   └── V1.000.100__create_infrastructure.sql
├── raw/
│   ├── ecomm/
│   │   ├── V1.050.100__create_raw_tables.sql
│   │   └── R__ecomm_raw_views.sql
│   ├── ecomm_budget/
│   │   └── V1.051.100__create_raw_tables.sql
│   ├── ecomm_actuals/
│   │   └── V1.052.100__create_raw_tables.sql
│   ├── aftermarket/
│   │   └── V1.100.100__create_raw_tables.sql
│   └── uds/
│       └── V1.200.100__create_raw_tables.sql
├── clean/
│   ├── ecomm/
│   │   ├── V1.050.200__create_clean_tables.sql
│   │   └── R__ecomm_clean_views.sql
│   ├── ecomm_budget/
│   │   └── V1.051.200__create_clean_tables.sql
│   ├── ecomm_actuals/
│   │   └── V1.052.200__create_clean_tables.sql
│   ├── aftermarket/
│   │   └── V1.100.200__create_clean_tables.sql
│   └── uds/
│       └── V1.200.200__create_clean_tables.sql
├── conformed/
│   ├── ecomm/
│   │   ├── V1.050.300__create_conformed_tables.sql
│   │   └── R__ecomm_procedures.sql
│   ├── ecomm_budget/
│   │   ├── V1.051.300__create_conformed_tables.sql
│   │   └── R__budget_procedures.sql
│   ├── ecomm_actuals/
│   │   ├── V1.052.300__create_conformed_tables.sql
│   │   └── R__actuals_procedures.sql
│   ├── aftermarket/
│   │   ├── V1.100.300__create_conformed_tables.sql
│   │   └── R__aftermarket_procedures.sql
│   └── uds/
│       ├── V1.200.300__create_conformed_tables.sql
│       └── R__uds_procedures.sql
├── orchestration/
│   ├── V1.800.100__create_orchestration_framework.sql
│   └── R__ingestion_tasks.sql
└── governance/
    ├── V1.900.100__create_masking_policies.sql
    ├── V1.900.101__create_data_quality.sql
    └── A__grants.sql
```

### Subdomain Rules

1. **Parent runs before child** — domain `050` (ecomm) always executes before `051` (ecomm_budget) and `052` (ecomm_actuals) because schemachange sorts versions numerically
2. **Parents at multiples of 50** (050, 100, 150...) with subdomains using sequential IDs (051, 052, ..., 099) — supports up to **49 subdomains per parent**
3. **Cross-subdomain references** are safe within the same parent tier (domain 051 can reference domain 050 objects since 051 > 050)
4. **Procedures go in R__ scripts** — the source platform has separate `*_procedures.sql` files per subdomain; these become repeatable scripts that are re-applied on content change
5. **Release 2+ ALTERs** stay scoped to their subdomain:
   ```
   V2.050.100__add_channel_to_bookings.sql
   V2.051.201__add_allocation_tier_to_budget.sql
   V2.150.100__add_warranty_flag_to_aftermarket_orders.sql
   ```
6. **Adding a subdomain later** requires no renumbering — assign the next available ID within the parent's range (e.g., `053` for a new ecomm subdomain like ecomm_loyalty)

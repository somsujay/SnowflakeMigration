/* ============================================================
   schemachange Always-Run: A__grants.sql
   PURPOSE : Apply grants and permissions on every deployment
   ============================================================ */

USE DATABASE {{ database }};

-- Grant usage on schemas to roles
GRANT USAGE ON SCHEMA {{ raw_schema }} TO ROLE {{ role }};
GRANT USAGE ON SCHEMA {{ clean_schema }} TO ROLE {{ role }};
GRANT USAGE ON SCHEMA {{ conformed_schema }} TO ROLE {{ role }};
GRANT USAGE ON SCHEMA {{ governance_schema }} TO ROLE {{ role }};

-- Grant SELECT on all tables/views in each schema
GRANT SELECT ON ALL TABLES IN SCHEMA {{ raw_schema }} TO ROLE {{ role }};
GRANT SELECT ON ALL TABLES IN SCHEMA {{ clean_schema }} TO ROLE {{ role }};
GRANT SELECT ON ALL TABLES IN SCHEMA {{ conformed_schema }} TO ROLE {{ role }};
GRANT SELECT ON ALL VIEWS IN SCHEMA {{ conformed_schema }} TO ROLE {{ role }};

-- Grant future privileges
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ raw_schema }} TO ROLE {{ role }};
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ clean_schema }} TO ROLE {{ role }};
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ conformed_schema }} TO ROLE {{ role }};
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ conformed_schema }} TO ROLE {{ role }};

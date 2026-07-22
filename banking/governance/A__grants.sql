/* ============================================================
   schemachange Always-Run: A__grants.sql
   PURPOSE : Apply grants and permissions on every deployment
   ============================================================ */

USE DATABASE {{ database }};

-- Grant usage on schemas to roles
GRANT USAGE ON SCHEMA BRONZE TO ROLE {{ role }};
GRANT USAGE ON SCHEMA SILVER TO ROLE {{ role }};
GRANT USAGE ON SCHEMA GOLD TO ROLE {{ role }};
GRANT USAGE ON SCHEMA GOVERNANCE TO ROLE {{ role }};

-- Grant SELECT on all tables/views in each schema
GRANT SELECT ON ALL TABLES IN SCHEMA BRONZE TO ROLE {{ role }};
GRANT SELECT ON ALL TABLES IN SCHEMA SILVER TO ROLE {{ role }};
GRANT SELECT ON ALL TABLES IN SCHEMA GOLD TO ROLE {{ role }};
GRANT SELECT ON ALL VIEWS IN SCHEMA GOLD TO ROLE {{ role }};

-- Grant future privileges
GRANT SELECT ON FUTURE TABLES IN SCHEMA BRONZE TO ROLE {{ role }};
GRANT SELECT ON FUTURE TABLES IN SCHEMA SILVER TO ROLE {{ role }};
GRANT SELECT ON FUTURE TABLES IN SCHEMA GOLD TO ROLE {{ role }};
GRANT SELECT ON FUTURE VIEWS IN SCHEMA GOLD TO ROLE {{ role }};

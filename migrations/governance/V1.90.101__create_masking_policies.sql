/* ============================================================
   Domain   : governance
   Layer    : n/a
   Release  : 1
   Sequence : 101
   Purpose  : Create masking policies for PII
   Author   : team-governance
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOVERNANCE;

CREATE MASKING POLICY IF NOT EXISTS MP_MASK_EMAIL AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ECOMM_WRITER', 'RL_UDS_WRITER', 'SYSADMIN')
            THEN val
        ELSE REGEXP_REPLACE(val, '.+@', '***@')
    END;

CREATE MASKING POLICY IF NOT EXISTS MP_MASK_PHONE AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ECOMM_WRITER', 'RL_UDS_WRITER', 'SYSADMIN')
            THEN val
        ELSE CONCAT('***-***-', RIGHT(val, 4))
    END;

CREATE MASKING POLICY IF NOT EXISTS MP_MASK_NAME AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ECOMM_WRITER', 'RL_UDS_WRITER', 'SYSADMIN')
            THEN val
        ELSE '***MASKED***'
    END;

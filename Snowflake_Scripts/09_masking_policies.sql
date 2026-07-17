/* ============================================================
   FILE    : 09_masking_policies.sql
   PURPOSE : PII data masking policies for the Medallion layers
   SCHEMA  : GOVERNANCE
   NOTES   :
       - Partial masking: shows first character + '***' for names/locations
       - Email: first char + '***@' + domain
       - Phone: '***-***-' + last 4 digits
       - Financial IDs: prefix + '-***'
       - Amounts: zeroed out (0.00)
       - Unmasked for: SYSADMIN, ACCOUNTADMIN
       - All other roles see masked data
   ============================================================ */


-- ----------------------------------------------------------
-- Create governance schema
-- ----------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS GOVERNANCE
COMMENT = 'Masking policies and data governance objects';


/* ============================================================
   MASKING POLICIES
   ============================================================ */

-- ----------------------------------------------------------
-- MASK_NAME: Partial mask for personal names
-- Output: 'J***', 'A***' (first character visible)
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_NAME AS(VAL STRING)
RETURNS STRING ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    WHEN VAL IS NULL
        THEN NULL
    ELSE LEFT(VAL, 1) || '***'
END;


-- ----------------------------------------------------------
-- MASK_EMAIL: Partial mask for email addresses
-- Output: 'j***@gmail.com' (first char + domain preserved)
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_EMAIL AS(VAL STRING)
RETURNS STRING ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    WHEN VAL IS NULL
        THEN NULL
    ELSE LEFT(VAL, 1) || '***@' || SPLIT_PART(VAL, '@', 2)
END;


-- ----------------------------------------------------------
-- MASK_PHONE: Partial mask for phone numbers
-- Output: '***-***-0101' (last 4 digits visible)
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_PHONE AS(VAL STRING)
RETURNS STRING ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    WHEN VAL IS NULL
        THEN NULL
    ELSE '***-***-' || RIGHT(VAL, 4)
END;


-- ----------------------------------------------------------
-- MASK_LOCATION: Partial mask for geographic data
-- Output: 'T***', 'O***' (first character visible)
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_LOCATION AS(VAL STRING)
RETURNS STRING ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    WHEN VAL IS NULL
        THEN NULL
    ELSE LEFT(VAL, 1) || '***'
END;


-- ----------------------------------------------------------
-- MASK_FINANCIAL_ID: Partial mask for account/customer IDs
-- Output: 'CUST-***', 'ACCT-***' (prefix visible)
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_FINANCIAL_ID AS(VAL STRING)
RETURNS STRING ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    WHEN VAL IS NULL
        THEN NULL
    ELSE SPLIT_PART(VAL, '-', 1) || '-***'
END;


-- ----------------------------------------------------------
-- MASK_AMOUNT: Full redaction for financial amounts
-- Output: 0.00
-- ----------------------------------------------------------
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_AMOUNT AS(VAL NUMBER(18, 2))
RETURNS NUMBER(18, 2) ->
CASE
    WHEN IS_ROLE_IN_SESSION('SYSADMIN') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
        THEN VAL
    ELSE 0.00
END;


/* ============================================================
   APPLY POLICIES – BRONZE LAYER
   ============================================================ */

-- BRONZE.T_Customer
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.MASK_NAME;
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.MASK_NAME;
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN EMAIL_ADDRESS SET MASKING POLICY GOVERNANCE.MASK_EMAIL;
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN PHONE_NUMBER SET MASKING POLICY GOVERNANCE.MASK_PHONE;
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN CITY SET MASKING POLICY GOVERNANCE.MASK_LOCATION;
ALTER TABLE BRONZE.T_CUSTOMER MODIFY COLUMN STATE_PROVINCE SET MASKING POLICY GOVERNANCE.MASK_LOCATION;

-- BRONZE.T_Account
ALTER TABLE BRONZE.T_ACCOUNT MODIFY COLUMN ACCOUNT_ID SET MASKING POLICY GOVERNANCE.MASK_FINANCIAL_ID;

-- BRONZE.T_Transaction
ALTER TABLE BRONZE.T_TRANSACTION MODIFY COLUMN AMOUNT SET MASKING POLICY GOVERNANCE.MASK_AMOUNT;


/* ============================================================
   APPLY POLICIES – SILVER LAYER
   ============================================================ */

-- SILVER.DimCustomer
ALTER TABLE SILVER.DIMCUSTOMER MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.MASK_NAME;
ALTER TABLE SILVER.DIMCUSTOMER MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.MASK_NAME;
ALTER TABLE SILVER.DIMCUSTOMER MODIFY COLUMN EMAIL_ADDRESS SET MASKING POLICY GOVERNANCE.MASK_EMAIL;
ALTER TABLE SILVER.DIMCUSTOMER MODIFY COLUMN CITY SET MASKING POLICY GOVERNANCE.MASK_LOCATION;
ALTER TABLE SILVER.DIMCUSTOMER MODIFY COLUMN STATE_PROVINCE SET MASKING POLICY GOVERNANCE.MASK_LOCATION;


/* ============================================================
   APPLY POLICIES – GOLD LAYER
   ============================================================ */

-- GOLD.FactDailyTransaction
ALTER TABLE GOLD.FACTDAILYTRANSACTION MODIFY COLUMN AMOUNT SET MASKING POLICY GOVERNANCE.MASK_AMOUNT;

-- GOLD.FactDailyAgg
ALTER TABLE GOLD.FACTDAILYAGG MODIFY COLUMN TOTAL_AMOUNT SET MASKING POLICY GOVERNANCE.MASK_AMOUNT;


/* ============================================================
   VERIFICATION QUERIES
   ============================================================

   -- As SYSADMIN (should see full unmasked data):
   USE ROLE SYSADMIN;
   SELECT FIRST_NAME, LAST_NAME, EMAIL_ADDRESS, PHONE_NUMBER, CITY
   FROM BRONZE.T_Customer LIMIT 5;

   -- As PUBLIC or non-admin role (should see masked data):
   USE ROLE PUBLIC;
   SELECT FIRST_NAME, LAST_NAME, EMAIL_ADDRESS, PHONE_NUMBER, CITY
   FROM BRONZE.T_Customer LIMIT 5;
   -- Expected: J***, A***, j***@gmail.com, ***-***-0101, T***

   -- Check which policies are applied:
   SELECT *
   FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
       REF_ENTITY_NAME => 'SSOM_COCO_DB.BRONZE.T_CUSTOMER',
       REF_ENTITY_DOMAIN => 'TABLE'
   ));

   ============================================================ */

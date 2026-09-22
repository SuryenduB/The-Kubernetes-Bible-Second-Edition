-- ============================================================
-- IdentityIQ MSSQL Setup Script
-- Run BEFORE deploying the Kubernetes manifests.
-- This creates databases, users, schemas, synonyms required by IIQ.
-- ============================================================

-- 1. Create databases (idempotent)
IF DB_ID('identityiq') IS NULL CREATE DATABASE identityiq;
IF DB_ID('identityiqPlugin') IS NULL CREATE DATABASE identityiqPlugin;
IF DB_ID('identityiqah') IS NULL CREATE DATABASE identityiqah;
GO

-- 2. Create login (skip if exists)
IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'identityiq')
BEGIN
    CREATE LOGIN identityiq WITH PASSWORD = 'id3ntityIQ!-TQ8BaiOxKAL4v-4lCIxVx';
END;
GO

-- 3. Configure each database
--    identityiq
USE identityiq;
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'identityiq')
    CREATE USER identityiq FOR LOGIN identityiq;
GO
EXEC sp_addrolemember 'db_owner', 'identityiq';
GO
ALTER USER identityiq WITH DEFAULT_SCHEMA = identityiq;
GO
-- Synonym for IIQ to find spt_database_version without schema qualification
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = 'spt_database_version')
BEGIN
    CREATE SYNONYM spt_database_version FOR identityiq.spt_database_version;
END;
GO

--    identityiqPlugin
USE identityiqPlugin;
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'identityiq')
    CREATE USER identityiq FOR LOGIN identityiq;
GO
EXEC sp_addrolemember 'db_owner', 'identityiq';
GO

--    identityiqah (Access History)
USE identityiqah;
GO
-- Create schema for IIQ objects
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'identityiqah')
    EXEC('CREATE SCHEMA identityiqah');
GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'identityiq')
    CREATE USER identityiq FOR LOGIN identityiq;
GO
EXEC sp_addrolemember 'db_owner', 'identityiq';
GO
-- Also create identityiqah user
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'identityiqah')
    CREATE USER identityiqah FOR LOGIN identityiq;
GO
EXEC sp_addrolemember 'db_owner', 'identityiqah';
GO
-- Synonym for access history version check
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = 'spt_hist_database_version')
BEGIN
    CREATE SYNONYM spt_hist_database_version FOR identityiqah.spt_hist_database_version;
END;
GO
-- Minimal table so IIQ startup doesn't fail (full schema from SQL scripts)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'spt_hist_database_version' AND schema_id = SCHEMA_ID('identityiqah'))
BEGIN
    CREATE TABLE identityiqah.spt_hist_database_version (
        name VARCHAR(128) NOT NULL,
        system_version VARCHAR(32) NOT NULL,
        schema_version VARCHAR(32) NOT NULL,
        CONSTRAINT PK_spt_hist_database_version PRIMARY KEY (name)
    );
    INSERT INTO identityiqah.spt_hist_database_version (name, system_version, schema_version)
    VALUES ('main', '8.4-107', '8.4-88');
END;
GO

-- 4. Verify
SELECT 'identityiq user:' as info, name, default_schema_name FROM sys.database_principals WHERE name = 'identityiq' AND type IN ('S','U');
SELECT 'Synonyms in identityiq:' as info, name, base_object_name FROM sys.synonyms WHERE name IN ('spt_database_version');
SELECT 'Synonyms in identityiqah:' as info, name, base_object_name FROM sys.synonyms WHERE name IN ('spt_hist_database_version');
SELECT 'identityiqah tables:' as info, TABLE_SCHEMA, TABLE_NAME FROM information_schema.tables WHERE table_schema = 'identityiqah';

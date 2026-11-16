-- Runs once per apply as the RDS admin user. Safe to re-run.
-- Creates the app_user 'test', sets its password, and makes 'test' the owner of vertxprojdb.
-- Till ALTER DATABASE, db belongs to 'dbadmin' since RDS created it as the master user. So schema scripts run as app_user 'test' exactly like they do locally.

-- 1. Create the role if it is missing.
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
    WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
    \gexec

-- 2. Keep the password in sync with Terraform.
-- app_user and app_password are passed into command 'psql....bootstrap.sql' from run_schema.sh L:30
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')
    \gexec

-- 3. RDS rule: to hand ownership to a role, the admin must be a member of it first.
SELECT format('GRANT %I TO CURRENT_USER', :'app_user')
    \gexec

-- 4. The application role owns the database (and can create objects in schema public).
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user')
    \gexec
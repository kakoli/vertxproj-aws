-- ============================================================================
-- Database Setup Script
-- Executes all database scripts in the correct order.
--
-- Execute using:
-- psql -h <host> -U <user> -d <database> -f <dir_name>/setup.sql
-- ============================================================================

\echo '====================================================='
\echo 'Creating database schema...'
\echo '====================================================='

-- \i psql meta-command that reads and executes SQL commands from another external file
\i ./schema/drop_tables.sql
\i ./schema/tables.sql
\i ./schema/constraints.sql
--\i ./schema/indexes.sql

\echo '====================================================='
\echo 'Loading reference data...'
\echo '====================================================='

\i ./data/reference_data.sql

\echo '====================================================='
\echo 'Database setup completed successfully.'
\echo '====================================================='

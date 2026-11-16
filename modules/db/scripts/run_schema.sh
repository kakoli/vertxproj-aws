#!/bin/bash
# Runs ON THE EC2 INSTANCE. Uploaded and executed by Terraform (db module).
#
# 1. Bootstrap as the RDS admin: create the app role, make it the database owner.
# 2. Run ONE entry script (setup.sql) as the app role. It pulls in the other files
#    with \i ./schema/... , so the whole folder is uploaded and psql runs inside it.
#
# SCHEMA_MODE:
#   once    (default) run the entry script only if it was never applied; if any .sql file
#           changed since, print a warning and leave the database alone.
#   rebuild run the entry script every time this step runs. setup.sql drops the tables
#           first, so this DELETES DATA. Use it deliberately.
#
# The whole run (script + history row) is one transaction: it fully applies or not at all.
set -euo pipefail
export LC_ALL=C
cd /tmp/dbscripts
trap 'cd /; rm -rf /tmp/dbscripts' EXIT   # also removes db.env with the passwords

# shellcheck disable=SC1091
# PGHOST PGPORT DB_NAME ADMIN_USER ADMIN_PASSWORD APP_USER APP_PASSWORD ENTRY_SCRIPT SCHEMA_MODE
source ./db.env
export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT=10

if ! [[ "$ENTRY_SCRIPT" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: entry script name '$ENTRY_SCRIPT' may only use letters, digits, . _ -" >&2
  exit 1
fi

# pg_isready is a built-in utility used to check the connection status of a PostgreSQL server
echo "Waiting for the database at ${PGHOST}:${PGPORT} ..."
for i in $(seq 1 30); do
  if pg_isready -q -h "$PGHOST" -p "$PGPORT"; then break; fi
  if [ "$i" -eq 30 ]; then echo "Database not reachable" >&2; exit 1; fi
  sleep 10
done

echo "== Bootstrap as ${ADMIN_USER}: application role and database ownership =="
# PGUSER, PGPASSWORD etc. are built-in environment variables recognized natively by PostgreSQL client tools like psql
# bootstrap.sql is run as ADMIN_USER...after this step PGUSER is set to APP_USER
PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD" PGDATABASE=postgres \
  psql -v ON_ERROR_STOP=1 -q \
       -v app_user="$APP_USER" -v app_password="$APP_PASSWORD" -v db_name="$DB_NAME" \
       -f bootstrap.sql

echo "== Schema as ${APP_USER}: ${ENTRY_SCRIPT} (mode: ${SCHEMA_MODE}) =="
export PGUSER="$APP_USER" PGPASSWORD="$APP_PASSWORD" PGDATABASE="$DB_NAME"
q() { psql -v ON_ERROR_STOP=1 -q -At "$@"; }

# setup.sql uses \i, psql resolves these subscript filepaths relative to the directory where the bash script is running, not the folder where setup.sql is.
cd sql
if [ ! -f "$ENTRY_SCRIPT" ]; then
  echo "ERROR: entry script '$ENTRY_SCRIPT' not found in the uploaded scripts folder" >&2
  exit 1
fi

# History lives in its own schema, so a script that drops tables (or even schema public)
# cannot wipe the record of what was applied.
echo "CREATE SCHEMA IF NOT EXISTS deploy_meta;
      CREATE TABLE IF NOT EXISTS deploy_meta.schema_script_history (
        filename   text PRIMARY KEY,
        sha256     text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now())" | q

# One checksum over every .sql file (entry script and everything it includes, by path).
sum=$(find . -type f -name '*.sql' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
prev=$(echo "SELECT sha256 FROM deploy_meta.schema_script_history WHERE filename = :'n'" | q -v n="$ENTRY_SCRIPT")

run=false
if [ "$SCHEMA_MODE" = "rebuild" ]; then # Sets run=true regardless of whether files changed.
  run=true
elif [ -z "$prev" ]; then # First-time, checks if $prev is empty ([-z "$prev"]->Check if a String is Empty)
  run=true
elif [ "$prev" = "$sum" ]; then # No changes, safely skips execution
  echo "skipping  $ENTRY_SCRIPT (already applied, no .sql file changed)"
else # Hashes do not match, and you didn't ask for a rebuild(schema_mode=once), prints a warning and leaves db untouched.
  echo "WARNING   .sql files changed since $ENTRY_SCRIPT was applied; database left untouched." >&2
  echo "          To rebuild (DROPS and recreates the tables) set db_schema_mode = \"rebuild\"." >&2
fi

# setup.sql read by cat and piped into psql. Records the new $sum hash and timestamp in schema_script_history.
if [ "$run" = true ]; then
  echo "running   $ENTRY_SCRIPT"
  {
    echo "BEGIN;"
    cat "$ENTRY_SCRIPT"
    printf '\n;\nINSERT INTO deploy_meta.schema_script_history (filename, sha256) VALUES ('"'"'%s'"'"', '"'"'%s'"'"') ON CONFLICT (filename) DO UPDATE SET sha256 = EXCLUDED.sha256, applied_at = now();\nCOMMIT;\n' "$ENTRY_SCRIPT" "$sum"
  } | q # q is a small function defined earlier at L:49, runs psql on all following arguments
fi

echo "Schema step finished."
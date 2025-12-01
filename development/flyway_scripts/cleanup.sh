#!/bin/bash

# ==============================================================================
# cleanup.sh
# ------------------------------------------------------------------------------
# Performs a full cleanup of the target PDB (orclpdb.localdomain), dropping
# all users, tablespaces, and the Flyway history, allowing for a fresh
# re-deployment. Executed by and returns control to the 'root' user.
# ==============================================================================

# --- Variables ---
# The SYS password used for SQL*Plus and Flyway clean operations
DB_PASS="pass" 
SERVICE_NAME="orclpdb.localdomain"
SHORT_SERVICE_NAME="ORCLPDB"
FLYWAY_CLEAN_URL="jdbc:oracle:thin:@//localhost:1521/$SERVICE_NAME?oracle.jdbc.restrictGetTables=false&internal_logon=sysdba"

echo "--- 1. Performing Database Cleanup (Users & Tablespaces) ---"
echo "Running SQL commands as 'oracle' user via 'su - oracle -c'..."

# --- 1a. Connect to Oracle as 'oracle' user and execute SQL commands ---
# The entire SQL block is executed by the 'oracle' user in a subshell, 
# ensuring the main script remains running as 'root'.
su - oracle -c "sqlplus -S /nolog << EOF
CONNECT sys/$DB_PASS@localhost:1521/$SERVICE_NAME as sysdba

-- Alter session to target the specific PDB for cleanup operations
PROMPT Targeting PDB: $SERVICE_NAME
ALTER SESSION SET CONTAINER = $SHORT_SERVICE_NAME; 

-- Drop users first
PROMPT Dropping application users...
DROP USER stock_user CASCADE;
DROP USER app_readonly CASCADE;
DROP USER ml_analyst CASCADE;
DROP USER ml_developer CASCADE;

-- Drop tablespaces (INCLUDING CONTENTS AND DATAFILES is critical for cleanup)
PROMPT Dropping tablespaces...
DROP TABLESPACE stocks_data INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE stocks_index INCLUDING CONTENTS AND DATAFILES;

COMMIT;
EXIT;
EOF"

# Check the exit status of the 'su - oracle -c' command
if [ $? -ne 0 ]; then
    echo "WARNING: Database SQL cleanup failed (possibly due to non-existent objects). Continuing to Flyway clean."
fi

echo "--- 1b. Database users and tablespaces cleanup complete. ---"

# --- 2. Flyway Clean (Removing Schema History) ---
echo "--- 2. Starting Flyway 'clean' to reset migration history ---"

# Ensure we are in the deployment directory for relative file paths if needed
cd /opt/dba_deployment

# Execute the Flyway clean command as the current user (root)
# NOTE: The root user must have Flyway in its PATH environment variable.
flyway \
    -url="$FLYWAY_CLEAN_URL" \
    -user="sys" \
    -password="$DB_PASS" \
    -cleanDisabled=false \
    -schemas="FLYWAY_HISTORY" \
    clean

if [ $? -ne 0 ]; then
    echo "FATAL ERROR: Flyway 'clean' failed. Cannot redeploy safely. Aborting."
    exit 1
fi

echo "--- 3. Cleanup Complete ---"
echo "Database $SERVICE_NAME is now clean and ready for redeployment."
echo "Execution context has remained as 'root'."
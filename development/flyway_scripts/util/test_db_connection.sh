#!/bin/bash
# -----------------------------------------------------------------------------
# test_db_connection.sh
# -----------------------------------------------------------------------------
# Tests database connectivity using SQL*Plus via 'su - oracle -c'.
#
# Arguments:
#   $1: DB_USER (e.g., sys)
#   $2: DB_PASS (The password to test)
#   $3: DB_PDB_SERVICE_NAME (e.g., orclpdb.localdomain)
#
# Returns:
#   0 on success (valid credentials/connection)
#   1 on failure (invalid login or connection error)
# -----------------------------------------------------------------------------

# Function to Test Database Connection
function test_db_connection() {
    local DB_USER="$1"
    local pass_to_test="$2"
    local DB_PDB_SERVICE_NAME="$3"

    # Construct the full connection string
    local full_connect_string="$DB_USER/$pass_to_test@localhost:1521/$DB_PDB_SERVICE_NAME as sysdba"

    # Execute a simple query using 'su - oracle -c'
    # Send all output (including stderr) to the variable
    SQL_OUTPUT=$(
        su - oracle -c "sqlplus -S /nolog << EOF
        CONNECT $full_connect_string
        SELECT 1 FROM DUAL;
        EXIT;
EOF" 2>&1
    )
    
    # Check for common Oracle and shell errors in the output
    if echo "$SQL_OUTPUT" | grep -E 'ORA-|TNS-|SP2-|Invalid username/password|dbhome: command not found|Permission denied|unknown user' > /dev/null; then
        # Print a concise error message for the caller
        echo "FAILURE: Connection Test Failed. See error details below."
        echo "-----------------------------------"
        echo "$SQL_OUTPUT" | head -n 5
        echo "-----------------------------------"
        return 1 # Failure
    else
        echo "SUCCESS: Database connection established."
        return 0 # Success
    fi
}
# Note: This file only contains the function definition and will be sourced.
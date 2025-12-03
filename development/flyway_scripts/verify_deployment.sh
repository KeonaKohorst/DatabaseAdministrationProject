#!/bin/bash

# --- Configuration ---
# Set the ORACLE_SID and PDB Service Name required for the connection string
ORACLE_SID="CDB1" # This is the CDB SID, used only for clarity/environment setup if needed
DB_PDB_SERVICE_NAME="orclpdb.localdomain" 

# NOTE: The connection will now use 'su - oracle -c' which handles the environment.
DB_USER="sys"
CONNECT_STRING="$DB_USER/%DB_PASS_REPLACE%@localhost:1521/$DB_PDB_SERVICE_NAME as sysdba" 
# %DB_PASS_REPLACE% is a placeholder for safety, the pass is inserted later in the function.

# --- Prompt for Database Password (DB_PASS) and CHECK THAT IT WORKS---
UTIL_DIR="/opt/dba_deployment/util"
TEST_CONNECTION_SCRIPT="$UTIL_DIR/test_db_connection.sh"

# Ensure the utility script exists and source it
if [ -f "$TEST_CONNECTION_SCRIPT" ]; then
    source "$TEST_CONNECTION_SCRIPT"
else
    echo "CRITICAL ERROR: Utility script $TEST_CONNECTION_SCRIPT not found. Aborting."
    exit 1
fi

DB_PASS="" # Initialize variable
MAX_ATTEMPTS=3
ATTEMPTS=0

while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
    echo -n "Enter the DB_PASS for user '$DB_USER' for connection to '$DB_PDB_SERVICE_NAME': "
    read -r -s DB_PASS
    echo

    # Test the connection with the provided password, passing all required arguments
    echo "--- Testing Database Connection ($((ATTEMPTS + 1))/$MAX_ATTEMPTS) ---"
    test_db_connection "$DB_USER" "$DB_PASS" "$DB_PDB_SERVICE_NAME" 

    if [ $? -eq 0 ]; then
        echo "--- Connection validated. Proceeding with deployment verification. ---"
        break # Exit the loop, password is good
    else
        ATTEMPTS=$((ATTEMPTS + 1))
        echo "--- Invalid password or connection error. Please try again. ---"
    fi
done

# Check if the loop exited due to failure
if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
    echo ""
    echo "!!! CRITICAL FAILURE: Maximum login attempts reached. Aborting deployment verification. !!!"
    exit 1
fi
# The password is now stored in $DB_PASS

# --- SQL*Plus Function for Running Checks via 'su - oracle' ---
# This is the crucial fix: executing the command as the 'oracle' user.
run_sql_check() {
    local sql_query="$1"
    local check_name="$2"
    
    echo "--- Checking: $check_name ---"
    
    # Replace the placeholder in the CONNECT_STRING with the actual password
    local full_connect_string="${CONNECT_STRING/\%DB_PASS_REPLACE\%/$DB_PASS}"

    # Execute SQL using 'su - oracle -c' to ensure the correct environment/PATH
    SQL_OUTPUT=$(
        su - oracle -c "sqlplus -S /nolog << EOF
        CONNECT $full_connect_string
        SET PAGESIZE 0
        SET FEEDBACK OFF
        SET HEAD OFF
        $sql_query
        EXIT;
EOF"
    )
    
    # Remove leading/trailing whitespace and check if output is empty
    # Also strip out the 'Connected' message that su - oracle -c may show
    RESULT=$(echo "$SQL_OUTPUT" | grep -v 'Connected' | tr -d ' ' | tr -d '\n')
    
    if [ -n "$RESULT" ]; then
        # If COUNT(*) is being run, we show the number of rows.
        if [[ "$sql_query" == *"COUNT(*)"* ]]; then
             echo "SUCCESS: $check_name found. Row Count: $RESULT"
        else
             echo "SUCCESS: $check_name found. Result: $RESULT"
        fi
        echo "-----------------------------------"
    else
        echo "FAILURE: $check_name NOT found."
        echo "-----------------------------------"
        exit 1 # Abort on the first failure
    fi
}

echo "--- Starting Deployment Verification (Running as oracle via su) ---"
echo " "

# --- PHASE 1: Flyway and SQLLoader Success Checks ---
## 1. Tablespaces Exist (STOCKS_DATA and STOCKS_INDEX)
run_sql_check "SELECT tablespace_name FROM dba_tablespaces WHERE tablespace_name IN ('STOCKS_DATA', 'STOCKS_INDEX') ORDER BY tablespace_name;" "Tablespaces STOCKS_DATA and STOCKS_INDEX"

## 2. Users Exist
USERS_TO_CHECK="'APP_READONLY', 'ML_ANALYST', 'ML_DEVELOPER', 'STOCK_USER'"
run_sql_check "SELECT username FROM all_users WHERE username IN ($USERS_TO_CHECK) ORDER BY username;" "Users ($USERS_TO_CHECK)"

## 3. Table Exists (STOCK_USER.STOCKS)
run_sql_check "SELECT table_name FROM all_tables WHERE owner = 'STOCK_USER' AND table_name = 'STOCKS';" "Table STOCK_USER.STOCKS"

## 4. Indexes Exist (STOCKS_SYMBOL_IDX and STOCKS_DATE_IDX)
INDEXES_TO_CHECK="'STOCKS_SYMBOL_IDX', 'STOCKS_DATE_IDX'"
run_sql_check "SELECT index_name FROM all_indexes WHERE owner = 'STOCK_USER' AND index_name IN ($INDEXES_TO_CHECK) ORDER BY index_name;" "Indexes STOCKS_SYMBOL_IDX and STOCKS_DATE_IDX"

## 5. Unique Constraint Exists
run_sql_check "SELECT constraint_name FROM all_constraints WHERE owner = 'STOCK_USER' AND table_name = 'STOCKS' AND constraint_type = 'U' AND constraint_name LIKE '%SYMBOL_DATE_UNIQ%';" "Unique Constraint on STOCKS"

## 6. Data Row Count (Expected 10001)
run_sql_check "SELECT COUNT(*) FROM stock_user.stocks;" "Data Row Count in STOCK_USER.STOCKS"

echo " "
echo "--- ALL VERIFICATION CHECKS FOR SCHEMA PASSED. ---"


# --- Call separate scripts to ensure configuration worked too ---
/opt/dba_deployment/backup/verify_backup_config.sh "$DB_PASS" # The DB_PASS is passed as the first argument ($1) to the script

# Check the exit status of the last command (verify_backup_config.sh)
if [ $? -ne 0 ]; then
    echo " "
    echo "!!! FAILURE: Backup Configuration Verification FAILED. See output above. !!!"
    echo "--- DEPLOYMENT FAILED. ---"
    exit 1 # Exit the main script with a non-zero status
fi


#./auditing/verify_auditing_config.sh "$DB_PASS"
#./performance/verify_performance_config.sh "$DB_PASS"

echo " "
echo "--- ALL VERIFICATION CHECKS PASSED. Deployment is successful! ---"
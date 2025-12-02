#!/bin/bash

# --- Configuration (Must match setup_backup_config.sh) ---
DB_USER="sys"
ORACLE_BASE="/u01/app/oracle"
ORACLE_SID="cdb1" 
CDB_SERVICE_NAME="orcl.localdomain" 
CONNECT_STRING="$DB_USER/%DB_PASS_REPLACE%@localhost:1521/$CDB_SERVICE_NAME as sysdba" 

# Paths to verify
FRA_DIR="$ORACLE_BASE/oradata/$ORACLE_SID/FRA"
ARCHIVE_DIR="/u02/rman/$ORACLE_SID/stable_archives"
RMAN_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/rman"
TEST_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/test_scripts/backup_recovery_tests"
FINAL_LOG_DIR="$ORACLE_BASE/admin/$ORACLE_SID/logs/rman"
FINAL_LOG_CRON_DIR="$FINAL_LOG_DIR/cron"

# Expected files (checking presence of at least one from each copied group)
EXPECTED_RMAN_SCRIPTS=(
    "rman_daily_cold_fullbu_cdb1.sh" 
    "rman_monthly_stable_cold_fullbu_cdb1.sh"
)
EXPECTED_TEST_SCRIPTS=(
    "simulate_pitr_restore.sh" 
    "simulate_restore_from_monthly.sh"
)

# --- Prompt for Database Password (DB_PASS) ---
echo -n "Enter the DB_PASS for user '$DB_USER' for connection to '$CDB_SERVICE_NAME': "
read -r -s DB_PASS
echo

echo "--- Starting Backup Configuration Verification ---"
echo " "

# --- Helper Functions ---

# Function to run a SQL check via 'su - oracle -c'
function run_sql_check_as_oracle() {
    local sql_query="$1"
    local expected_result_pattern="$2"
    local check_name="$3"
    
    echo "--- DB Check: $check_name ---"
    
    # Replace the placeholder in the CONNECT_STRING with the actual password
    local full_connect_string="${CONNECT_STRING/\%DB_PASS_REPLACE\%/$DB_PASS}"

    # Execute SQL using su - oracle -c, suppress headers/feedback
    # NOTE: V$ views must be escaped as V\\$ to survive both the outer shell and the su -c shell.
    SQL_OUTPUT=$(
        su - oracle -c "sqlplus -S /nolog << 'EOF'
            CONNECT $full_connect_string
            SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
            $sql_query
            EXIT;
EOF"
    )

    # Use grep to check for the pattern, ignoring connection messages
    echo "$SQL_OUTPUT" | grep -v 'Connected' | grep -q "$expected_result_pattern"
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: $check_name verified. (Pattern: '$expected_result_pattern')"
    else
        echo "FAILURE: $check_name FAILED. Expected pattern '$expected_result_pattern' not found."
        echo "Actual Output Snippet (First 3 lines):"
        echo "$SQL_OUTPUT" | grep -v 'Connected' | head -n 3
        echo "-----------------------------------"
        exit 1 # Abort on failure
    fi
}

# Function to verify RMAN configuration via 'su - oracle -c'
function run_rman_check_as_oracle() {
    local rman_command="$1"
    local expected_result_pattern="$2"
    local check_name="$3"

    echo "--- RMAN Check: $check_name ---"
    
    # Execute RMAN target / via su - oracle -c (uses OS authentication)
    RMAN_OUTPUT=$(
        su - oracle -c "rman target / << EOF
            $rman_command
            EXIT;
EOF"
    )

    # Check the RMAN output for the required configuration pattern
    echo "$RMAN_OUTPUT" | grep -q "$expected_result_pattern"

    if [ $? -eq 0 ]; then
        echo "SUCCESS: $check_name verified. (Found pattern: '$expected_result_pattern')"
    else
        echo "FAILURE: $check_name FAILED. Expected pattern '$expected_result_pattern' not found."
        echo "Actual Output Snippet (RMAN Config):"
        echo "$RMAN_OUTPUT" | grep -A 2 'RMAN configuration' | head -n 5
        echo "-----------------------------------"
        exit 1 # Abort on failure
    fi
}


# Function to verify OS artifacts (directories, files)
function verify_os_artifact() {
    local artifact_path="$1"
    local expected_owner="oracle:dba"
    local artifact_type="$2" # directory or file
    local check_name="$3"

    echo "--- OS Check: $check_name ---"

    # Check existence
    if [ "$artifact_type" == "directory" ]; then
        if [ ! -d "$artifact_path" ]; then
            echo "FAILURE: Directory $artifact_path does not exist."
            exit 1
        fi
    elif [ "$artifact_type" == "file" ]; then
        if [ ! -f "$artifact_path" ]; then
            echo "FAILURE: File $artifact_path does not exist."
            exit 1
        fi
    fi

    # Check ownership using 'su - oracle -c' for safety, or direct ls if run as root
    OWNER=$(ls -ld "$artifact_path" | awk '{print $3":"$4}')
    
    if [ "$OWNER" == "$expected_owner" ]; then
        echo "SUCCESS: $check_name exists and ownership ($OWNER) is correct."
    else
        echo "WARNING: $check_name exists, but ownership is unexpected. Expected: $expected_owner, Found: $OWNER"
    fi
}

# Function to verify crontab entry
function verify_crontab() {
    local pattern="$1"
    local check_name="$2"

    echo "--- CRONTAB Check: $check_name ---"

    # Fetch crontab as 'oracle' user and check for pattern
    CRON_OUTPUT=$(su - oracle -c "crontab -l 2>/dev/null")

    echo "$CRON_OUTPUT" | grep -q "$pattern"

    if [ $? -eq 0 ]; then
        echo "SUCCESS: $check_name verified. Cron entry found."
    else
        echo "FAILURE: $check_name FAILED. Cron entry for pattern '$pattern' not found."
        echo "Actual crontab snippet:"
        echo "$CRON_OUTPUT" | grep 'rman_'
        echo "-----------------------------------"
        exit 1
    fi
}

# ----------------------------------------------------
## Phase 1: Database Parameter Checks
# ----------------------------------------------------

### 1. Show FRA Size and Location
# 100G = 107374182400 bytes. We check for the location path and the size value.
run_sql_check_as_oracle \
"SELECT value FROM V\$PARAMETER WHERE name = 'db_recovery_file_dest' AND isdefault = 'FALSE';" \
"$FRA_DIR" \
"FRA Location ($FRA_DIR)"

run_sql_check_as_oracle \
"SELECT value FROM V\$PARAMETER WHERE name = 'db_recovery_file_dest_size';" \
"107374182400" \
"FRA Size (100G)"

### 2. Show ARCHIVELOG Mode
run_sql_check_as_oracle "SELECT LOG_MODE FROM V\$DATABASE;" "ARCHIVELOG" "ARCHIVELOG Mode"

### 3. Show RMAN Configuration (Uses RMAN utility)
run_rman_check_as_oracle "SHOW ALL;" "CONFIGURE CONTROLFILE AUTOBACKUP ON;" "RMAN Control File Autobackup"

run_rman_check_as_oracle "SHOW ALL;" "CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;" "RMAN Retention Policy (7 days)"

# ----------------------------------------------------
## Phase 2: OS Artifact Checks
# ----------------------------------------------------

### 4. Show that the directories exist
verify_os_artifact "$FRA_DIR" "directory" "Flash Recovery Area Directory"
verify_os_artifact "$ARCHIVE_DIR" "directory" "Stable Archive Directory"
verify_os_artifact "$RMAN_SCRIPT_DIR" "directory" "RMAN Script Directory"
verify_os_artifact "$TEST_SCRIPT_DIR" "directory" "Test Script Directory"
verify_os_artifact "$FINAL_LOG_DIR" "directory" "RMAN Logs Directory"
verify_os_artifact "$FINAL_LOG_CRON_DIR" "directory" "RMAN Cron Logs Directory"

### 5. Show that the RMAN script files exist
for script in "${EXPECTED_RMAN_SCRIPTS[@]}"; do
    verify_os_artifact "$RMAN_SCRIPT_DIR/$script" "file" "RMAN Backup Script ($script)"
done

### 6. Show that the test script files exist
for script in "${EXPECTED_TEST_SCRIPTS[@]}"; do
    verify_os_artifact "$TEST_SCRIPT_DIR/$script" "file" "Backup Test Script ($script)"
done

### 7. Show that the crontab for the oracle user contains automation
# Check for a unique part of the daily job entry
verify_crontab "rman_daily_cold_fullbu_cdb1.sh" "Oracle Crontab Entry for Daily Backup"

echo " "
echo "--- ALL VERIFICATION CHECKS PASSED. Backup Configuration is successful! ---"
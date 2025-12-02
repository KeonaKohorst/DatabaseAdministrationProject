#!/bin/bash

# ==============================================================================
# setup_backup_config.sh
# ------------------------------------------------------------------------------
# 1. Configures the Flash Recovery Area (FRA) size and location.
# 2. Configures RMAN retention policy and default device types.
# 3. Creates necessary directories and copies RMAN backup/test scripts.
#
# NOTE: This script assumes ORACLE_BASE is /opt/oracle and ORACLE_SID is ORCL.
# It uses 'su - oracle -c' to execute database commands as the 'oracle' user.
# ==============================================================================

# --- 0. Argument and Environment Setup ---

# Define standard Oracle environment paths
ORACLE_BASE="/u01/app/oracle"
ORACLE_SID="CDB1" 
CDB_SERVICE_NAME="orcl.localdomain" # Use the CDB service name for FRA configuration

# Paths for the new configuration
RMAN_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/rman"
RMAN_LOG_DIR="$ORACLE_BASE/admin/$ORACLE_SID/logs/rman"
TEST_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/test_scripts/backup_recovery_tests"
FRA_DIR="$ORACLE_BASE/oradata/$ORACLE_SID/FRA"
ARCHIVE_DIR="/u02/rman/cdb1/stable_archives"

# Source directories for deployment scripts (as provided in the request)
DEPLOY_BACKUP_SCRIPTS="/opt/dba_deployment/backup/backup_rman_scripts"
DEPLOY_TEST_SCRIPTS="/opt/dba_deployment/backup/test_backup_scripts"

# Check for the required argument (DB_PASS)
CONFIG_DB_USER="sys"

if [ -z "$1" ]; then
    echo "WARNING: DB_PASS argument was missing. Prompting for password now."
    
    # Prompt the user for the password securely
    echo -n "Enter the DB_PASS for user '$CONFIG_DB_USER': "
    # Read the password into the CONFIG_DB_PASS variable without displaying it on the screen (-s)
    read -r -s CONFIG_DB_PASS
    echo # Print a newline after silent input
else
    # Password was provided as an argument, so use it
    CONFIG_DB_PASS="$1"
fi

# CORRECTED: Use the CDB_SERVICE_NAME for connecting to the CDB for FRA config.
# We will use TNS-less format: user/pass@service_name as sysdba
CONNECT_STRING="$CONFIG_DB_USER/$CONFIG_DB_PASS@localhost:1521/$CDB_SERVICE_NAME as sysdba"

echo "Starting Oracle Backup Configuration for $CDB_SERVICE_NAME (CDB)..."

# --- Helper Function for Database Commands ---
function run_sql_as_oracle() {
    local sql_commands="$1"
    
    echo "Attempting db connection with string: $CONNECT_STRING"
    # The 'su - oracle -c' command runs the SQL inside the Oracle environment
    # We use the full connect string for SQL*Plus
    su - oracle -c "sqlplus -S /nolog << EOF
        CONNECT $CONNECT_STRING
        SET ECHO ON
        SET FEEDBACK ON
        $sql_commands
        EXIT;
EOF"
    if [ $? -ne 0 ]; then
        echo "ERROR: SQL execution failed."
        return 1
    fi
    return 0
}

# --- 1. Configure Flash Recovery Area (FRA) ---
echo "--- 1. Configuring Flash Recovery Area (FRA) ---"

# Create FRA directory and set ownership
echo "Creating FRA directory: $FRA_DIR"
mkdir -p "$FRA_DIR"
chown oracle:dba "$FRA_DIR"
chmod 755 "$FRA_DIR"

SQL_FRA_CONFIG="
-- FRA configuration must happen at the CDB root level.
-- Since we connect using the CDB service name, no ALTER SESSION is needed.
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST='$FRA_DIR' SCOPE=BOTH;
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE=100G SCOPE=BOTH;
SHOW PARAMETER DB_RECOVERY_FILE_DEST;
SHOW PARAMETER DB_RECOVERY_FILE_DEST_SIZE;
"
run_sql_as_oracle "$SQL_FRA_CONFIG"
if [ $? -ne 0 ]; then exit 1; fi

# --- 2. Configure RMAN Settings ---
echo "--- 2. Configuring RMAN Policy and Devices ---"

RMAN_CONFIG_SCRIPT="
RUN {
    CONFIGURE CONTROLFILE AUTOBACKUP ON;
    CONFIGURE DEFAULT DEVICE TYPE TO DISK;
    CONFIGURE DEVICE TYPE DISK BACKUP TYPE TO BACKUPSET;
    CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
    SHOW ALL;
}
EXIT;
"
# CORRECTED RMAN CONNECTION: Use OS authentication (target /) when running via su - oracle -c
su - oracle -c "rman target / << EOF
$RMAN_CONFIG_SCRIPT
EOF"

if [ $? -ne 0 ]; then
    echo "ERROR: RMAN configuration failed."
    exit 1
fi

# --- 3. Setup RMAN Script Directory and Copy Files ---
echo "--- 3. Setting up RMAN script directories and copying files ---"
mkdir -p "$RMAN_SCRIPT_DIR"
chown oracle:dba "$RMAN_SCRIPT_DIR"

if [ -d "$DEPLOY_BACKUP_SCRIPTS" ]; then
    cp -v "$DEPLOY_BACKUP_SCRIPTS"/rman_daily_cold_fullbu_cdb1.sh "$RMAN_SCRIPT_DIR"/
    cp -v "$DEPLOY_BACKUP_SCRIPTS"/rman_monthly_stable_cold_fullbu_cdb1.sh "$RMAN_SCRIPT_DIR"/
    cp -v "$DEPLOY_BACKUP_SCRIPTS"/rman_yearly_stable_cold_fullbu_cdb1.sh "$RMAN_SCRIPT_DIR"/
    chown oracle:dba "$RMAN_SCRIPT_DIR"/*.sh
    chmod 700 "$RMAN_SCRIPT_DIR"/*.sh
else
    echo "WARNING: Deployment backup script source directory not found: $DEPLOY_BACKUP_SCRIPTS. Skipping script copy."
fi

# --- 4. Create Archival Backup Directory ---
echo "--- 4. Creating stable archival directory: $ARCHIVE_DIR ---"
mkdir -p "$ARCHIVE_DIR"
chown oracle:dba "$ARCHIVE_DIR"
chmod 750 "$ARCHIVE_DIR"

# --- 5. Create Log Directory for Cron Jobs ---
echo "--- 5. Creating RMAN log directory for cron: $RMAN_LOG_DIR ---"
mkdir -p "$RMAN_LOG_DIR"
chown oracle:dba "$RMAN_LOG_DIR"
chmod 775 "$RMAN_LOG_DIR"

# --- 6. Setup Backup/Recovery Test Scripts Directory and Copy Files ---
echo "--- 6. Setting up backup and recovery test script directories ---"
mkdir -p "$TEST_SCRIPT_DIR"
chown oracle:dba "$TEST_SCRIPT_DIR"

if [ -d "$DEPLOY_TEST_SCRIPTS" ]; then
    cp -v "$DEPLOY_TEST_SCRIPTS"/simulate_pitr_restore.sh "$TEST_SCRIPT_DIR"/
    cp -v "$DEPLOY_TEST_SCRIPTS"/simulate_restore_from_monthly.sh "$TEST_SCRIPT_DIR"/
    cp -v "$DEPLOY_TEST_SCRIPTS"/simulate_restore_from_yearly.sh "$TEST_SCRIPT_DIR"/
    chown oracle:dba "$TEST_SCRIPT_DIR"/*.sh
    chmod 700 "$TEST_SCRIPT_DIR"/*.sh
else
    echo "WARNING: Deployment test script source directory not found: $DEPLOY_TEST_SCRIPTS. Skipping test script copy."
fi

# --- 7. Create Log Directory for Backup Scripts ---
FINAL_LOG_DIR="$ORACLE_BASE/admin/cdb1/logs/rman"
echo "--- 7. Creating final RMAN log directory: $FINAL_LOG_DIR ---"
mkdir -p "$FINAL_LOG_DIR"
chown oracle:dba "$FINAL_LOG_DIR"
chmod 775 "$FINAL_LOG_DIR"



# --- 8. Set up Oracle User Crontab Entries
echo "--- 8. Configuring Crontab for the 'oracle' user (Idempotent Check) ---"

# Define Paths and Crontab Entries (CRONTAB_ENTRIES variable remains the same)
# ... (CRONTAB_ENTRIES definition block here, exactly as before) ...
CRON_JOB_DAILY="$RMAN_SCRIPT_DIR/rman_daily_cold_fullbu_cdb1.sh"
CRON_JOB_MONTHLY="$RMAN_SCRIPT_DIR/rman_monthly_stable_cold_fullbu_cdb1.sh"
CRON_JOB_YEARLY="$RMAN_SCRIPT_DIR/rman_yearly_stable_cold_fullbu_cdb1.sh"
CRON_JOB_CLEANUP="$RMAN_SCRIPT_DIR/rman_log_cleanup.sh"
RMAN_LOGS_DIR="$FINAL_LOG_DIR" 

# Define the exact entries to be appended (filtered from the main CRONTAB_ENTRIES variable)
CRONTAB_NEW_ENTRIES=$(cat << EOT
# =============================================================
# Oracle RMAN Backup Jobs (Installed by setup_backup_config.sh)
# =============================================================

# 1. Primary Daily Backup
0 23 * * * /bin/bash -c '$CRON_JOB_DAILY >> $RMAN_LOGS_DIR/daily_backup_\$(date +\\%Y\\%m\\%d).log 2>&1'

# 2. Stable Monthly Redundant Backup (NOT CURRENTLY ACTIVE)
#0 0 1 * * $CRON_JOB_MONTHLY >> $RMAN_LOGS_DIR/monthly_backup.log 2>&1

# 3. Yearly Redundant Backup
0 1 1 1 * /bin/bash -c '$CRON_JOB_YEARLY >> $RMAN_LOGS_DIR/yearly_shell_\$(date +\\%Y\\%m\\%d).log 2>&1'

# 4. Daily Log Cleanup
0 6 * * * $CRON_JOB_CLEANUP > /dev/null 2>&1

# =============================================================
EOT
)

# --- Install Crontab using a single secure stream (Heredoc) ---

# This command uses 'su' to switch user and then runs a block of commands.
# 1. 'crontab -l 2>/dev/null' lists existing jobs.
# 2. The output is filtered (grep -v) to remove existing RMAN jobs.
# 3. The new entries are appended.
# 4. The whole combined output is then piped back into 'crontab -' to set the new crontab.
su - oracle -c "
    (
    crontab -l 2>/dev/null | \
        grep -v \"$CRON_JOB_DAILY\" | \
        grep -v \"$CRON_JOB_MONTHLY\" | \
        grep -v \"$CRON_JOB_YEARLY\" | \
        grep -v \"$CRON_JOB_CLEANUP\"
    echo \"$CRONTAB_NEW_ENTRIES\"
    ) | crontab -
"
if [ $? -eq 0 ]; then
    echo "SUCCESS: Crontab entries successfully installed and synchronized for the 'oracle' user."
else
    echo "ERROR: Failed to install crontab entries for the 'oracle' user. Please check 'su' permissions and 'crontab' access."
fi

#---------------------------------------------------------

echo "Backup configuration script finished successfully."
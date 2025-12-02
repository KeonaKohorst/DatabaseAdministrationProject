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
ORACLE_SID="cdb1" 
CDB_SERVICE_NAME="orcl.localdomain" # Use the CDB service name for FRA configuration

# Paths for the new configuration
RMAN_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/rman"
RMAN_LOG_DIR="$ORACLE_BASE/admin/$ORACLE_SID/logs/rman"
TEST_SCRIPT_DIR="$ORACLE_BASE/admin/$ORACLE_SID/scripts/test_scripts/backup_recovery_tests"
FRA_DIR="$ORACLE_BASE/oradata/$ORACLE_SID/FRA"
ARCHIVE_DIR="/u02/rman/$ORACLE_SID/stable_archives"

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

# --- 2. Enable ARCHIVELOG mode and Configure RMAN Settings ---
echo "--- 2. Checking and Enabling ARCHIVELOG Mode ---"

# --- Define a simple helper for LOCAL OS auth (needed for startup/shutdown) ---
# We will use this block structure repeatedly in this section.
function run_local_sql_as_oracle() {
    local sql_commands="$1"
    su - oracle -c "sqlplus -S / as sysdba << EOF
        SET ECHO ON
        SET FEEDBACK ON
        $sql_commands
        EXIT;
EOF"
    if [ $? -ne 0 ]; then
        echo "ERROR: Local SQL execution failed."
        return 1
    fi
    return 0
}
# -------------------------------------------------------------------------------


# Check current mode by looking for the ARCHIVELOG string.
SQL_CHECK_MODE="SELECT LOG_MODE FROM V\$DATABASE;"
echo "Current Database Mode:"

# Execute SQL via run_sql_as_oracle helper (This can use TNS as the DB is OPEN now)
su - oracle -c "sqlplus -S /nolog << EOF
	CONNECT $CONNECT_STRING
	SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
	$SQL_CHECK_MODE
	EXIT;
EOF" | grep 'ARCHIVELOG' > /dev/null 2>&1

# If grep was successful (ARCHIVELOG found), the return code ($?) is 0.
if [ $? -eq 0 ]; then
	echo "Database is already in ARCHIVELOG mode. Skipping change."
else
	echo "Database is in NOARCHIVELOG mode. Initiating ARCHIVELOG setup..."

	# 1. Shutdown Immediate (Using LOCAL OS AUTH)
	SQL_SHUTDOWN="SHUTDOWN IMMEDIATE;"
	echo "Shutting down the database..."
	run_local_sql_as_oracle "$SQL_SHUTDOWN"
	if [ $? -ne 0 ]; then echo "ERROR: Database shutdown failed. Exiting."; exit 1; fi

	# 2. Startup Mount (Using LOCAL OS AUTH)
	SQL_STARTUP_MOUNT="STARTUP MOUNT;"
	echo "Starting up in MOUNT mode..."
	run_local_sql_as_oracle "$SQL_STARTUP_MOUNT"
	if [ $? -ne 0 ]; then exit 1; fi

	# 3. Enable ARCHIVELOG (Using LOCAL OS AUTH)
	SQL_ARCHIVELOG="
	ALTER DATABASE ARCHIVELOG;
	ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=USE_DB_RECOVERY_FILE_DEST' SCOPE=BOTH;
	"
	echo "Enabling ARCHIVELOG mode and setting archive destination to FRA..."
	run_local_sql_as_oracle "$SQL_ARCHIVELOG"
	if [ $? -ne 0 ]; then exit 1; fi

	# 4. Open Database (Using LOCAL OS AUTH)
	SQL_OPEN="ALTER DATABASE OPEN;"
	echo "Opening the database..."
	run_local_sql_as_oracle "$SQL_OPEN"
	if [ $? -ne 0 ]; then exit 1; fi

	echo "ARCHIVELOG mode successfully enabled."
fi


echo "--- 2.5. Configuring RMAN Policy and Devices ---"

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
FINAL_LOG_DIR="$ORACLE_BASE/admin/$ORACLE_SID/logs/rman"
echo "--- 7. Creating final RMAN log directory: $FINAL_LOG_DIR ---"
mkdir -p "$FINAL_LOG_DIR"
chown oracle:dba "$FINAL_LOG_DIR"
chmod 775 "$FINAL_LOG_DIR"

# --- 7.5 Create log directory for CRON jobs of backup scripts ---
echo "--- 7.5 Creating log directory for backup cron jobs: $FINAL_LOG_DIR/cron ---" 
mkdir -p "$FINAL_LOG_DIR/cron"
chown oracle:dba "$FINAL_LOG_DIR/cron"
chmod 775 "$FINAL_LOG_DIR/cron"



# --- 8. Configuring Crontab for the 'oracle' user (robust method) ---
echo "--- 8. Installing crontab via temporary file ---"

# Define Paths and Crontab Entries (CRONTAB_ENTRIES variable remains the same)
# ... (CRONTAB_ENTRIES definition block here, exactly as before) ...
CRON_JOB_DAILY="$RMAN_SCRIPT_DIR/rman_daily_cold_fullbu_cdb1.sh"
CRON_JOB_MONTHLY="$RMAN_SCRIPT_DIR/rman_monthly_stable_cold_fullbu_cdb1.sh"
CRON_JOB_YEARLY="$RMAN_SCRIPT_DIR/rman_yearly_stable_cold_fullbu_cdb1.sh"
CRON_JOB_CLEANUP="$RMAN_SCRIPT_DIR/rman_log_cleanup.sh"
RMAN_LOGS_DIR="$FINAL_LOG_DIR/cron" 

# Create a temp file
TMP_CRON_FILE=$(mktemp /tmp/oracle_cron.XXXXXX) || { echo "ERROR: mktemp failed"; exit 1; }

# Write a template into the temp file using a single-quoted heredoc so nothing expands (especially $(date ...))
cat > "$TMP_CRON_FILE" <<'CRON_TEMPLATE'
# =============================================================
# Oracle RMAN Backup Jobs (Installed by setup_backup_config.sh)
# =============================================================

# 1. Primary Daily Backup
0 23 * * * /bin/bash -c 'DAILY_JOB_PATH >> LOGS_DIR/daily_backup_$(date +\%Y\%m\%d).log 2>&1'

# 2. Stable Monthly Redundant Backup
0 0 1 * * MONTHLY_JOB_PATH >> LOGS_DIR/monthly_backup_$(date +\%Y\%m\%d).log 2>&1

# 3. Yearly Redundant Backup
0 1 1 1 * /bin/bash -c 'YEARLY_JOB_PATH >> LOGS_DIR/yearly_backup_$(date +\%Y\%m\%d).log 2>&1'

# 4. Daily Log Cleanup
0 6 * * * CLEANUP_JOB_PATH > /dev/null 2>&1

# =============================================================
CRON_TEMPLATE

# Replace placeholders with actual paths (sed won't execute the $(date ...))
sed -i \
    -e "s|DAILY_JOB_PATH|$CRON_JOB_DAILY|g" \
    -e "s|MONTHLY_JOB_PATH|$CRON_JOB_MONTHLY|g" \
    -e "s|YEARLY_JOB_PATH|$CRON_JOB_YEARLY|g" \
    -e "s|CLEANUP_JOB_PATH|$CRON_JOB_CLEANUP|g" \
    -e "s|LOGS_DIR|$RMAN_LOGS_DIR|g" \
    "$TMP_CRON_FILE"

# (Optional) show the file locally for debugging
echo "----- Generated crontab file (preview) -----"
sed -n '1,200p' "$TMP_CRON_FILE"
echo "-------------------------------------------"

# Install the crontab as the oracle user by pointing crontab to the file.
# This reads the file contents literally; crontab will not expand $(date ...).
chmod 644 "$TMP_CRON_FILE"
su - oracle -c "crontab $TMP_CRON_FILE"
RC=$?

if [ $RC -eq 0 ]; then
    echo "SUCCESS: Crontab installed for oracle user."
else
    echo "ERROR: Failed to install crontab (rc=$RC). Please check su/crontab permissions."
fi

# Clean up
rm -f "$TMP_CRON_FILE"

#---------------------------------------------------------

echo "Backup configuration script finished successfully."
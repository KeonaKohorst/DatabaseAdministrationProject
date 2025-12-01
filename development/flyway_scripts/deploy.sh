#!/bin/bash

# --- Set Database Variables ---
JDBC_OPTS="?oracle.jdbc.restrictGetTables=false&internal_logon=sysdba"
# Only the PDB URL is necessary now
DB_PDB_URL="jdbc:oracle:thin:@//localhost:1521/orclpdb.localdomain${JDBC_OPTS}" 

DB_USER="sys"
# --- Prompt for Database Password (DB_PASS) ---
echo -n "Enter the DB_PASS for user '$DB_USER': "
# Read the password into the DB_PASS variable without displaying it on the screen (-s)
# The -r flag prevents backslash escapes from being interpreted
read -r -s DB_PASS
echo
# The password is now stored in $DB_PASS

# Flyway configuration required for all runs (SYSDBA login and restricting tables)
FLYWAY_COMMON_OPTS="-user=$DB_USER -password=$DB_PASS -schemas=FLYWAY_HISTORY" 

# --- PHASE 1: PDB Structural Deployment (V1.0.0 to V1.0.2) ---
echo "--- 1. PHASE 1: Deploying PDB Structure (V1.0.0, V1.0.1, V1.0.2) ---"

# Target the PDB URL, running all scripts up to 1.0.2 (Tables and Indexes)
# We don't need CDB URL, baselineOnMigrate, or any skip flags anymore!
flyway -url="$DB_PDB_URL" $FLYWAY_COMMON_OPTS -target="1.0.2" migrate

if [ $? -ne 0 ]; then
    echo "ERROR: Flyway structural migration failed. Aborting."
    exit 1
fi

# --- PHASE 2: External Data Load and V1.0.4 Marker (DIRECT RUN) ---
echo "--- 2. PHASE 2: External Data Load (V1.0.4) ---"

# 1. Ensure the 'data' directory (source of .ctl and .csv) is owned by oracle
chown -R oracle:dba /opt/dba_deployment/data

# 2. Ensure the 'log' directory (destination for .log) is owned by oracle and writable
chown oracle:dba /opt/dba_deployment/log
chmod 775 /opt/dba_deployment/log

echo "--- 2a. Starting SQLLoader ---"

# Execute SQLLoader using 'su - oracle -c' to switch user and run the command.
# NOTE: The command string for the '-c' argument must be fully quoted.
su - oracle -c "sqlldr stock_user/pass@ORCLPDB control=/opt/dba_deployment/data/stocks.ctl log=/opt/dba_deployment/log/stocks.log"

if [ $? -ne 0 ]; then
    echo "ERROR: SQLLoader data load failed. Deployment incomplete."
    exit 1
fi

echo "SQLLoader data load complete. Applying Flyway marker (V1.0.4)."

# 2b. RUN FLYWAY MIGRATION AGAIN to apply the empty V1.0.4 marker script
# Flyway must stay running as root (or cosc-admin with sudo) for proper environment access
flyway -url="$DB_PDB_URL" $FLYWAY_COMMON_OPTS migrate

if [ $? -ne 0 ]; then
    echo "ERROR: Flyway V1.0.4 marker application failed. Manual check required."
    exit 1
fi


# --- PHASE 3: Database Configuration (Backup, Auditing, Performance) ---
echo "--- 3. Starting Database Configuration ---"
# --- Call separate scripts for configuration ---
./backup/setup_backup_config.sh "$DB_PASS" # The DB_PASS is passed as the first argument ($1) to the script
#./setup_auditing_config.sh
#./setup_performance_config.sh

echo "--- Deployment complete. ---"
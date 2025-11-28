#!/bin/bash

# --- Set Database Variables ---
DB_URL="jdbc:oracle:thin:@//10.12.43.235:1521/orclpdb.localdomain"
DB_USER="sys"
DB_PASS="pass"

# Flyway command string for reuse
FLYWAY_CMD="flyway -url=\"$DB_URL\" -user=\"$DB_USER\" -password=\"$DB_PASS\""

# 1. RUN FLYWAY MIGRATIONS (Structural, V1.0.0 to V1.0.3)
echo "--- 1. Starting Flyway Structural Migration (V1.0.0 to V1.0.3) ---"
$FLYWAY_CMD migrate

if [ $? -ne 0 ]; then
    echo "ERROR: Flyway structural migration failed. Aborting."
    exit 1
fi

# 2. CHECK IF V1.0.4 DATA LOAD IS PENDING
# Flyway info command returns 0 only if all pending migrations can be applied.
# We check the history table for V1.0.4, but an easier way is to check the output of info
if $FLYWAY_CMD info | grep "V1.0.4__data_load_via_sqlldr.sql" | grep -q "Pending"; then
    echo "--- 2a. V1.0.4 (Data Load) is Pending. Starting SQLLoader ---"
    
    # Execute SQLLoader (the external, non-Flyway step)
    sqlldr stock_user/pass@ORCLPDB control=/opt/dba_deployment/data/stocks.ctl log=/opt/dba_deployment/log/stocks.log

    if [ $? -ne 0 ]; then
        echo "ERROR: SQLLoader data load failed. Deployment incomplete."
        exit 1
    fi

    echo "SQLLoader data load complete. Applying Flyway marker."
    
    # 2b. RUN FLYWAY MIGRATION AGAIN to apply the empty V1.0.4 marker script
    $FLYWAY_CMD migrate
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Flyway marker application failed. Manual check required."
        exit 1
    fi
else
    echo "--- 2. V1.0.4 Data Load already applied. Skipping SQLLoader. ---"
fi


# 3. Database Configuration (Backup, Auditing, Performance)
echo "--- 3. Starting Database Configuration ---"

# --- Call separate scripts for configuration ---
#./setup_backup_config.sh
#./setup_auditing_config.sh
#./setup_performance_config.sh
# Check exit status after each call if strict error handling is needed

echo "--- Deployment complete. ---"
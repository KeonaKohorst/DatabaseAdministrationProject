#!/bin/bash
#-----------------------------------------------------------------------
# Script: simulate_restore_from_monthly.sh
# Purpose: Simulates a data loss event and recovers the entire CDB
#          (and ORCLPDB) using the RMAN monthly COLD backup tagged
#          'STABLE_MONTHLY_BU'.
# Execution: Run manually by the Oracle user.
# NOTE: This performs a full CDB restore, requiring the CDB to be shut down.
#-----------------------------------------------------------------------

# --- Environment Setup ---
export ORACLE_SID=cdb1
export ORAENV_ASK=NO
export ORACLE_BASE=/u01/app/oracle

# PDB and Backup configuration
TARGET_PDB='ORCLPDB'
USER_TO_IMPERSONATE='STOCK_USER'
TABLE_NAME='STOCKS'
DELETE_ROWS=10000 
BACKUP_TAG='STABLE_MONTHLY_BU' # Tag used in your monthly backup script

# Determine ORACLE_HOME
export ORACLE_HOME=$(cat /etc/oratab | grep -E "^$ORACLE_SID:" | cut -d ':' -f 2)
if [ -z "$ORACLE_HOME" ]; then
    export ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1"
fi
export PATH=$ORACLE_HOME/bin:$PATH
export NLS_DATE_FORMAT='DD-MON-YYYY HH24:MI:SS'


# --- Logging Configuration ---
LOG_DIR="$ORACLE_BASE/admin/$ORACLE_SID/logs/rman"
LOG_FILE="$LOG_DIR/monthly_restore_sim_$(date +\%Y\%m\%d_\%H\%M\%S).log"
mkdir -p $LOG_DIR

echo "========================================================================" | tee -a $LOG_FILE
echo "Starting Monthly Backup Restore Simulation at $(date)" | tee -a $LOG_FILE
echo "Target PDB: ${TARGET_PDB} | Rows to Delete: ${DELETE_ROWS}" | tee -a $LOG_FILE
echo "Using Backup Tag: ${BACKUP_TAG}" | tee -a $LOG_FILE
echo "========================================================================" | tee -a $LOG_FILE

# --- 1. INITIALIZATION: Ensure PDB is open for R/W ---
echo "1. Initializing: Ensuring PDB ${TARGET_PDB} is open for READ WRITE." | tee -a $LOG_FILE
sqlplus -s / as sysdba << EOF >> $LOG_FILE
ALTER PLUGGABLE DATABASE ${TARGET_PDB} OPEN;
EXIT;
EOF


# --- 2. PRE-CHECK: Get initial row count ---
echo "2. Checking initial row count in ${TARGET_PDB}..." | tee -a $LOG_FILE
INITIAL_ROWS=$(sqlplus -s / as sysdba << EOF
SET HEAD OFF FEED OFF;
ALTER SESSION SET CONTAINER = ${TARGET_PDB};
SELECT COUNT(*) FROM ${USER_TO_IMPERSONATE}.${TABLE_NAME};
EXIT;
EOF
)
INITIAL_ROWS=$(echo "$INITIAL_ROWS" | tr -d '[:space:]') 
echo "Initial Rows in ${TABLE_NAME}: ${INITIAL_ROWS}" | tee -a $LOG_FILE

# --- 3. DISASTER SIMULATION ---
# Capture the current timestamp BEFORE the DELETE for our recovery point.
RECOVERY_UNTIL_TIME=$(date +"%Y-%m-%d %H:%M:%S")

echo "3. Simulating disaster: Deleting ${DELETE_ROWS} rows from ${TABLE_NAME}." | tee -a $LOG_FILE
sqlplus -s / as sysdba << EOF >> $LOG_FILE
-- Switch the container and user schema
ALTER SESSION SET CONTAINER = ${TARGET_PDB};
ALTER SESSION SET CURRENT_SCHEMA = ${USER_TO_IMPERSONATE};

-- Run the destructive command
DELETE FROM ${TABLE_NAME} WHERE ROWNUM <= ${DELETE_ROWS};

-- Commit the deletion to make it permanent
COMMIT;
EXIT;
EOF

# Check post-disaster row count
echo "Checking post-disaster row count..." | tee -a $LOG_FILE
DELETED_ROWS=$(sqlplus -s / as sysdba << EOF
SET HEAD OFF FEED OFF;
ALTER SESSION SET CONTAINER = ${TARGET_PDB};
SELECT COUNT(*) FROM ${USER_TO_IMPERSONATE}.${TABLE_NAME};
EXIT;
EOF
)
DELETED_ROWS=$(echo "$DELETED_ROWS" | tr -d '[:space:]')
echo "POST-DISASTER Rows in ${TABLE_NAME}: ${DELETED_ROWS}" | tee -a $LOG_FILE

# Validation check
if [ "$DELETED_ROWS" -lt "$INITIAL_ROWS" ]; then
    echo "Disaster confirmed: Data deleted. Proceeding with full CDB recovery." | tee -a $LOG_FILE
else
    echo "ERROR: Data deletion failed or no rows were deleted. Cannot proceed. Exiting." | tee -a $LOG_FILE
    exit 1
fi

# --- 4. CDB SHUTDOWN (REQUIRED FOR FULL CDB RESTORE) ---
echo "4. Shutting down the CDB for full restore operation." | tee -a $LOG_FILE
sqlplus -s / as sysdba << EOF >> $LOG_FILE
SHUTDOWN IMMEDIATE;
EXIT;
EOF


# --- 5. FULL CDB RESTORE AND RECOVERY ---
echo "5. Starting RMAN FULL CDB RESTORE using tag ${BACKUP_TAG}..." | tee -a $LOG_FILE
echo "Recovery Target Time: ${RECOVERY_UNTIL_TIME}" | tee -a $LOG_FILE

rman target / log=$LOG_FILE append << RMAN_EOF
set echo on;
RUN {
    # 1. Start the CDB in MOUNT state immediately after connecting
    STARTUP MOUNT;

    # Allocate multiple channels for parallel I/O operations (Restores and Recovery)
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c2 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c3 DEVICE TYPE DISK;
    ALLOCATE CHANNEL c4 DEVICE TYPE DISK;
    
    # 2. Restore the full database using the specified monthly backup TAG.
    # We use 'FROM TAG' for robust RMAN parsing.
    RESTORE DATABASE FROM TAG '${BACKUP_TAG}' UNTIL TIME "TO_DATE('${RECOVERY_UNTIL_TIME}','YYYY-MM-DD HH24:MI:SS')";

    # 3. Recover the database by applying archive logs up to the UNTIL TIME.
    RECOVER DATABASE UNTIL TIME "TO_DATE('${RECOVERY_UNTIL_TIME}','YYYY-MM-DD HH24:MI:SS')";
    
    # 4. Open the CDB with RESETLOGS to create a new incarnation.
    ALTER DATABASE OPEN RESETLOGS;

    # Release the channels once the RUN block is complete
    RELEASE CHANNEL c1;
    RELEASE CHANNEL c2;
    RELEASE CHANNEL c3;
    RELEASE CHANNEL c4;
}
EXIT;
RMAN_EOF

RMAN_STATUS=$?

if [ $RMAN_STATUS -eq 0 ]; then
    echo "RMAN CDB Restore/Recovery completed successfully." | tee -a $LOG_FILE
else
    echo "ERROR: RMAN CDB Recovery failed (Status: $RMAN_STATUS). Check the RMAN log in $LOG_FILE." | tee -a $LOG_FILE
    exit 1
fi

# --- 6. VERIFICATION ---
echo "6. Checking final row count after recovery..." | tee -a $LOG_FILE
RECOVERED_ROWS=$(sqlplus -s / as sysdba << EOF
SET HEAD OFF FEED OFF;
ALTER SESSION SET CONTAINER = ${TARGET_PDB};
-- The CDB OPEN RESETLOGS command implicitly opens the PDBs, so no need to explicitly open it here.
SELECT COUNT(*) FROM ${USER_TO_IMPERSONATE}.${TABLE_NAME};
EXIT;
EOF
)
RECOVERED_ROWS=$(echo "$RECOVERED_ROWS" | tr -d '[:space:]')

echo "RECOVERED Rows in ${TABLE_NAME}: ${RECOVERED_ROWS}" | tee -a $LOG_FILE

if [ "$RECOVERED_ROWS" -eq "$INITIAL_ROWS" ]; then
    echo "SUCCESS: Recovery confirmed. Initial count ($INITIAL_ROWS) matches recovered count ($RECOVERED_ROWS)." | tee -a $LOG_FILE
else
    echo "FAILURE: Recovery may have partially failed. Initial count ($INITIAL_ROWS) does not match recovered count ($RECOVERED_ROWS)." tee -a $LOG_FILE
fi

echo "========================================================================" | tee -a $LOG_FILE
echo "Simulation finished at $(date)" | tee -a $LOG_FILE
echo "========================================================================" | tee -a $LOG_FILE

exit 0
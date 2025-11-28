#!/bin/bash

# --- Set Database Variables ---
DB_URL="jdbc:oracle:thin:@//10.12.43.235:1521/orclpdb.localdomain"
DB_USER="sys"
DB_PASS="pass"

# 1. Run Flyway Migrations (handles all SQL scripts V1.0.0 to V1.0.3)
echo "Starting Flyway SQL Migration..."
flyway -url="$DB_URL" -user="$DB_USER" -password="$DB_PASS" migrate

# Check Flyway exit status
if [ $? -ne 0 ]; then
    echo "Flyway migration failed. Aborting."
    exit 1
fi

# 2. Execute SQLLoader (for V1.0.4 - the data population step)
echo "Starting SQLLoader data load..."
sqlldr stock_user/pass@ORCLPDB control=/u01/app/oracle/oradata/ORCL/csv_data/stocks.ctl log=/u01/app/oracle/oradata/ORCL/csv_data/stocks.log

# Check SQLLoader exit status
if [ $? -ne 0 ]; then
    echo "SQLLoader failed. Deployment incomplete."
    exit 1
fi

# Now, from here we can do database configuration for backup/auditing/performance.

echo "Deployment complete."
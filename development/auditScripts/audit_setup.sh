#!/bin/bash

sqlplus / as sysdba <<EOF

-- initial audit set up

ALTER SYSTEM SET audit_trail = DB, extended SCOPE=SPFILE;

AUDIT CREATE ANY TABLE BY ACCESS;

AUDIT DROP ANY TABLE BY ACCESS;

AUDIT ALTER SYSTEM BY ACCESS;

AUDIT CREATE USER BY ACCESS;

AUDIT GRANT ANY PRIVILEGE BY ACCESS;

-- create archive table 
BEGIN
    -- Create table only if not exists
    EXECUTE IMMEDIATE '
        CREATE TABLE aud$_archive
        COMPRESS BASIC
        AS SELECT * FROM sys.aud$ WHERE 1=0
    ';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN
            NULL; -- table already exists
        ELSE
            RAISE;
        END IF;
END;
/
 
-- Create index only if not exists
BEGIN
    EXECUTE IMMEDIATE '
        CREATE INDEX aud$_archive_ts_idx
        ON aud$_archive (timestamp#)
    ';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN
            NULL; -- index already exists
        ELSE
            RAISE;
        END IF;
END;
/



-- function to archive logs and purge them after
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'ARCHIVE_PURGE_AUDIT_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => q'[ 
            DECLARE
                l_cutoff DATE := TRUNC(SYSDATE) - 30;
            BEGIN
                -- Archive rows
                INSERT /*+ APPEND */ INTO aud$_archive
                SELECT *
                FROM sys.aud$
                WHERE timestamp# < l_cutoff;

                -- Purge rows
                DELETE FROM sys.aud$
                WHERE timestamp# < l_cutoff;

                COMMIT;
            END;
        ]',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=MONTHLY;BYMONTHDAY=1;BYHOUR=02;BYMINUTE=00;BYSECOND=00',
        enabled         => TRUE,
        comments        => 'Monthly archive and purge of SYS.AUD$ older than 30 days'
    );
END;
/
EXIT;
EOF

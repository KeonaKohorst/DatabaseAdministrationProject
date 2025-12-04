-- show all entries from all users in the last 21 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE extended_timestamp >= SYSDATE - 21
ORDER BY extended_timestamp ASC;
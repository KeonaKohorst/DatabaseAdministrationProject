-- show all entries from all users in the last 14 to 7 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE extended_timestamp BETWEEN SYSDATE - 14 AND SYSDATE - 7
ORDER BY extended_timestamp ASC;
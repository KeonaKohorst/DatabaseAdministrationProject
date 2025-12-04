-- show all entries from all users in the last 30 to 21 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE extended_timestamp BETWEEN SYSDATE - 30 AND SYSDATE - 21
ORDER BY extended_timestamp ASC;
-- show all entries from all users except monitoring in the last 30 days

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username != 'MONITORING'
ORDER BY extended_timestamp ASC;
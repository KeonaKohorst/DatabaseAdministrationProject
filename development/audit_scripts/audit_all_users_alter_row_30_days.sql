-- show updates, inserts and deletes from any user in the last 30 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE action_name IN ('UPDATE', 'INSERT', 'DELETE')
ORDER BY extended_timestamp ASC;
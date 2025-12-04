-- show updates, inserts and deletes from any user in the last 14 to 7 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE extended_timestamp BETWEEN SYSDATE - 14 AND SYSDATE - 7 AND 
	action_name IN ('UPDATE', 'INSERT', 'DELETE')
ORDER BY extended_timestamp ASC;
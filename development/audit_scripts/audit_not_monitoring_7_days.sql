-- show all entries from all users except monitoring in the last 7 days

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username != 'MONITORING' AND
	extended_timestamp >= SYSDATE - 7
ORDER BY extended_timestamp ASC;
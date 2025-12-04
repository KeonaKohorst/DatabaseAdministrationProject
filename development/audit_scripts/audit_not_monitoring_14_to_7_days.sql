-- show all entries from all users except monitoring in the last 14 to 7 days ago


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username != 'MONITORING' AND
	extended_timestamp BETWEEN SYSDATE-14 AND SYSDATE - 7
ORDER BY extended_timestamp ASC;
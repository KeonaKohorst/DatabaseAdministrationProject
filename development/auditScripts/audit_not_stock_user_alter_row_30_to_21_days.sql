-- show updates, inserts and deletes from any user except stock_user in the last 30 to 21 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username != 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 30 AND SYSDATE - 21 AND 
	action_name IN ('UPDATE', 'INSERT', 'DELETE')
ORDER BY extended_timestamp ASC;
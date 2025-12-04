-- show updates, inderts and deletes from stock_user in last 14 to 7 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 14 AND SYSDATE - 7 AND 
	action_name IN ('UPDATE', 'INSERT', 'DELETE')
ORDER BY extended_timestamp ASC;
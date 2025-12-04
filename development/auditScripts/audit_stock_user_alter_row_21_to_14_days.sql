-- show updates, inderts and deletes from stock_user in last 21 to 14 days


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 21 AND SYSDATE - 14 AND 
	action_name IN ('UPDATE', 'INSERT', 'DELETE')
ORDER BY extended_timestamp ASC;
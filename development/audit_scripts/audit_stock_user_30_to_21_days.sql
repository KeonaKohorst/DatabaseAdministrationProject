-- show all entries from stock_user between 30 and 21 days ago

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 30 AND SYSDATE - 21
ORDER BY extended_timestamp ASC;
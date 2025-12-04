-- show all entries from stock_user between 14 and 7 days ago

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 14 AND SYSDATE - 7
ORDER BY extended_timestamp ASC;
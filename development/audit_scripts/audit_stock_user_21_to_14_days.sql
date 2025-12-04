-- show all entries from stock_user between 21 and 14 days ago

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp BETWEEN SYSDATE - 21 AND SYSDATE - 14
ORDER BY extended_timestamp ASC;
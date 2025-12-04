-- show all entries from stock_user in last 7 days

SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
WHERE username = 'stock_user' AND
	extended_timestamp >= SYSDATE - 7
ORDER BY extended_timestamp ASC;
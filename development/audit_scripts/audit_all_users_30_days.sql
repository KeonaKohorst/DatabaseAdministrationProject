-- show all entries from all users


SELECT username, extended_timestamp, action_name, obj_name, sql_text 
FROM DBA_AUDIT_TRAIL
ORDER BY extended_timestamp ASC;
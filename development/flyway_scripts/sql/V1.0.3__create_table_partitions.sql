-- Script: partition_stocks_table.sql
-- Purpose: Alters the stocks table to set partitions by data

-- Requirements: Connect to sqlplus as sysdba

-- Set container to orclpdb (pluggable database)
ALTER SESSION SET CONTAINER = orclpdb;

-- Set partitions by range (trade_date)
-- Interval option will continue to create partitions on a 3-month basis after the last partition.
-- ONLINE options guarantees very minimal if not null downtime.

ALTER TABLE STOCK_USER.STOCKS
	MODIFY PARTITION BY RANGE (trade_date)
	INTERVAL (NUMTOYMINTERVAL(3, 'MONTH'))
	(
		PARTITION STOCKS_BEFORE_2025 VALUES LESS THAN (TIMESTAMP, '2025-01-01 00:00:00') TABLESPACE stocks_data,
		PARTITION STOCKS_Q1_2025 VALUES LESS THAN (TIMESTAMP, '2025-04-01 00:00:00') TABLESPACE stocks_data,
		PARTITION STOCKS_Q2_2025 VALUES LESS THAN (TIMESTAMP, '2025-07-01 00:00:00') TABLESPACE stocks_data,
		PARTITION STOCKS_Q3_2025 VALUES LESS THAN (TIMESTAMP, '2025-10-01 00:00:00') TABLESPACE stocks_data,
		PARTITION STOCKS_Q4_2025 VALUES LESS THAN (TIMESTAMP, '2026-01-01 00:00:00') TABLESPACE stocks_data
	)
	ONLINE
	UPDATE INDEXES;
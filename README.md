# Database Administration Project - Algorithmic Trading Database

## Purpose of Database
The database stores historical stock market data to support machine learning models for financial forecasting and predictive analysis. In a production environment, the database would receive real-time updates at 5 minute intervals to maintain current market information.

## Key Users and Applications
Key users include machine learning developers who query the database to extract historical stock data for model training and analysis via Python applications. The five database administrators also serve as key users, responsible for database maintenance and optimization.

## Database Design
The database structure is based on the best structure for machine learning models. This could take the form of a data warehouse with a star schema, or rather a single flat table with all data in it. 

Since the database is hosted on the Digital Research Alliance of Canada’s PostgreSQL infrastructure rather than Oracle, the design cannot be implemented exactly as specified. However, for instructional purposes, the database is planned and documented as if it were deployed in an Oracle environment.

## Goals
- To integrate the database with a BI tool and provides charts of the data.
- To perform typical DBA tasks such as database configuration, backup and recovery, user management, security, performance tuning and maintenance.
- sTo document the physical structure, configuration, operational procedures, and security policies of the database.


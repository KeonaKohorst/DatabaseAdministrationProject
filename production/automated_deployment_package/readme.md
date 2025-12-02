# The dba_deployment.zip file contains the following:

/opt/dba_deployment/
    ├── sql/                   ←  V1.0.0, V1.0.1, V1.0.2... SQL/Configuration files
    ├── data/                  ←  Stock data CSV file for SQL*Loader (Only demo file with 10K rows, contact DBAs for full 29M row file)
    ├── log/                   ←  SQLLoader logs (stocks.log)
    ├── backup/                ←  Backup configuration scripts and files
    ├── performance/           ←  Performance configuration scripts and files
    ├── auditing/              ←  Auditing configuration scripts and files
    ├── flyway.conf/           ←  Flyway configuration file
    ├── cleanup.sh             ←  Clean up after failed deployment script
    ├── install_flyway.sh      ←  Install flyway CLI script
    └── deploy.sh              ← Master deployment script

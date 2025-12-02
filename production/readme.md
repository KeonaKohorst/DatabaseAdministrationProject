# Database Deployment Instructions

This guide provides step-by-step instructions on how to download the automated deployment package and execute the database deployment process using the provided scripts.

---

## Downloading and Extracting the Deployment Package

1.  Navigate to the primary installation directory:
    
    ```bash
    cd /opt
    ```

2.  Unzip the automated deployment package (`dba_deployment.zip`) obtained from the GitHub repository [6].
    
    > **Tip:** A script named **`download_deployment_package.sh`** is available in the `/development/flyway_scripts` directory of the GitHub repository. You can execute this script if you prefer not to manually download and extract the file.

---

## Preparation and Execution

### 1. Make the Deployment Script Executable

Ensure the main deployment script has execution permissions:

```bash
chmod +x /opt/dba_deployment/deploy.sh
```

### 2. (Optional) Updating to the Full Stock Data File

The downloaded package contains only a smaller demo CSV file for the `Stocks` table. If you require the **full version (29M rows)**, follow these steps:

* Request the full CSV file from one of the DBAs.
* Copy the full CSV file into the deployment package's data directory, naming it `stock_data_utf.csv`:
    
    ```bash
    cp /path/to/full/stock_data.csv /opt/dba_deployment/data/stock_data_utf.csv
    ```

* Edit the SQL\*Loader control file, `/opt/dba_deployment/data/stock.ctl`, to change the `INFILE` parameter to point to the new full file: `stock_data_utf.csv`.

### 3. Install Flyway CLI

Execute the installation script to set up the database migration tool:

* The script **`install_flyway.sh`** will install **Flyway CLI version 11.18.0** into the `/opt/flyway` directory and automatically add Flyway to your system's PATH.

### 4. Execute Deployment

Navigate to the deployment directory and run the master script:

```bash
cd /opt/dba_deployment
./deploy.sh
```

---

## Troubleshooting

If the deployment process fails, please refer to the section of this document (or a linked document) titled "Cleaning After Automated Deployment Failure"
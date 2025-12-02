# Correct raw URL for the ZIP file content
DOWNLOAD_URL="https://github.com/KeonaKohorst/DatabaseAdministrationProject/raw/refs/heads/main/production/automated_deployment_package/dba_deployment.zip"
TARGET_DIR="/opt"

# 1. Create the target directory if it doesn't exist
sudo mkdir -p "$TARGET_DIR" && \
# 2. Download the RAW ZIP file content directly into the target directory
sudo curl -L "$DOWNLOAD_URL" -o "$TARGET_DIR/dba_deployment.zip" && \
# 3. Unzip the contents into the target directory (this will extract folders/files)
sudo unzip -o "$TARGET_DIR/dba_deployment.zip" -d "$TARGET_DIR" && \
# 4. Clean up the downloaded ZIP file
sudo rm "$TARGET_DIR/dba_deployment.zip"
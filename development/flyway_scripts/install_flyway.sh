#!/bin/bash

# ==============================================================================
# install_flyway.sh 
# ------------------------------------------------------------------------------
# Installs the standalone Flyway CLI into /opt/flyway/flyway-X.Y.Z,
# creates a symlink to /opt/flyway, and configures the system PATH.
# MUST BE RUN AS ROOT or with sudo.
# ==============================================================================

# --- Configuration Variables ---
# Use the official, non-Desktop download link from the community edition page
# This URL points to the latest community version.
FLYWAY_DOWNLOAD_URL="https://download.red-gate.com/maven/release/com/redgate/flyway/flyway-commandline/11.18.0/flyway-commandline-11.18.0-linux-x64.tar.gz"
INSTALL_BASE_DIR="/opt"
FLYWAY_HOME_DIR="/opt/flyway" # This will be the symlink target
TEMP_DIR="/tmp/flyway_install"
PROFILE_D_FILE="/etc/profile.d/flyway.sh"

echo "--- 1. Starting Flyway CLI Installation from Official Maven Repo ---"
echo "Downloading from: ${FLYWAY_DOWNLOAD_URL}"

# --- 2. Check for Dependencies ---
if ! command -v curl &> /dev/null; then
    echo "ERROR: 'curl' is required but not installed. Please install it."
    exit 1
fi
if ! command -v tar &> /dev/null; then
    echo "ERROR: 'tar' is required but not installed."
    exit 1
fi

# --- 3. Download and Extract ---
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

echo "Downloading Flyway..."
curl -L "${FLYWAY_DOWNLOAD_URL}" -o "flyway.tar.gz"

if [ $? -ne 0 ]; then
    echo "FATAL ERROR: Download failed. Check URL and connectivity."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Extracting Flyway..."
tar -xzf flyway.tar.gz

# --- 4. Install to Target Directory ---
# The tarball extracts a single folder named flyway-X.Y.Z (e.g., flyway-10.15.2)
# We move this folder into /opt/ and then create a clean symlink /opt/flyway

EXTRACTED_DIR=$(find . -maxdepth 1 -type d ! -name . | head -n 1)

if [[ -z "$EXTRACTED_DIR" || "$EXTRACTED_DIR" == "." ]]; then
    echo "FATAL ERROR: Could not find the expected extracted flyway directory."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# The actual installation path will be /opt/flyway-X.Y.Z
ACTUAL_INSTALL_PATH="$INSTALL_BASE_DIR/$EXTRACTED_DIR"

echo "Installing to actual directory: $ACTUAL_INSTALL_PATH"

# Remove existing installation directory if it exists
if [ -d "$ACTUAL_INSTALL_PATH" ]; then
    echo "Warning: Existing installation found. Removing $ACTUAL_INSTALL_PATH..."
    rm -rf "$ACTUAL_INSTALL_PATH"
fi

# Move the extracted version folder to the /opt directory
mv "$EXTRACTED_DIR" "$INSTALL_BASE_DIR"/

# Clean up old symlink and create new one
if [ -L "$FLYWAY_HOME_DIR" ]; then
    echo "Removing old symlink: $FLYWAY_HOME_DIR"
    rm "$FLYWAY_HOME_DIR"
elif [ -d "$FLYWAY_HOME_DIR" ]; then
    echo "Warning: Directory $FLYWAY_HOME_DIR exists. Removing it."
    rm -rf "$FLYWAY_HOME_DIR"
fi

echo "Creating symlink $FLYWAY_HOME_DIR -> $ACTUAL_INSTALL_PATH"
ln -s "$ACTUAL_INSTALL_PATH" "$FLYWAY_HOME_DIR"


# --- 5. Clean Up ---
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

# --- 6. Configure PATH for Users ---
echo "Configuring PATH by creating $PROFILE_D_FILE..."

# Remove existing profile file to prevent duplicate entries
[ -f "$PROFILE_D_FILE" ] && rm "$PROFILE_D_FILE"

# The executable is located in $FLYWAY_HOME_DIR/bin
cat << EOF > "$PROFILE_D_FILE"
# Flyway CLI Path Configuration (Installed via Script)
export FLYWAY_HOME="$FLYWAY_HOME_DIR"
# The Flyway executable is in the bin subdirectory
export PATH="\$FLYWAY_HOME:\$PATH"
EOF

# Ensure the file is executable and readable by all users
chmod +x "$PROFILE_D_FILE"

echo "--- 7. Installation Complete ---"
echo "Flyway installed in: $ACTUAL_INSTALL_PATH"
echo "Symlink created at: $FLYWAY_HOME_DIR"
echo "PATH configuration saved to: $PROFILE_D_FILE"
echo ""
echo "**SUCCESS:** To use Flyway immediately, run: 'source $PROFILE_D_FILE' or start a new shell session."
echo "You should then be able to run: 'flyway -v'"
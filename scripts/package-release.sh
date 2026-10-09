#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
BUILD_DIR="${REPO_DIR}/build"
DIST_DIR="${REPO_DIR}/dist"
PKG_DIR="${DIST_DIR}/Rane-Sixty-Eight-macOS-Driver"

echo "========================================="
echo "   Packaging Rane Driver Release         "
echo "========================================="

# 1. Ensure clean build
cd "${REPO_DIR}"
./build.sh

# 2. Prepare dist directory
rm -rf "${DIST_DIR}"
mkdir -p "${PKG_DIR}"
mkdir -p "${PKG_DIR}/scripts"

# 3. Copy binaries and assets
cp -R "${BUILD_DIR}/Rane Sixty-Eight Control Panel.app" "${PKG_DIR}/"
cp -R "${BUILD_DIR}/RaneHAL.driver" "${PKG_DIR}/"
cp "${BUILD_DIR}/RaneMIDIAgent" "${PKG_DIR}/"
cp "${BUILD_DIR}/rane-selftest" "${PKG_DIR}/"
cp "${BUILD_DIR}/rane-stresstest" "${PKG_DIR}/"
cp "${REPO_DIR}/README.md" "${PKG_DIR}/"
cp "${REPO_DIR}/LICENSE" "${PKG_DIR}/"
cp "${REPO_DIR}/scripts/install.sh" "${PKG_DIR}/scripts/"
cp "${REPO_DIR}/scripts/uninstall.sh" "${PKG_DIR}/scripts/"
cp "${REPO_DIR}/src/midi-agent/org.openrane.sixtyeight.midi-agent.plist" "${PKG_DIR}/"

# 4. Create double-clickable Install.command
cat << 'EOF' > "${PKG_DIR}/Install.command"
#!/bin/bash
cd "$(dirname "$0")"
echo "=========================================================="
echo "   Installing Rane Sixty-Eight macOS Driver & Panel       "
echo "=========================================================="
echo ""
echo "Please enter your Mac administrator password to install:"
sudo ./scripts/install.sh
echo ""
echo "Installation complete! Opening Control Panel..."
open -a "/Applications/Rane Sixty-Eight Control Panel.app"
echo ""
read -p "Press [Enter] to close this window..."
EOF
chmod +x "${PKG_DIR}/Install.command"

# 5. Create double-clickable Uninstall.command
cat << 'EOF' > "${PKG_DIR}/Uninstall.command"
#!/bin/bash
cd "$(dirname "$0")"
echo "=========================================================="
echo "   Uninstalling Rane Sixty-Eight macOS Driver             "
echo "=========================================================="
echo ""
echo "Please enter your Mac administrator password to uninstall:"
sudo ./scripts/uninstall.sh
echo ""
read -p "Press [Enter] to close this window..."
EOF
chmod +x "${PKG_DIR}/Uninstall.command"

# 6. Create Zip archive
cd "${DIST_DIR}"
zip -r -q "Rane-Sixty-Eight-macOS-Driver.zip" "Rane-Sixty-Eight-macOS-Driver"

echo ""
echo "========================================="
echo "   Release Package Created Successfully! "
echo "========================================="
echo "Zip File: ${DIST_DIR}/Rane-Sixty-Eight-macOS-Driver.zip"
ls -lh "${DIST_DIR}/Rane-Sixty-Eight-macOS-Driver.zip"

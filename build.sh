#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${SCRIPT_DIR}/build"

echo "========================================="
echo "   Building Rane macOS User-Space Driver "
echo "========================================="

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" ..
make -j$(sysctl -n hw.ncpu)
echo -n "BNDL????" > RaneHAL.driver/Contents/PkgInfo

echo ""
echo "========================================="
echo "   Running Unit Tests                    "
echo "========================================="
ctest --output-on-failure

echo ""
echo "========================================="
echo "   Code Signing Products (Ad-Hoc / Univ) "
echo "========================================="
codesign --force --deep --sign - RaneHAL.driver
codesign --force --sign - RaneMIDIAgent
codesign --force --sign - rane-selftest
codesign --force --sign - rane-stresstest 2>/dev/null || true

echo ""
echo "========================================="
echo "   Building Swift Driver Manager App     "
echo "========================================="
mkdir -p "Rane Driver Manager.app/Contents/MacOS"
mkdir -p "Rane Driver Manager.app/Contents/Resources"
cp "${SCRIPT_DIR}/src/manager/Info.plist" "Rane Driver Manager.app/Contents/Info.plist"
cp "${SCRIPT_DIR}/src/manager/mixer_topdown.jpg" "Rane Driver Manager.app/Contents/Resources/" 2>/dev/null || true
cp "${SCRIPT_DIR}/src/manager/AppIcon.icns" "Rane Driver Manager.app/Contents/Resources/" 2>/dev/null || true
cp -R "${SCRIPT_DIR}/scripts" "Rane Driver Manager.app/Contents/Resources/" 2>/dev/null || true
cp "${SCRIPT_DIR}/src/midi-agent/org.openrane.sixtyeight.midi-agent.plist" "Rane Driver Manager.app/Contents/Resources/" 2>/dev/null || true
cp -R RaneHAL.driver RaneMIDIAgent rane-selftest rane-stresstest "Rane Driver Manager.app/Contents/Resources/" 2>/dev/null || true

# Compile Universal 2 Swift Binary from modular sources (x86_64 + arm64)
SWIFT_FILES=$(find "${SCRIPT_DIR}/src/manager" -name "*.swift" | sort)
swiftc -O -whole-module-optimization -target x86_64-apple-macos11.0 -import-objc-header "${SCRIPT_DIR}/src/manager/Link/RaneLinkBridge.h" -L"${SCRIPT_DIR}/lib" -labl_link -lc++ -framework Cocoa -framework IOKit -framework CoreMIDI -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework CoreAudioKit ${SWIFT_FILES} -o "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_x86"
swiftc -O -whole-module-optimization -target arm64-apple-macos11.0 -import-objc-header "${SCRIPT_DIR}/src/manager/Link/RaneLinkBridge.h" -L"${SCRIPT_DIR}/lib" -labl_link -lc++ -framework Cocoa -framework IOKit -framework CoreMIDI -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework CoreAudioKit ${SWIFT_FILES} -o "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_arm"
lipo -create -output "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager" \
     "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_x86" \
     "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_arm"
rm -f "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_x86" "Rane Driver Manager.app/Contents/MacOS/Rane Driver Manager_arm"

rm -rf "Rane Sixty-Eight Control Panel.app"
cp -R "Rane Driver Manager.app" "Rane Sixty-Eight Control Panel.app"
codesign --force --deep --sign - --entitlements "${SCRIPT_DIR}/src/manager/Entitlements.plist" "Rane Sixty-Eight Control Panel.app"
codesign --force --deep --sign - --entitlements "${SCRIPT_DIR}/src/manager/Entitlements.plist" "Rane Driver Manager.app"

echo ""
echo "========================================="
echo "   Build & Signing Completed Successfully!"
echo "========================================="
echo "Output Driver:   ${BUILD_DIR}/RaneHAL.driver (Universal 2)"
echo "Output Agent:    ${BUILD_DIR}/RaneMIDIAgent (Universal 2)"
echo "Selftest Tool:   ${BUILD_DIR}/rane-selftest (Universal 2)"
echo "Stresstest Tool: ${BUILD_DIR}/rane-stresstest (Universal 2)"
echo "GUI Manager:     ${BUILD_DIR}/Rane Driver Manager.app (Universal 2)"

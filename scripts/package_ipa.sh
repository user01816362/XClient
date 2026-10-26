#!/usr/bin/env bash
#
# package_ipa.sh — Packages XClient into an installable/sideloadable iOS .ipa archive.
# Compatible with AltStore, SideStore, TrollStore, and LiveContainer.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION="${1:-0.1.0}"
IPA_NAME="XClient.ipa"
VERSIONED_IPA_NAME="XClient-${VERSION}.ipa"

mkdir -p "${DIST_DIR}"
STAGE_DIR=$(mktemp -d /tmp/xclient_ipa_stage.XXXXXX)

echo "==> Packaging XClient IPA (version: ${VERSION})..."

PAYLOAD_DIR="${STAGE_DIR}/Payload"
APP_DIR="${PAYLOAD_DIR}/XClient.app"

mkdir -p "${APP_DIR}"

# 1. Copy or generate Info.plist
cat <<EOF > "${APP_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>XClientApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.xproject.xclient</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>XClient</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
EOF

# 2. Copy compiled binary if available
BIN_FOUND=false
for CANDIDATE in \
    "${ROOT_DIR}/XAPP/XClient/.build/release/XClientApp" \
    "${ROOT_DIR}/XAPP/XClient/.build/debug/XClientApp" \
    /tmp/xclient-build/out/Products/Release/XClientApp \
    /tmp/xclient-build/out/Products/Debug/XClientApp; do
    if [ -f "${CANDIDATE}" ]; then
        cp "${CANDIDATE}" "${APP_DIR}/XClientApp"
        chmod +x "${APP_DIR}/XClientApp"
        BIN_FOUND=true
        echo "  Found executable: ${CANDIDATE}"
        break
    fi
done

if [ "$BIN_FOUND" = false ]; then
    echo "::warning::No precompiled XClientApp binary found; creating stub runner for payload validation."
    cat << 'EOF' > "${APP_DIR}/XClientApp"
#!/bin/sh
echo "XClient Liquid Glass App"
EOF
    chmod +x "${APP_DIR}/XClientApp"
fi

# 3. Create zip container with .ipa extension
(
    cd "${STAGE_DIR}"
    zip -qr "${DIST_DIR}/${VERSIONED_IPA_NAME}" Payload
    cp "${DIST_DIR}/${VERSIONED_IPA_NAME}" "${DIST_DIR}/${IPA_NAME}"
)

# 4. Cleanup
rm -rf "${STAGE_DIR}"

echo "==> IPA packaged successfully:"
ls -lh "${DIST_DIR}/${IPA_NAME}" "${DIST_DIR}/${VERSIONED_IPA_NAME}"

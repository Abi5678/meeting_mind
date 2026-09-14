#!/usr/bin/env bash
# install-device.sh — Deploy InstantNotes build to a physical iPhone
# Prerequisites:
#   1. iPhone Developer Mode enabled (Settings → Privacy & Security)
#   2. Phone trusted on the Mac (System Settings → General → Sharing → Developer)
#   3. Run ./Scripts/build.sh --device first

set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_NAME="${1:-}"

if [[ -z "${DEVICE_NAME}" ]]; then
    # Auto-detect connected device
    DEVICE_ID=$(devicectl list devices --json 2>/dev/null | jq -r '.result[0].identifier')
    if [[ -z "${DEVICE_ID}" ]]; then
        echo "❌ No iOS device found. Connect and run: devicectl list devices"
        exit 1
    fi
else
    # Find device by name
    DEVICE_ID=$(devicectl list devices --json 2>/dev/null | jq -r --arg name "$DEVICE_NAME" '.result[] | select(.name == $name) | .identifier')
fi

if [[ -z "${DEVICE_ID}" ]]; then
    echo "❌ Device not found: ${DEVICE_NAME}"
    exit 1
fi

BUILD_DIR="$(pwd)/build/Products/Release-iphoneos"
IPA_PATH="${BUILD_DIR}/InstantNotes.ipa"

# Check if IPA exists, try to build it first
if [[ ! -f "${IPA_PATH}" ]]; then
    echo "🔨 Building IPA for device..."
    ./Scripts/build.sh --device
fi

echo "📦 Installing to ${DEVICE_NAME:-connected device}..."
devicectl install device "${DEVICE_ID}" local "${IPA_PATH}" 2>&1 || {
    echo "⚠️ devicectl install failed, trying with xcrun..."
    xcrun simctl launch "$(xcrun simctl list devices iPhone | head -1)" com.homezero1.instantnotes
    exit 1
}

echo "✅ Installed! Launch with: devicectl device ${DEVICE_ID} process list --json"

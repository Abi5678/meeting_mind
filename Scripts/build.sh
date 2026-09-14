#!/usr/bin/env bash
# build.sh — Build InstantNotes using XcodeGen + xcodebuild
# Usage:
#   ./Scripts/build.sh              # debug build (simulator)
#   ./Scripts/build.sh --device     # release build for device
#   ./Scripts/build.sh --scheme Debug  # specify scheme
#   ./Scripts/build.sh --config Release

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="Debug"
DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=latest"

while [[ $# -gt 0 ]]; do
    case $1 in
        --device) DESTINATION="generic/platform=iOS"; shift ;;
        --scheme) CONFIG="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        --*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) CONFIG="$1"; shift ;;
    esac
done

# Generate Xcode project from XcodeGen
if ! command -v xcodegen &>/dev/null; then
    echo "❌ xcodegen not found. Install: brew install xcodegen"
    exit 1
fi

echo "🔧 Generating project..."
xcodegen generate

# Build
BUILD_DIR="$(pwd)/build"
mkdir -p "$BUILD_DIR"

echo "🏗️ Building ${CONFIG} for ${DESTINATION}..."
xcodebuild build \
    -project "${BUILD_DIR}/InstantNotes.xcodeproj" \
    -scheme InstantNotes \
    -configuration "${CONFIG}" \
    -destination "${DESTINATION}" \
    -quiet \
    2>&1 | tee "${BUILD_DIR}/build.log"

if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    echo "✅ Build succeeded!"
else
    echo "❌ Build failed. See build.log"
    exit 1
fi

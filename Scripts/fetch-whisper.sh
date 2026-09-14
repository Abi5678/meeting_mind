#!/usr/bin/env bash
# fetch-whisper.sh — Download whisper.cpp xcframework for Instant Notes
# Run: ./Scripts/fetch-whisper.sh [--version 1.9.1]

set -euo pipefail

VERSION="${1:-1.9.1}"
WHISPER_DIR="Vendor/whisper.xcframework"

echo "Fetching whisper.cpp v${VERSION} xcframework..."

# Download all platform xcframeworks from GitHub releases
BASE_URL="https://github.com/ggerganov/whisper.cpp/releases/download/v${VERSION}"

mkdir -p "${WHISPER_DIR}"

for platform in ios-arm64 ios-arm64-simulator ios-x86_64-simulator macos-universal; do
    URL="${BASE_URL}/whisper.v${VERSION}.${platform}.xcframework.zip"
    echo "  → ${platform}"
    curl -fsSL -o "/tmp/whisper-${platform}.zip" "${URL}" || true
done

# TODO: Unzip and combine into the final xcframework
# For now this is a stub — will be filled in once we verify the correct release assets

echo "Done. Next steps:"
echo "  1. Verify downloaded frameworks match"
echo "  2. Add to InstantNotes target in project.yml"
echo "  3. Run swift test to confirm kit compiles with new dependency"

#!/bin/bash
#
#  fetch-whisper.sh
#  Recap
#
#  Created by Rio on 2026/8/19.
#
#  Downloads the official prebuilt whisper.cpp xcframework into Vendor/.
#  Run once after cloning. Set https_proxy first if GitHub is unreachable.

set -euo pipefail

VERSION="v1.9.2"
URL="https://github.com/ggml-org/whisper.cpp/releases/download/${VERSION}/whisper-${VERSION}-xcframework.zip"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/RecapKit/Vendor/whisper.xcframework"

if [ -d "$DEST" ]; then
    echo "Already present: $DEST"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading whisper.cpp ${VERSION} xcframework…"
curl -L --fail -o "$TMP/whisper.zip" "$URL"
unzip -q "$TMP/whisper.zip" -d "$TMP"

mkdir -p "${ROOT}/RecapKit/Vendor"
mv "$TMP/build-apple/whisper.xcframework" "$DEST"
echo "Installed → $DEST"

#!/bin/bash
#
#  build-whisper-macabi.sh
#  Recap
#
#  Created by Rio on 2026/8/19.
#
#  The official whisper.cpp xcframework ships no Mac Catalyst slice, so the
#  Catalyst app target cannot link it. This builds one from source and grafts
#  it into Vendor/whisper.xcframework.
#
#  Usage: build-whisper-macabi.sh <whisper.cpp source dir (v1.9.2 tag)>

set -euo pipefail

SRC="${1:?usage: build-whisper-macabi.sh <whisper.cpp source dir>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCFW="$ROOT/Vendor/whisper.xcframework"
TRIPLE="arm64-apple-ios17.0-macabi"
BUILD="$SRC/build-maccatalyst"
SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"

[ -d "$XCFW" ] || { echo "Run scripts/fetch-whisper.sh first."; exit 1; }

# Same GGML options as upstream build-xcframework.sh; CoreML off (unused).
cmake -B "$BUILD" -S "$SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT=macosx \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS="-target $TRIPLE" \
    -DCMAKE_CXX_FLAGS="-target $TRIPLE" \
    -DCMAKE_ASM_FLAGS="-target $TRIPLE" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target $TRIPLE" \
    -DCMAKE_EXE_LINKER_FLAGS="-target $TRIPLE" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_METAL_USE_BF16=ON \
    -DGGML_BLAS_DEFAULT=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Combining static libraries…"
find "$BUILD" -name '*.a' -print0 | xargs -0 libtool -static -o "$TMP/combined.a" 2>/dev/null

echo "Linking dynamic framework binary…"
xcrun -sdk macosx clang++ -dynamiclib \
    -target "$TRIPLE" \
    -isysroot "$SYSROOT" \
    -Wl,-force_load,"$TMP/combined.a" \
    -framework Foundation -framework Metal -framework Accelerate -lc++ \
    -install_name "@rpath/whisper.framework/whisper" \
    -o "$TMP/whisper"

echo "Assembling slice (macOS-style framework layout)…"
SLICE="$XCFW/ios-arm64-maccatalyst"
rm -rf "$SLICE"
mkdir -p "$SLICE"
ditto "$XCFW/macos-arm64_x86_64/whisper.framework" "$SLICE/whisper.framework"
cp "$TMP/whisper" "$SLICE/whisper.framework/Versions/A/whisper"

echo "Registering slice in xcframework manifest…"
/usr/bin/python3 - "$XCFW/Info.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    manifest = plistlib.load(f)
libs = manifest["AvailableLibraries"]
libs[:] = [l for l in libs if l.get("LibraryIdentifier") != "ios-arm64-maccatalyst"]
template = next(l for l in libs if l.get("LibraryIdentifier") == "macos-arm64_x86_64")
entry = dict(template)
entry.pop("DebugSymbolsPath", None)  # we ship no dSYM for this slice
entry.update({
    "LibraryIdentifier": "ios-arm64-maccatalyst",
    "SupportedArchitectures": ["arm64"],
    "SupportedPlatform": "ios",
    "SupportedPlatformVariant": "maccatalyst",
})
libs.append(entry)
with open(path, "wb") as f:
    plistlib.dump(manifest, f)
print("Manifest entries:", [l["LibraryIdentifier"] for l in libs])
PY

echo "Done → $SLICE"

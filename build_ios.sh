#!/bin/bash
set -euo pipefail

OUTPUT_DIR="output/ios"
LIBRARY_NAME="liboflux"

if ! command -v xcrun >/dev/null 2>&1; then
    echo "Xcode command line tools are required" >&2
    exit 1
fi

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
CLANGXX="$(xcrun --sdk iphoneos --find clang++)"
if [ ! -d "$SDK_PATH" ] || [ ! -x "$CLANG" ] || [ ! -x "$CLANGXX" ]; then
    echo "iPhoneOS SDK or compiler is unavailable" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
export GOARCH=arm64
export GOOS=ios
export CGO_ENABLED=1
export SDK_PATH
export CC="$CLANG -isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=15.0"
export CXX="$CLANGXX -isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=15.0"
export CGO_CFLAGS="-isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=15.0"
export CGO_LDFLAGS="-isysroot $SDK_PATH -arch arm64 -miphoneos-version-min=15.0"

echo "Building Go static library for iOS arm64..."
go build -buildmode=c-archive -ldflags="-w" -trimpath -o "$OUTPUT_DIR/$LIBRARY_NAME.a" .
echo "Build complete: $OUTPUT_DIR/$LIBRARY_NAME.a"
ls -lh "$OUTPUT_DIR/$LIBRARY_NAME.a"

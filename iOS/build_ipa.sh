#!/bin/bash
# Builds an unsigned IPA suitable for TrollStore.
# TrollStore re-signs the app itself, so no signing certificate is required.
#
# Usage (on macOS with Xcode installed):
#   ./build_ipa.sh
# Output: build/SomtodayMod.ipa

set -euo pipefail

cd "$(dirname "$0")"

BUILD_DIR="build"
APP_NAME="SomtodayMod"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Some Xcode versions return a nonzero exit code even after printing
# BUILD SUCCEEDED (e.g. for unsigned builds). We therefore judge success by
# whether the .app bundle was produced, not by the exit code.
XCODEBUILD_EXIT=0
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -target "$APP_NAME" \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    clean build || XCODEBUILD_EXIT=$?
echo "xcodebuild exit code: $XCODEBUILD_EXIT"
if [ "$XCODEBUILD_EXIT" -ne 0 ]; then
    echo "Warning: xcodebuild returned nonzero; continuing based on produced files" >&2
fi

echo "Build finished, locating $APP_NAME.app..."
# With CONFIGURATION_BUILD_DIR the .app lands in $BUILD_DIR itself; without
# it, Xcode puts it in $BUILD_DIR/Release-iphoneos. Support both.
APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH="$BUILD_DIR/Release-iphoneos/$APP_NAME.app"
fi
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_NAME.app was not produced by xcodebuild" >&2
    ls -la "$BUILD_DIR" >&2 || true
    exit 1
fi
echo "Found app bundle at $APP_PATH"

rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

cd "$BUILD_DIR"
rm -f SomtodayMod.ipa
zip -qry SomtodayMod.ipa Payload
cd ..

echo "Created $(pwd)/$BUILD_DIR/SomtodayMod.ipa:"
ls -la "$BUILD_DIR/SomtodayMod.ipa"

echo ""
echo "Done: $(pwd)/$BUILD_DIR/SomtodayMod.ipa"
echo "Open https://github.com/opa334/TrollStore and import the IPA,"
echo "or use the TrollStore URL scheme: apple-magnifier://install?url=<direct link to the IPA>"

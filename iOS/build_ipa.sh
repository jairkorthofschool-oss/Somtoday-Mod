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
    clean build

APP_PATH="$BUILD_DIR/Release-iphoneos/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH was not produced by xcodebuild" >&2
    exit 1
fi

rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

cd "$BUILD_DIR"
rm -f SomtodayMod.ipa
zip -qry SomtodayMod.ipa Payload
cd ..

echo ""
echo "Done: $(pwd)/$BUILD_DIR/SomtodayMod.ipa"
echo "Open https://github.com/opa334/TrollStore and import the IPA,"
echo "or use the TrollStore URL scheme: apple-magnifier://install?url=<direct link to the IPA>"

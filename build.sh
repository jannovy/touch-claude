#!/bin/sh
# Builds build/ClaudeUsageBar.app with the Command Line Tools only (no Xcode needed).
#   ./build.sh            build for this Mac
#   ./build.sh release    universal build (Apple silicon + Intel), zipped into build/release/
set -eu
cd "$(dirname "$0")"

APP=build/ClaudeUsageBar.app
BIN="$APP/Contents/MacOS/ClaudeUsageBar"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
mkdir -p "$APP/Contents/MacOS"

compile() { # arch, output
    swiftc -O -swift-version 5 -target "$1-apple-macos13.0" -framework AppKit -o "$2" Sources/*.swift
}

if [ "${1:-}" = release ]; then
    compile arm64 build/ClaudeUsageBar-arm64
    compile x86_64 build/ClaudeUsageBar-x86_64
    lipo -create -output "$BIN" build/ClaudeUsageBar-arm64 build/ClaudeUsageBar-x86_64
    rm build/ClaudeUsageBar-arm64 build/ClaudeUsageBar-x86_64
else
    compile "$(uname -m)" "$BIN"
fi

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = release ]; then
    ZIP="build/release/ClaudeUsageBar-$VERSION.zip"
    mkdir -p build/release
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "packed $ZIP"
    shasum -a 256 "$ZIP"
fi

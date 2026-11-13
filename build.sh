#!/bin/sh
# Builds build/ClaudeUsageBar.app with the Command Line Tools only (no Xcode needed).
#   ./build.sh            build for this Mac
#   ./build.sh release    also packs one zip per architecture into build/release/
set -eu
cd "$(dirname "$0")"

APP=build/ClaudeUsageBar.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

build() { # arch
    mkdir -p "$APP/Contents/MacOS"
    swiftc -O -swift-version 5 -target "$1-apple-macos13.0" -framework AppKit \
        -o "$APP/Contents/MacOS/ClaudeUsageBar" Sources/*.swift
    cp Info.plist "$APP/Contents/Info.plist"
    codesign --force --sign - "$APP"
}

pack() { # arch, name used in the zip file
    build "$1"
    zip="build/release/ClaudeUsageBar-$VERSION-$2.zip"
    mkdir -p build/release
    rm -f "$zip"
    ditto -c -k --keepParent "$APP" "$zip"
    shasum -a 256 "$zip"
}

if [ "${1:-}" = release ]; then
    pack arm64 apple-silicon
    pack x86_64 intel
fi

# Always finish with a build for this Mac, so build/ClaudeUsageBar.app is runnable here.
build "$(uname -m)"
echo "built $APP"

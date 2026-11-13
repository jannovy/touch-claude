#!/bin/sh
# Builds build/ClaudeUsageBar.app with the Command Line Tools only (no Xcode needed).
set -eu
cd "$(dirname "$0")"

APP=build/ClaudeUsageBar.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" -framework AppKit \
    -o "$APP/Contents/MacOS/ClaudeUsageBar" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built $APP"

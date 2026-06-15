#!/bin/bash
set -e

echo "=== Starting Build ==="

# Application name
APP_NAME="MissionControlExtend"
APP_BUNDLE="${APP_NAME}.app"

# Cleaning up previous builds
rm -rf "$APP_BUNDLE"
rm -f "$APP_NAME"
rm -rf "MissionControlPlus.app"
rm -f "MissionControlPlus"

# Fetching the macOS SDK path
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)

echo "Compiling Swift source files..."
swiftc -o "$APP_NAME" \
    AccessibilityEngine.swift \
    MissionControlDetector.swift \
    CloseButtonView.swift \
    OverlayWindowController.swift \
    AppDelegate.swift \
    main.swift \
    -sdk "$SDK_PATH" \
    -O

echo "Creating bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "Installing binary and Info.plist..."
mv "$APP_NAME" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

echo "Ad-hoc codesigning the application bundle..."
codesign -s - --force --deep "${APP_BUNDLE}"

echo "=== Build successful: ${APP_BUNDLE} is ready! ==="

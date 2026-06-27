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

# Get version from Git tag, fallback to 1.0.0
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | tr -d 'v' || echo "1.0.0")

# Get build number from Git commit count, fallback to 1
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

echo "Injecting version metadata (Version: $VERSION, Build: $BUILD_NUMBER)..."
plutil -replace CFBundleShortVersionString -string "$VERSION" "${APP_BUNDLE}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "${APP_BUNDLE}/Contents/Info.plist"

echo "Ad-hoc codesigning the application bundle..."
codesign -s - --force --deep "${APP_BUNDLE}"

echo "=== Build successful: ${APP_BUNDLE} is ready! ==="

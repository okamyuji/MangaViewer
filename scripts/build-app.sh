#!/bin/bash
set -e

# Configuration
APP_NAME="MangaViewer"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."

# Build release
swift build -c release

echo "📦 Creating app bundle..."

# Remove existing bundle if exists
if [ -d "${APP_BUNDLE}" ]; then
    rm -rf "${APP_BUNDLE}"
fi

# Create bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy ZIPFoundation bundle if exists
if [ -d "${BUILD_DIR}/ZIPFoundation_ZIPFoundation.bundle" ]; then
    cp -R "${BUILD_DIR}/ZIPFoundation_ZIPFoundation.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

# Copy app icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
    echo "📎 Added app icon"
fi

# Copy privacy manifest if exists
if [ -f "Resources/PrivacyInfo.xcprivacy" ]; then
    cp "Resources/PrivacyInfo.xcprivacy" "${APP_BUNDLE}/Contents/Resources/"
    echo "📎 Added privacy manifest"
fi

# Copy Info.plist from the shared source of truth (used by both Xcode and SwiftPM builds)
cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Clean up any CLAUDE.md files
find "${APP_BUNDLE}" -name "CLAUDE.md" -delete 2>/dev/null || true

echo "✅ Build complete: ${APP_BUNDLE}"
echo ""
echo "To run the app:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "To install to Applications:"
echo "  cp -R ${APP_BUNDLE} /Applications/"

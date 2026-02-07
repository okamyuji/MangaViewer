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

# Generate Info.plist using PlistBuddy to replace all Xcode build-setting placeholders
PLIST="${APP_BUNDLE}/Contents/Info.plist"
cp "Info.plist" "${PLIST}"
BUDDY=/usr/libexec/PlistBuddy
${BUDDY} -c "Set :CFBundleExecutable ${APP_NAME}" "${PLIST}"
${BUDDY} -c "Set :CFBundleIdentifier work.okamyuji.mangaviewer" "${PLIST}"
${BUDDY} -c "Set :CFBundleName ${APP_NAME}" "${PLIST}"
${BUDDY} -c "Set :LSMinimumSystemVersion 14.0" "${PLIST}"
# SwiftPM builds use .icns directly instead of Asset Catalog
${BUDDY} -c "Delete :CFBundleIconName" "${PLIST}" 2>/dev/null || true
${BUDDY} -c "Add :CFBundleIconFile string AppIcon" "${PLIST}" 2>/dev/null || true

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

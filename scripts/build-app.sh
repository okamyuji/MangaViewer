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

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MangaViewer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>work.okamyuji.mangaviewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MangaViewer</string>
    <key>CFBundleDisplayName</key>
    <string>Manga Viewer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.graphics-design</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 MangaViewer. All rights reserved.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Comic Book Archive (ZIP)</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>work.okamyuji.mangaviewer.cbz</string>
                <string>public.zip-archive</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Comic Book Archive (RAR)</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>work.okamyuji.mangaviewer.cbr</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>work.okamyuji.mangaviewer.cbz</string>
            <key>UTTypeDescription</key>
            <string>Comic Book Archive (ZIP)</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.zip-archive</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>cbz</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>work.okamyuji.mangaviewer.cbr</string>
            <key>UTTypeDescription</key>
            <string>Comic Book Archive (RAR)</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>cbr</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

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

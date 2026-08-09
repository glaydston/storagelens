#!/usr/bin/env bash
# Builds StorageLens.app from the SwiftPM executable.
#
# SwiftPM produces a bare Mach-O binary; macOS needs a bundle around it before
# it counts as an app (Dock icon, menu bar, TCC identity). This assembles that
# bundle and signs it ad-hoc so it launches locally.
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="StorageLens"
BUNDLE_ID="com.glaydston.StorageLens"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# AppInfo.swift is the single source of truth for version and author.
read_app_info() {
  sed -n "s/.*static let $1 = \"\(.*\)\"/\1/p" "$ROOT/Sources/StorageLens/AppInfo.swift"
}
VERSION="${VERSION:-$(read_app_info version)}"
AUTHOR="$(read_app_info author)"
COPYRIGHT="© 2026 $AUTHOR · MIT licensed"

BUILD_DIR="$ROOT/.build/$CONFIGURATION"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Localizations live as .lproj folders in Contents/Resources, so NSLocalizedString
# finds them through Bundle.main. Keys are the English source strings, so any
# locale without a table here falls back to en-US.
for lproj in "$ROOT"/Localizations/*.lproj; do
  [[ -d "$lproj" ]] && cp -R "$lproj" "$APP_DIR/Contents/Resources/"
done

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  ICON_ENTRY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
  ICON_ENTRY=''
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>CFBundleDevelopmentRegion</key><string>en_US</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>pt-BR</string><string>es-ES</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><true/>
  $ICON_ENTRY
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
# No sandbox entitlement: the app has to read ~/Library and the Trash. Users
# grant Full Disk Access themselves for the protected locations.
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "==> Built $APP_DIR ($APP_NAME $VERSION)"

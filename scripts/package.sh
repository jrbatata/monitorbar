#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox
binary_dir="$(swift build -c release --disable-sandbox --show-bin-path)"
mkdir -p dist
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
architecture="$(uname -m)"
dmg_path="$PWD/dist/MonitorBar-$version-$architecture-installer.dmg"
stage="$(mktemp -d "$PWD/.build/package.XXXXXX")"
app="$stage/MonitorBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/MonitorBar" "$app/Contents/MacOS/MonitorBar"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp README.md THIRD_PARTY_NOTICES.md Resources/LEIA-ME.txt "$app/Contents/Resources/"
swift scripts/make-icon.swift "$stage"
iconutil -c iconset "$stage/AppIcon.icns" -o "$stage/Decoded.iconset"
swift scripts/check-icon.swift "$stage/AppIcon.iconset" "$stage/Decoded.iconset"
cp "$stage/AppIcon.icns" "$app/Contents/Resources/AppIcon-v2.icns"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
if [ -d dist/MonitorBar.app ]; then
    mv dist/MonitorBar.app "$stage/Previous-MonitorBar.app"
fi
ditto "$app" dist/MonitorBar.app
codesign --verify --deep --strict dist/MonitorBar.app
mkdir -p "$stage/image"
ditto "$app" "$stage/image/MonitorBar.app"
ln -s /Applications "$stage/image/Applications"
volume_name="MonitorBar Installer"
swift scripts/style-dmg.swift "$stage/image" "$stage/AppIcon.icns" "$PWD/dist/installer-preview.png" "$volume_name"
xcrun SetFile -a E "$stage/image/MonitorBar.app"
# Build HFS without mounting a temporary device, then compress into a standard UDZO DMG.
hdiutil makehybrid -hfs -hfs-volume-name "$volume_name" -o "$stage/MonitorBar-hfs.dmg" "$stage/image"
# Bind the AliasRecord AFTER HFS has assigned its file IDs and creation dates.
python3 scripts/finalize-dmg.py "$stage/MonitorBar-hfs.dmg" "$stage/image/.DS_Store" "$stage/final.DS_Store"
hdiutil convert "$stage/MonitorBar-hfs.dmg" -format UDZO -ov -o "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path"
# Sparkle appcast: upload dist/appcast.xml AND the dmg to the GitHub release (feed = releases/latest/download/appcast.xml).
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
signature="$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$dmg_path")"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MonitorBar</title>
    <item>
      <title>Versão $version</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/jrbatata/monitorbar/releases/download/v$version/$(basename "$dmg_path")" type="application/x-apple-diskimage" $signature/>
    </item>
  </channel>
</rss>
XML
printf '\nApp: %s/dist/MonitorBar.app\nDMG: %s\n' "$PWD" "$dmg_path"

#!/bin/bash
# Builds Reel.app (Apple Silicon, macOS 15+) and zips it to build/Reel.zip.
#
# Signing: if SIGNING_CERT_P12 (base64 of a .p12) and SIGNING_CERT_PASSWORD are set, the app is
# signed with that personal certificate, so macOS remembers Reel's permissions across updates.
# Otherwise it is signed ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/Reel.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Reel" "$APP/Contents/MacOS/Reel"
strip -x "$APP/Contents/MacOS/Reel" 2>/dev/null || true

VERSION="1.8.3"
# The public repo counts runs from 1; the private one reached 91, so builds keep rising across the move.
BUILD_NUMBER="$(( ${GITHUB_RUN_NUMBER:-1} + 100 ))"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Reel</string>
  <key>CFBundleDisplayName</key><string>Reel</string>
  <key>CFBundleIdentifier</key><string>com.howbizzar.reel</string>
  <key>CFBundleExecutable</key><string>Reel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Reel keeps your library and notes in Documents › Reel.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Reel reads the file names on your film drive. It never changes the drive.</string>
  <key>NSAppleEventsUsageDescription</key><string>Reel asks VLC to play films full screen.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Reel reads the file names in your film folder. It never changes it.</string>
</dict>
</plist>
PLIST

IDENTITY="-"
if [ -n "${SIGNING_CERT_P12:-}" ]; then
  TMP="${RUNNER_TEMP:-$(mktemp -d)}"
  KEYCHAIN="$TMP/reel-signing.keychain-db"
  KEYCHAIN_PASS="$(uuidgen)"
  security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  security set-keychain-settings -lut 3600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
  echo "$SIGNING_CERT_P12" | base64 --decode > "$TMP/reel.p12"
  security import "$TMP/reel.p12" -k "$KEYCHAIN" -P "${SIGNING_CERT_PASSWORD:-}" -T /usr/bin/codesign >/dev/null
  rm -f "$TMP/reel.p12"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
  IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/\)/ {print $2; exit}')"
  if [ -z "$IDENTITY" ]; then
    echo "::error::No code signing identity found in SIGNING_CERT_P12"
    exit 1
  fi
  echo "::notice::Signed with the personal certificate"
else
  echo "::notice::Signed ad hoc (no SIGNING_CERT_P12 secret yet)"
fi

codesign --force --sign "$IDENTITY" --identifier com.howbizzar.reel "$APP"
codesign --verify --strict "$APP"

(cd build && ditto -c -k --keepParent Reel.app Reel.zip)
echo "Built build/Reel.zip ($(du -h build/Reel.zip | cut -f1))"

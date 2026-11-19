#!/bin/zsh
# Build DeskPad.app into build/ and install it to ~/Applications.
#   ./build.sh            build, sign, install
#   DESKPAD_SIGN=-        sign ad hoc instead of with the Apple Development certificate
# Signing with a real certificate keeps the app's identity stable across rebuilds, so any macOS permission
# granted to it survives a rebuild.
set -e
cd "${0:A:h}"
APP=build/DeskPad.app
SIGN=${DESKPAD_SIGN:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
SIGN=${SIGN:--}
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -import-objc-header DeskPad/DeskPad-Bridging-Header.h \
  DeskPad/*.swift -o $APP/Contents/MacOS/DeskPad \
  -framework AppKit -framework ScreenCaptureKit
cp DeskPad/Info.plist $APP/Contents/Info.plist
# App icon from upstream's 1024 px artwork.
ICONSET=build/AppIcon.iconset && rm -rf $ICONSET && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s DeskPad/Assets.xcassets/AppIcon.appiconset/Icon-1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) DeskPad/Assets.xcassets/AppIcon.appiconset/Icon-1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
codesign --force --sign "$SIGN" $APP
mkdir -p ~/Applications && rm -rf ~/Applications/DeskPad.app && cp -R $APP ~/Applications/DeskPad.app
echo "built and installed ~/Applications/DeskPad.app (signed: $SIGN)"

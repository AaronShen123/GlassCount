#!/bin/bash
# Regenerates Resources/Assets.xcassets/AppIcon.appiconset and Resources/AppIcon.icns from Tools/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=Resources/Assets.xcassets/AppIcon.appiconset
MASTER=$(mktemp -d)/master.png
swift Tools/make_icon.swift "$MASTER"
for s in 16 32 64 128 256 512 1024; do sips -z $s $s "$MASTER" --out "$SET/icon_$s.png" >/dev/null; done
cat > "$SET/Contents.json" <<'J'
{ "images": [
 {"idiom":"mac","size":"16x16","scale":"1x","filename":"icon_16.png"},
 {"idiom":"mac","size":"16x16","scale":"2x","filename":"icon_32.png"},
 {"idiom":"mac","size":"32x32","scale":"1x","filename":"icon_32.png"},
 {"idiom":"mac","size":"32x32","scale":"2x","filename":"icon_64.png"},
 {"idiom":"mac","size":"128x128","scale":"1x","filename":"icon_128.png"},
 {"idiom":"mac","size":"128x128","scale":"2x","filename":"icon_256.png"},
 {"idiom":"mac","size":"256x256","scale":"1x","filename":"icon_256.png"},
 {"idiom":"mac","size":"256x256","scale":"2x","filename":"icon_512.png"},
 {"idiom":"mac","size":"512x512","scale":"1x","filename":"icon_512.png"},
 {"idiom":"mac","size":"512x512","scale":"2x","filename":"icon_1024.png"} ],
 "info": {"version":1,"author":"xcode"} }
J
echo '{ "info": {"version":1,"author":"xcode"} }' > Resources/Assets.xcassets/Contents.json
# .icns for the script-built app (no Xcode asset compiler needed)
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Icon written."

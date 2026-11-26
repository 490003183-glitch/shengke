#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-lame.sh
swift build --build-system native -c release --product WaveStudio
APP="dist/声刻.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Replace the executable inode so an open previous build keeps its mapped code intact.
cp .build/release/WaveStudio "$APP/Contents/MacOS/.WaveStudio.new"
mv -f "$APP/Contents/MacOS/.WaveStudio.new" "$APP/Contents/MacOS/WaveStudio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources/ThirdParty/LAME"
cp ThirdParty/lame/install/lib/libmp3lame.0.dylib "$APP/Contents/Frameworks/.libmp3lame.new"
mv -f "$APP/Contents/Frameworks/.libmp3lame.new" "$APP/Contents/Frameworks/libmp3lame.0.dylib"
cp ThirdParty/lame/lame-3.100/COPYING ThirdParty/lame/README.md ThirdParty/lame/remove-obsolete-symbol.patch ThirdParty/lame/lame-3.100.tar.gz scripts/build-lame.sh "$APP/Contents/Resources/ThirdParty/LAME/"
codesign --force --sign - "$APP/Contents/Frameworks/libmp3lame.0.dylib"
codesign --force --sign - "$APP"
printf '已构建 %s\n' "$PWD/$APP"

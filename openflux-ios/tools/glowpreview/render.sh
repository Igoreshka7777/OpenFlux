#!/bin/bash
set -euo pipefail
cd tools/glowpreview
xcodegen generate
xcodebuild -project GlowPreview.xcodeproj -scheme GlowPreview -sdk iphonesimulator -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build > build.log 2>&1
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if x["name"].startswith("iPhone")))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" build/Build/Products/Debug-iphonesimulator/GlowPreview.app
xcrun simctl launch "$DEVICE" ru.openflux.glowpreview
sleep 3
xcrun simctl io "$DEVICE" screenshot glow-489.png

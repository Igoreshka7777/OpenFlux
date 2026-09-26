#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
app="$root/ios-app"
"$root/build_ios_wb.sh"
cd "$app"
xcodegen generate
xcodebuild -resolvePackageDependencies -project OpenFlux.xcodeproj -scheme OpenFlux
mkdir -p build
xcodebuild -project OpenFlux.xcodeproj -scheme OpenFlux -configuration Release -destination 'generic/platform=iOS' -archivePath build/OpenFlux.xcarchive -allowProvisioningUpdates clean archive
xcodebuild -exportArchive -archivePath build/OpenFlux.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
echo "IPA ready: $app/build/export/OpenFlux.ipa"

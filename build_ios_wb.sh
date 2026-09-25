#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runtime="$root/ios-wb-runtime"
output="$root/ios-app/Lib/OpenFluxWBRuntime.xcframework"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

(
  cd "$runtime"
  GOBIN="$temporary_dir" go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
  PATH="$temporary_dir:$PATH" CGO_ENABLED=1 "$temporary_dir/gomobile" bind \
    -target=ios,iossimulator -trimpath \
    -ldflags='-s -w -checklinkname=0' \
    -o "$temporary_dir/OpenFluxWBRuntime.xcframework" .
)

mkdir -p "$(dirname "$output")"
rm -rf "$output"
/usr/bin/ditto "$temporary_dir/OpenFluxWBRuntime.xcframework" "$output"
echo "Built $output"

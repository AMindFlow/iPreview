#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "Usage: $0 /absolute/path/iPreview-macos-arm64.zip" >&2
  exit 2
fi

output="$1"
cd "$(dirname "$0")/.."
mkdir -p "$(dirname "$output")" .build/package
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-modules}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
swift build --configuration release --arch arm64 --manifest-cache none
products="$(swift build --configuration release --arch arm64 --manifest-cache none --show-bin-path)"
staging="$(mktemp -d "$PWD/.build/package/iPreview.XXXXXX")"
application="$staging/iPreview.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
install -m 755 "$products/iPreview" "$application/Contents/MacOS/iPreview"
ditto "$products/iPreview_iPreviewCore.bundle" "$application/Contents/Resources/iPreview_iPreviewCore.bundle"
install -m 644 apps/macos/Info.plist "$application/Contents/Info.plist"
codesign --force --sign - "$application"
codesign --verify --strict "$application"
ditto -c -k --keepParent "$application" "$staging/iPreview-macos-arm64.zip"

# Check a fresh extraction outside the build tree while the SwiftPM resources still exist there.
smoke="$(mktemp -d "${TMPDIR:-/tmp}/ipreview-package-check.XXXXXX")"
ditto -x -k "$staging/iPreview-macos-arm64.zip" "$smoke"
extracted="$smoke/iPreview.app"
"$products/iPreviewCoreChecks" --check-packaged-migration "$extracted"
mv "$extracted/Contents/Resources" "$smoke/withheld-resources"
"$products/iPreviewCoreChecks" --check-missing-migration "$extracted"

mv "$staging/iPreview-macos-arm64.zip" "$output"

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
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
minimum_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' apps/macos/Info.plist)"
# The Swift driver can stamp the deployment target as the SDK version. AppKit uses
# the linked SDK in the executable to select the native window and control design.
build=(swift build --configuration release --arch arm64 --manifest-cache none
  -Xlinker -platform_version -Xlinker macos -Xlinker "$minimum_version" -Xlinker "$sdk_version")
"${build[@]}" --product iPreview
products="$("${build[@]}" --show-bin-path)"
staging="$(mktemp -d "$PWD/.build/package/iPreview.XXXXXX")"
application="$staging/iPreview.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
install -m 755 "$products/iPreview" "$application/Contents/MacOS/iPreview"
architecture="$(xcrun lipo -archs "$application/Contents/MacOS/iPreview")"
if [[ "$architecture" != arm64 ]]; then
  echo "Expected an arm64 application executable, received: $architecture" >&2
  exit 1
fi
linked_sdk="$(xcrun vtool -show-build "$application/Contents/MacOS/iPreview" | awk '$1 == "sdk" { print $2 }')"
if [[ "$linked_sdk" != "$sdk_version" && "$linked_sdk" != "$sdk_version.0" && "$linked_sdk.0" != "$sdk_version" ]]; then
  echo "Expected the executable to link against macOS SDK $sdk_version, received: $linked_sdk" >&2
  exit 1
fi
ditto "$products/iPreview_iPreviewCore.bundle" "$application/Contents/Resources/iPreview_iPreviewCore.bundle"
install -m 644 apps/macos/Info.plist "$application/Contents/Info.plist"
install -m 644 apps/macos/Assets/AppIcon.icns "$application/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$application"
codesign --verify --strict "$application"
ditto -c -k --keepParent "$application" "$staging/iPreview-macos-arm64.zip"

# Run a host-native checker against the archive without launching its arm64 executable.
check=(swift run --configuration release --manifest-cache none --scratch-path "$PWD/.build/package-checks" iPreviewCoreChecks)
smoke="$(mktemp -d "${TMPDIR:-/tmp}/ipreview-package-check.XXXXXX")"
ditto -x -k "$staging/iPreview-macos-arm64.zip" "$smoke"
extracted="$smoke/iPreview.app"
icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$extracted/Contents/Info.plist")"
if [[ ! -s "$extracted/Contents/Resources/$icon_file" ]]; then
  echo "macOS ZIP is missing the bundle icon: $icon_file" >&2
  exit 1
fi
"${check[@]}" --check-packaged-migration "$extracted"
mv "$extracted/Contents/Resources" "$smoke/withheld-resources"
"${check[@]}" --check-missing-migration "$extracted"

mv "$staging/iPreview-macos-arm64.zip" "$output"

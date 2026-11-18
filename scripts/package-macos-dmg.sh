#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 || "$1" != /* || "$2" != /* ]]; then
  echo "Usage: $0 /absolute/path/iPreview-macos-arm64.zip /absolute/path/iPreview-macos-arm64.dmg" >&2
  exit 2
fi

archive="$1"
output="$2"
cd "$(dirname "$0")/.."
mkdir -p .build/package "$(dirname "$output")"
staging="$(mktemp -d "$PWD/.build/package/dmg.XXXXXX")"
contents="$staging/contents"
mkdir "$contents"
ditto -x -k "$archive" "$contents"
application="$contents/iPreview.app"
codesign --verify --strict "$application"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Contents/Info.plist")"
ln -s /Applications "$contents/Applications"
cat > "$contents/安装说明.txt" <<'INSTRUCTIONS'
将 iPreview.app 拖入 Applications，然后从「应用程序」打开。
更新前退出 iPreview，以新应用替换旧应用。卸载时将应用移入废纸篓。
媒体原文件和本机资料库独立于应用，不随应用替换或卸载而删除。

此版本为 Apple Silicon macOS 15 及以上版本构建。
应用使用 ad hoc 签名，尚未取得 Developer ID 签名或 Apple 公证。
INSTRUCTIONS

hdiutil create -volname "iPreview $version" -srcfolder "$contents" -fs HFS+ -format UDZO "$output"
hdiutil verify "$output"
mountpoint="$staging/mounted"
mkdir "$mountpoint"
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$output"
trap 'hdiutil detach "$mountpoint"' EXIT
test "$(readlink "$mountpoint/Applications")" = /Applications
codesign --verify --strict "$mountpoint/iPreview.app"
diff -qr "$application" "$mountpoint/iPreview.app"
hdiutil detach "$mountpoint"
trap - EXIT
shasum -a 256 "$output"

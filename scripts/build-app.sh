#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$repo_root/.build/TabCount.app"
binary="$repo_root/.build/release/tabcount"
app_binary="$app/Contents/MacOS/TabCount"

cd "$repo_root"
swift build -c release >&2

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app_binary"
cp "$repo_root/Resources/TabCountInfo.plist" "$app/Contents/Info.plist"
if [[ -f "$repo_root/Resources/AppIcon.icns" ]]; then
  cp "$repo_root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - --identifier com.markmoriarty.tabcount "$app" >&2

echo "$app"

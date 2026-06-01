#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_app="${TABCOUNT_APP:-$HOME/Applications/TabCount.app}"

app="$("$repo_root/scripts/build-app.sh")"
pkill -f "$install_app/Contents/MacOS/TabCount" 2>/dev/null || true
rm -rf "$install_app"
mkdir -p "$(dirname "$install_app")"
cp -R "$app" "$install_app"

echo "App: $install_app"
echo "Open the app with:"
echo "open '$install_app'"

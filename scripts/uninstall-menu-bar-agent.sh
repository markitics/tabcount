#!/usr/bin/env bash
set -euo pipefail

install_app="${TABCOUNT_APP:-$HOME/Applications/TabCount.app}"

pkill -f "$install_app/Contents/MacOS/TabCount" 2>/dev/null || true
rm -rf "$install_app"

echo "Removed $install_app"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_app="${TABCOUNT_APP:-$HOME/Applications/TabCount.app}"
open_after_install=false
launch_hidden=false

for arg in "$@"; do
  case "$arg" in
    --open)
      open_after_install=true
      ;;
    --hidden)
      open_after_install=true
      launch_hidden=true
      ;;
    --no-open)
      open_after_install=false
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--open] [--hidden] [--no-open]" >&2
      exit 64
      ;;
  esac
done

app="$("$repo_root/scripts/build-app.sh")"
pkill -f "$install_app/Contents/MacOS/TabCount" 2>/dev/null || true
rm -rf "$install_app"
mkdir -p "$(dirname "$install_app")"
cp -R "$app" "$install_app"

echo "App: $install_app"
if [[ "$open_after_install" == true ]]; then
  if [[ "$launch_hidden" == true ]]; then
    open -gj "$install_app" --args --hidden
    echo "Opened hidden. TabCount will keep sampling every five minutes."
    echo "Open TabCount from Spotlight/Finder to show it in the menu bar again."
  else
    open "$install_app"
    echo "Opened TabCount."
  fi
else
  echo "Open the app with:"
  echo "open '$install_app'"
  echo "Or start it hidden with:"
  echo "open -gj '$install_app' --args --hidden"
fi

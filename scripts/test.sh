#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_binary="$(mktemp -t tabcount-history-store-test)"

cd "$repo_root"
swift build
swiftc Sources/TabCountCore/*.swift scripts/history-store-smoke-test.swift -o "$test_binary"
"$test_binary"
rm -f "$test_binary"

#!/usr/bin/env bash
# Headless end-to-end test: starts the stdlib Bitbucket mock (tests/mock_bitbucket.py),
# compiles Models + Services + tests/Harness.swift into a CLI (no Sparkle, no UI)
# and runs the approve / merge / veto / out-of-date / comment / CI flows against it.
# Uses an isolated EMERGER_SUPPORT_DIR and fake Keychain items it deletes on exit.
# Usage: scripts/e2e.sh [port]
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${1:-7990}"
WORK="$(mktemp -d)"
trap 'kill "${MOCK_PID:-}" 2>/dev/null || true; wait "${MOCK_PID:-}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Served under /bitbucket (503 at the host root) to mirror a corporate reverse proxy.
python3 -I tests/mock_bitbucket.py "$PORT" /bitbucket > "$WORK/mock.log" 2>&1 &
MOCK_PID=$!
sleep 1

echo "▶ Compiling harness…"
swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 -O \
  EMerger/Models/*.swift EMerger/Services/*.swift tests/Harness.swift \
  -framework UserNotifications -framework Security -o "$WORK/harness"

echo "▶ Running against http://localhost:$PORT/bitbucket …"
EMERGER_SUPPORT_DIR="$WORK/support" "$WORK/harness"

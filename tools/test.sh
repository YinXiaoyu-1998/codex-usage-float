#!/bin/zsh
set -euo pipefail

FOLLOW_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FOLLOW_TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/codex-follow-tests.XXXXXX")"
trap 'rm -rf "$FOLLOW_TEST_BUILD"' EXIT

# Compile the same controller and models used by the app, without its startup,
# system permission requests or real external-window observation.
swiftc \
  -framework Cocoa -framework ApplicationServices \
  "$FOLLOW_TEST_ROOT/UsageModels.swift" \
  "$FOLLOW_TEST_ROOT/FollowOverlayController.swift" \
  "$FOLLOW_TEST_ROOT/CodexWindowTracker.swift" \
  "$FOLLOW_TEST_ROOT/Tests/FollowOverlayBehaviorTests.swift" \
  -o "$FOLLOW_TEST_BUILD/FollowOverlayBehaviorTests"
"$FOLLOW_TEST_BUILD/FollowOverlayBehaviorTests"

#!/bin/zsh
# Checks that a shortcut saved by the previous build keeps its Category after upgrading.
#
# Phase A builds <previous-ref> in a temporary worktree, erases the simulator, and
# creates a shortcut "Add Expense" with Category = Food in the Shortcuts app.
# Phase B installs the current checkout over it and runs ShortcutUpgradeUITests.
#
# Usage: scripts/check-shortcut-upgrade.sh [previous-ref]   (default: main)
# Run before every release that changes QuickAddExpense's parameters. Exits 1 unless
# phase B passes.
#
# Expected RED for the stage 4 release (custom categories): changing the Category
# parameter from AppEnum to AppEntity drops the saved value, a clean break chosen on
# purpose while Kalyta is unreleased (docs/decisions.md). From then on the parameter
# type is frozen and this script is a real gate.
set -euo pipefail
REPO=${0:A:h:h}
REF=${1:-main}
DEVICE="iPhone 17"
WORK=$(mktemp -d)
trap 'git -C "$REPO" worktree remove --force "$WORK/old" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

run_tests() {  # <dir> <derived data> <test id> [env assignment]
    (cd "$1" && env ${4:-} perl -e 'alarm 600; exec @ARGV' xcodebuild test -scheme Kalyta \
        -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$2" -only-testing:"KalytaUITests/$3") \
        | grep -E "Test Case .*(passed|failed|skipped)|error:" || true
}

git -C "$REPO" worktree add -q "$WORK/old" "$REF"
cp "$REPO/Config/Local.xcconfig" "$WORK/old/Config/" 2>/dev/null || true
cp "$REPO/scripts/shortcut-upgrade/ShortcutSetupUITests.swift" "$WORK/old/KalytaUITests/"

xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
xcrun simctl erase "$DEVICE"
echo "== Phase A: $REF creates the shortcut =="
# Shortcuts indexes the app's actions only after its first launch, so the first try may fail.
run_tests "$WORK/old" "$WORK/dd-old" ShortcutSetupUITests
run_tests "$WORK/old" "$WORK/dd-old" ShortcutSetupUITests

echo "== Phase B: the current checkout is installed over it =="
RESULT=$(run_tests "$REPO" "$WORK/dd-new" ShortcutUpgradeUITests TEST_RUNNER_KALYTA_SHORTCUT_UPGRADE=1)
print -r -- "$RESULT"
if [[ "$RESULT" == *"KeepsCategory]' passed"* ]]; then
    echo "SHORTCUT UPGRADE OK"
else
    echo "SHORTCUT UPGRADE FAILED: the saved Category did not survive"
    exit 1
fi

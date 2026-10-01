#!/bin/zsh
# Regenerates the Shortcuts screenshots of Settings → Automatic Recording, in English and Ukrainian.
#
# For each language: erases the simulator, sets its system language (Shortcuts and the share
# sheet ignore the app's launch arguments), runs AutopayGuideUITests and copies the cropped
# JPEGs into Kalyta/Assets.xcassets/Autopay*.imageset/<name>-<language>.jpg.
#
# Usage: scripts/autopay-screenshots.sh [simulator name]   (default: "iPhone 17 Autopay")
# The simulator is erased, so never pass a shared one.
set -euo pipefail
REPO=${0:A:h:h}
DEVICE=${1:-"iPhone 17 Autopay"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for LANGUAGE LOCALE in en en_US uk uk_UA; do
    echo "== $LANGUAGE =="
    xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
    xcrun simctl erase "$DEVICE"
    xcrun simctl boot "$DEVICE"
    xcrun simctl spawn "$DEVICE" defaults write -g AppleLanguages -array "$LANGUAGE"
    xcrun simctl spawn "$DEVICE" defaults write -g AppleLocale "$LOCALE"
    xcrun simctl shutdown "$DEVICE"  # the language applies from the next boot
    # The first launch of Shortcuts on an erased simulator is slow enough to time out UI queries.
    xcrun simctl boot "$DEVICE"
    xcrun simctl launch "$DEVICE" com.apple.shortcuts >/dev/null
    sleep 30
    xcrun simctl terminate "$DEVICE" com.apple.shortcuts

    RESULT=$(cd "$REPO" && TEST_RUNNER_KALYTA_GUIDE_LANGUAGE=$LANGUAGE perl -e 'alarm 600; exec @ARGV' xcodebuild test \
        -scheme Kalyta -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$WORK/dd" \
        -resultBundlePath "$WORK/$LANGUAGE.xcresult" -only-testing:KalytaUITests/AutopayGuideUITests \
        | grep -E "Test Case .*(passed|failed|skipped)|error:" || true)
    print -r -- "$RESULT"
    [[ "$RESULT" == *"testCaptureGuideScreens]' passed"* ]] || { echo "AUTOPAY SCREENSHOTS FAILED ($LANGUAGE)"; exit 1; }

    xcrun xcresulttool export attachments --path "$WORK/$LANGUAGE.xcresult" --output-path "$WORK/$LANGUAGE"
    python3 - "$WORK/$LANGUAGE" "$REPO/Kalyta/Assets.xcassets" "$LANGUAGE" <<'EOF'
import json, shutil, sys
from pathlib import Path
source, assets, language = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"].removeprefix("autopay-").split(".")[0].split("_")[0]
        target = assets / f"Autopay{name.capitalize()}.imageset" / f"{name}-{language}.jpg"
        shutil.copyfile(source / attachment["exportedFileName"], target)
        print(f"{target.relative_to(assets.parent.parent)}  {target.stat().st_size // 1024} KB")
EOF
done
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true

#!/bin/zsh
# Regenerates the README screenshots in docs/images/screens/{en,uk}/, 600 px wide and under 250 KB.
#
# Erases the simulator once, then for each language sets its system language (the Home Screen widget
# ignores the app's launch arguments), cleans the status bar, runs ScreenshotUITests, which writes the
# PNGs itself, and shrinks them: sips to 600 px, then Pillow down to 256 colours (the widget's wallpaper
# is about 900 KB otherwise). English runs first: it adds the widget, whose gallery is searched in English.
#
# Needs Pillow: python3 -m pip install --user Pillow
# Usage: scripts/readme-screenshots.sh [simulator name]   (default: "iPhone 17 Pro Screens", made if missing)
# The simulator is erased, so never pass a shared one.
set -euo pipefail
REPO=${0:A:h:h}
DEVICE=${1:-"iPhone 17 Pro Screens"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

python3 -c "import PIL" 2>/dev/null || { echo "Pillow is missing: python3 -m pip install --user Pillow"; exit 1; }
xcrun simctl list devices | grep -q "    $DEVICE (" || xcrun simctl create "$DEVICE" "iPhone 17 Pro"

cd "$REPO"
perl -e 'alarm 900; exec @ARGV' xcodebuild build-for-testing -scheme Kalyta \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$WORK/dd" -quiet
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
xcrun simctl erase "$DEVICE"

for LANGUAGE LOCALE in en en_US uk uk_UA; do
    echo "== $LANGUAGE =="
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl bootstatus "$DEVICE" >/dev/null
    xcrun simctl spawn "$DEVICE" defaults write -g AppleLanguages -array "$LANGUAGE"
    xcrun simctl spawn "$DEVICE" defaults write -g AppleLocale "$LOCALE"
    # The widget gallery lists a newly installed app only after a reboot, which also applies the language.
    xcrun simctl install "$DEVICE" "$WORK/dd/Build/Products/Debug-iphonesimulator/Kalyta.app"
    xcrun simctl shutdown "$DEVICE"
    xcrun simctl boot "$DEVICE"
    xcrun simctl bootstatus "$DEVICE" >/dev/null
    xcrun simctl ui "$DEVICE" appearance light
    xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryLevel 100 --batteryState charged \
        --cellularBars 4 --wifiBars 3

    RESULT=$(TEST_RUNNER_KALYTA_SCREENSHOTS=1 perl -e 'alarm 900; exec @ARGV' xcodebuild test-without-building \
        -scheme Kalyta -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$WORK/dd" \
        -only-testing:KalytaUITests/ScreenshotUITests | grep -E "Test Case .*(passed|failed|skipped)|error:" || true)
    print -r -- "$RESULT"
    [[ "$RESULT" == *"testCaptureReadmeScreens]' passed"* ]] || { echo "README SCREENSHOTS FAILED ($LANGUAGE)"; exit 1; }
done
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true

sips --resampleWidth 600 docs/images/screens/*/*.png >/dev/null
python3 - docs/images/screens/*/*.png <<'EOF'
import os, sys
from PIL import Image
for path in sys.argv[1:]:
    Image.open(path).convert("RGB").quantize(256).save(path, optimize=True)
    size = os.path.getsize(path)
    print(f"{path}  {size // 1024} KB")
    if size >= 250 * 1024: sys.exit(f"{path} is over 250 KB")
EOF

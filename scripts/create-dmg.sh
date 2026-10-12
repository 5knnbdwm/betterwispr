#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! -d "$1/Contents" || "$2" != *.dmg ]]; then
    echo "Usage: bash scripts/create-dmg.sh BetterWispr.app output.dmg" >&2
    exit 1
fi
if ! diskutil image --help >/dev/null 2>&1; then
    echo "DMG packaging requires 'diskutil image' (macOS 27 or later)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$(cd "$1" && pwd)"
mkdir -p "$(dirname "$2")"
OUTPUT_DIR="$(cd "$(dirname "$2")" && pwd)"
OUTPUT_PATH="$OUTPUT_DIR/$(basename "$2")"
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.dmg-build.XXXXXX")"
DEVICE=""
cleanup() {
    [[ -z "$DEVICE" ]] || diskutil eject "$DEVICE" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

STAGING="$WORK_DIR/staging"
mkdir -p "$STAGING/.background"
ditto "$APP_PATH" "$STAGING/BetterWispr.app"
ln -s /Applications "$STAGING/Applications"
xcrun swift "$SCRIPT_DIR/dmg-background.swift" "$STAGING/.background/background.tiff"

diskutil image create from "$STAGING" "$WORK_DIR/rw.dmg" --format RAW --volumeName BetterWispr
attach_output="$(diskutil image attach --nobrowse "$WORK_DIR/rw.dmg")"
DEVICE="$(awk 'NR == 1 {print $1}' <<< "$attach_output")"
MOUNT_POINT="$(awk -F '\t' '$3 != "" {print $3; exit}' <<< "$attach_output")"
if [[ -z "$DEVICE" || ! -d "$MOUNT_POINT" ]]; then
    printf 'Could not find the mounted DMG volume:\n%s\n' "$attach_output" >&2
    exit 1
fi

layout_window() {
    osascript - "$MOUNT_POINT" <<'EOF'
on run argv
    tell application "Finder"
        tell disk (POSIX file (item 1 of argv) as alias)
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set bounds to {200, 140, 842, 546}
            end tell
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 128
            set text size of viewOptions to 13
            set background picture of viewOptions to file ".background:background.tiff"
            set extension hidden of item "BetterWispr.app" to true
            set position of item "BetterWispr.app" of container window to {164, 160}
            set position of item "Applications" of container window to {478, 160}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
EOF
}

for attempt in 1 2 3; do
    if layout_window 2> "$WORK_DIR/layout.log"; then
        break
    else
        status=$?
    fi
    cat "$WORK_DIR/layout.log" >&2
    if [[ $attempt -eq 3 ]] || ! grep -Fq -- '(-15260)' "$WORK_DIR/layout.log"; then
        exit "$status"
    fi
    echo "Finder is busy; retrying DMG layout ($attempt/3)..."
    sleep "$((attempt * 2))"
done

for _ in {1..10}; do
    [[ -f "$MOUNT_POINT/.DS_Store" ]] && break
    sleep 1
done
if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
    echo "Finder did not save the DMG window layout." >&2
    exit 1
fi

diskutil eject "$DEVICE"
DEVICE=""
diskutil image create from "$WORK_DIR/rw.dmg" "$WORK_DIR/BetterWispr.dmg" --format UDZO
hdiutil verify "$WORK_DIR/BetterWispr.dmg"
mv -f "$WORK_DIR/BetterWispr.dmg" "$OUTPUT_PATH"
echo "Created $OUTPUT_PATH"

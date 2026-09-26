#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_dir/build/testing"
derived_dir="$repo_dir/build/.derived-data-testing"
app_path="$build_dir/Word Snip Testing.app"
executable_path="$app_path/Contents/MacOS/Word Snip Testing"
bundle_id="com.aldrinnellas.wordsnip.testing"
signing_identity="CD4D712C8AA4110E3322ADAACA1DEAE098E4C902"

usage() {
    echo "Usage: scripts/test-app.sh {build|run|check|stop|path}" >&2
    exit 2
}

running_pids() {
    pgrep -f "^$executable_path$" || true
}

stop_app() {
    local pid
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        kill -TERM "$pid"
    done < <(running_pids)
    for _ in {1..50}; do
        [[ -z "$(running_pids)" ]] && return
        sleep 0.1
    done
    echo "Word Snip Testing did not quit; close it before rebuilding." >&2
    exit 1
}

check_app() {
    [[ -d "$app_path" ]] || { echo "Missing test app: $app_path" >&2; exit 1; }
    [[ -x "$executable_path" ]] || { echo "Missing test executable: $executable_path" >&2; exit 1; }
    local identifier name signature
    identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
    name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app_path/Contents/Info.plist")"
    signature="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
    [[ "$identifier" == "$bundle_id" ]] || { echo "Unexpected bundle identifier: $identifier" >&2; exit 1; }
    [[ "$name" == 'Word Snip Testing' ]] || { echo "Unexpected display name: $name" >&2; exit 1; }
    [[ "$signature" == *'Authority=Apple Development:'* ]] || { echo "Test app is not Apple Development signed." >&2; exit 1; }
    [[ "$signature" != *'Signature=adhoc'* ]] || { echo "Test app is ad hoc signed." >&2; exit 1; }
    codesign --verify --deep --strict "$app_path"
    echo "Verified: $app_path"
    echo "Bundle ID: $identifier"
}

build_app() {
    stop_app
    mkdir -p "$build_dir"
    xcodebuild \
        -project "$repo_dir/WordSnip.xcodeproj" \
        -scheme WordSnip \
        -configuration Debug \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$derived_dir" \
        "CONFIGURATION_BUILD_DIR=$build_dir" \
        'PRODUCT_NAME=Word Snip Testing' \
        "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" \
        "CODE_SIGN_IDENTITY=$signing_identity" \
        'CODE_SIGN_STYLE=Manual' \
        'ENABLE_DEBUG_DYLIB=NO' \
        build
    check_app
}

case "${1:-}" in
    build) build_app ;;
    run)
        build_app
        open "$app_path"
        for _ in {1..50}; do
            if [[ -n "$(running_pids)" ]]; then
                echo "Running: $app_path"
                exit 0
            fi
            sleep 0.1
        done
        echo "The test app did not start." >&2
        exit 1
        ;;
    check) check_app ;;
    stop) stop_app ;;
    path) echo "$app_path" ;;
    *) usage ;;
esac

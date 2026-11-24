#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="$repo_dir/build/translation-integration/Translation Integration.app"
mkdir -p "$app_path/Contents/MacOS"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.aldrinnellas.wordsnip.translation-integration</string>
<key>CFBundleExecutable</key><string>TranslationIntegration</string>
<key>CFBundleName</key><string>Translation Integration</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library "$repo_dir/WordSnip/TranslationOverlay.swift" "$repo_dir/WordSnip/TextCapture.swift" "$repo_dir/WordSnip/SelectionOverlay.swift" "$repo_dir/WordSnip/ShortcutManager.swift" "$repo_dir/WordSnip/SettingsView.swift" "$repo_dir/WordSnip/QRCodeBehavior.swift" "$repo_dir/tests/TranslationIntegration.swift" -o "$app_path/Contents/MacOS/TranslationIntegration"
codesign --force --sign "${WORD_SNIP_SIGNING_IDENTITY:-Apple Development}" "$app_path"
"$app_path/Contents/MacOS/TranslationIntegration"

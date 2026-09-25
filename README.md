# Word Snip

Because my girlfriend asked for it so that she could make flashcards...introducing Word Snip!

A native macOS menu bar app that copies text from a selected screen area using Apple Vision OCR.

## Build

Requires macOS 14 or newer, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project WordSnip.xcodeproj -scheme WordSnip -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

Before generating the project on another Mac, set `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` in `project.yml` to your own Apple Development signing identity and team. Open `WordSnip.xcodeproj` in Xcode to run or archive the app. Move a built app to `/Applications` before enabling **Launch at login**, so the login item points to a stable location. Consistent signing lets Screen Recording permission persist across builds. For distribution to another Mac, configure Developer ID signing and notarization.

## Use

1. Launch Word Snip. The settings window opens the first time.
2. Press **⌃⇧2** (or choose another shortcut in Settings).
3. Grant Screen Recording access when macOS asks. **Quit Word Snip completely, then reopen it** after granting access. macOS requires a restart before capture works.
4. Drag a rectangle around the text. Recognized text is copied to the clipboard. Press **Esc** to cancel.

The menu bar icon can be hidden in Settings. **⌃⌥,** always opens Settings, including when the icon is hidden.

If macOS keeps asking for permission despite the switch being on, confirm that you launched the copy in `/Applications`, quit it, and reopen that same copy. Older Xcode and `dist` builds may appear under the same name in System Settings. Remove stale Word Snip entries there and grant access to the installed copy.

# Word Snip development workflow

- Build and run the development app with `scripts/test-app.sh build` or `scripts/test-app.sh run`.
- The only active test bundle is `build/testing/Word Snip Testing.app`. Its bundle identifier is `com.aldrinnellas.wordsnip.testing`, separate from the release app's `com.aldrinnellas.wordsnip`.
- Keep the test app in that path across builds and sign it with the configured Apple Development identity. Screen Recording access is tied to this stable test identity and location.
- Do not build or run the release bundle, copy an app to `/Applications`, or prepare a distributable unless the user explicitly asks for release preparation. Do not reset Screen Recording permissions unless the user explicitly asks for that reset.
- Do not launch a temporary `.app` from DerivedData or `/private/tmp` for manual testing. Use the test script and its stable path.
- `scripts/test-app.sh check` verifies the test bundle's path, name, identifier, and signature. It does not verify OCR or Screen Recording access; test a capture interactively when needed.

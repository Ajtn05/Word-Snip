import AppKit

private enum AppLifetime {
    @MainActor static let delegate = AppDelegate()
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = AppLifetime.delegate
    application.run()
}

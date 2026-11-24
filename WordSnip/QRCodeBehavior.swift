import Foundation

/// What Word Snip does after copying a scanned QR payload that is an http/https URL with a host.
enum QRCodeBehavior: String, CaseIterable, Codable {
    /// Copy the payload to the clipboard only (default).
    case copyOnly
    /// Show the scanned link in an in-app preview window.
    case preview
    /// Immediately open the scanned link in the default browser.
    case openBrowser

    var title: String {
        switch self {
        case .copyOnly: "Copy only"
        case .preview: "Preview link"
        case .openBrowser: "Open in browser"
        }
    }

    var description: String {
        switch self {
        case .copyOnly: "Copy the scanned value and show the usual confirmation"
        case .preview: "Copy it, then show a window with the full selectable link"
        case .openBrowser: "Copy it, then open the link in your default browser"
        }
    }
}

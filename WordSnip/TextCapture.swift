import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

enum CaptureError: LocalizedError {
    case displayUnavailable
    case invalidSelection
    case noText

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected display is no longer available."
        case .invalidSelection: "The selected area could not be captured."
        case .noText: "No text was found in the selected area."
        }
    }
}

enum TextCapture {
    static func recognize(screen: NSScreen, selection: CGRect) async throws -> String {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw CaptureError.displayUnavailable
        }
        let displayID = screenNumber.uint32Value

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let screenshot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        let scaleX = CGFloat(screenshot.width) / screen.frame.width
        let scaleY = CGFloat(screenshot.height) / screen.frame.height
        let local = selection.intersection(screen.frame)
        let crop = CGRect(
            x: (local.minX - screen.frame.minX) * scaleX,
            y: (screen.frame.maxY - local.maxY) * scaleY,
            width: local.width * scaleX,
            height: local.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height))
        guard crop.width > 0, crop.height > 0, let image = screenshot.cropping(to: crop) else {
            throw CaptureError.invalidSelection
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CaptureError.noText }
        return text
    }
}

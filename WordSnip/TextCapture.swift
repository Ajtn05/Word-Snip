import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

enum CaptureError: LocalizedError {
    case displayUnavailable
    case invalidSelection
    case noText
    case clipboardUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected display is no longer available."
        case .invalidSelection: "The selected area could not be captured."
        case .noText: "No text was found in the selected area."
        case .clipboardUnavailable: "The recognized text could not be copied to the clipboard."
        }
    }
}

enum TextCapture {
    static func recognize(screen: NSScreen, selection: SelectionArea, singleLine: Bool) async throws -> String {
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
        let local = selection.bounds.intersection(screen.frame)
        let crop = CGRect(
            x: (local.minX - screen.frame.minX) * scaleX,
            y: (screen.frame.maxY - local.maxY) * scaleY,
            width: local.width * scaleX,
            height: local.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height))
        guard crop.width > 0, crop.height > 0, let croppedImage = screenshot.cropping(to: crop) else {
            throw CaptureError.invalidSelection
        }
        let image: CGImage
        switch selection {
        case .rectangle:
            image = croppedImage
        case .freehand(let points):
            guard let maskedImage = maskOutsideSelection(croppedImage, points: points, screen: screen,
                                                         crop: crop, scaleX: scaleX, scaleY: scaleY,
                                                         screenshotHeight: CGFloat(screenshot.height)) else {
                throw CaptureError.invalidSelection
            }
            image = maskedImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let recognized = lines.joined(separator: "\n")
        let text = singleLine
            ? recognized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            : recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CaptureError.noText }
        return text
    }

    private static func maskOutsideSelection(_ image: CGImage, points: [CGPoint], screen: NSScreen,
                                             crop: CGRect, scaleX: CGFloat, scaleY: CGFloat,
                                             screenshotHeight: CGFloat) -> CGImage? {
        guard points.count >= 3,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(imageBounds)

        // Screenshot crop coordinates start at the top; CGContext path coordinates start at the bottom.
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let pixel = CGPoint(x: (point.x - screen.frame.minX) * scaleX - crop.minX,
                                y: (point.y - screen.frame.minY) * scaleY - (screenshotHeight - crop.maxY))
            if index == 0 { path.move(to: pixel) }
            else { path.addLine(to: pixel) }
        }
        path.closeSubpath()
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.draw(image, in: imageBounds)
        return context.makeImage()
    }
}

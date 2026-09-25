import AppKit

let canvasSize: CGFloat = 1024
let outputDirectory = URL(fileURLWithPath: "WordSnip/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func drawIcon() {
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                  xRadius: 216, yRadius: 216)
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.11, green: 0.31, blue: 0.76, alpha: 1))!
        .draw(in: background, angle: -45)

    // A clear scan frame reads better than a document silhouette at Dock sizes.
    let corners: [[NSPoint]] = [
        [NSPoint(x: 400, y: 790), NSPoint(x: 225, y: 790), NSPoint(x: 225, y: 635)],
        [NSPoint(x: 625, y: 790), NSPoint(x: 800, y: 790), NSPoint(x: 800, y: 635)],
        [NSPoint(x: 800, y: 385), NSPoint(x: 800, y: 230), NSPoint(x: 625, y: 230)],
        [NSPoint(x: 400, y: 230), NSPoint(x: 225, y: 230), NSPoint(x: 225, y: 385)]
    ]
    NSColor.white.setStroke()
    for points in corners {
        let path = NSBezierPath()
        path.move(to: points[0])
        path.line(to: points[1])
        path.line(to: points[2])
        path.lineWidth = 48
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    NSColor.white.setFill()
    for (y, width) in [(620.0, 330.0), (500.0, 355.0), (380.0, 280.0)] {
        NSBezierPath(roundedRect: NSRect(x: 335, y: y, width: width, height: 48),
                     xRadius: 24, yRadius: 24).fill()
    }
}

func render(pixelSize: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    context.imageInterpolation = .high
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixelSize) / canvasSize
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputDirectory.appendingPathComponent(filename))
}

var images: [[String: String]] = []
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(pointSize)@\(scale)x.png"
        try render(pixelSize: pointSize * scale, filename: filename)
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(pointSize)x\(pointSize)"])
    }
}
let catalog: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let catalogData = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
try catalogData.write(to: outputDirectory.appendingPathComponent("Contents.json"))

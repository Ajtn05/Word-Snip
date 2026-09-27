import AppKit

let canvasSize: CGFloat = 1024
let outputDirectory = URL(fileURLWithPath: "WordSnip/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func drawIcon() {
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                  xRadius: 251, yRadius: 251)
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.11, green: 0.31, blue: 0.76, alpha: 1))!
        .draw(in: background, angle: -45)

    // Match the SF Symbol used in the Settings header: 31 points on a 50-point tile.
    let symbolSize = 31 * (896 / 50.0)
    let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else {
        fatalError("The text.viewfinder symbol is unavailable")
    }
    let size = symbol.size
    let rect = NSRect(x: (canvasSize - size.width) / 2,
                      y: (canvasSize - size.height) / 2,
                      width: size.width, height: size.height)
    symbol.draw(in: rect)
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

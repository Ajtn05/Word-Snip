import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.45, blue: 0.96, alpha: 1),
           ending: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.72, alpha: 1))!
    .draw(in: background, angle: -45)

let page = NSBezierPath(roundedRect: NSRect(x: 280, y: 224, width: 464, height: 576), xRadius: 44, yRadius: 44)
NSColor.white.withAlphaComponent(0.96).setFill()
page.fill()

let ink = NSColor(calibratedRed: 0.16, green: 0.32, blue: 0.72, alpha: 1)
ink.setFill()
for (y, width) in [(638.0, 270.0), (552.0, 310.0), (466.0, 260.0), (380.0, 290.0)] {
    NSBezierPath(roundedRect: NSRect(x: 355, y: y, width: width, height: 26), xRadius: 13, yRadius: 13).fill()
}

let corners: [[NSPoint]] = [
    [NSPoint(x: 224, y: 356), NSPoint(x: 224, y: 808), NSPoint(x: 386, y: 808)],
    [NSPoint(x: 638, y: 808), NSPoint(x: 800, y: 808), NSPoint(x: 800, y: 646)],
    [NSPoint(x: 800, y: 356), NSPoint(x: 800, y: 192), NSPoint(x: 638, y: 192)],
    [NSPoint(x: 386, y: 192), NSPoint(x: 224, y: 192), NSPoint(x: 224, y: 356)]
]
NSColor.white.setStroke()
for points in corners {
    let path = NSBezierPath()
    path.move(to: points[0])
    path.line(to: points[1])
    path.line(to: points[2])
    path.lineWidth = 30
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

image.unlockFocus()
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: "WordSnip/Assets.xcassets/AppIcon.appiconset/icon_1024.png"))

// Generates an original BreakTime app icon (rounded square + timer ring)
// into an .iconset directory. Usage: swift make_icon.swift <output.iconset>
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus(); return img
    }
    let s = size

    // rounded-rect background with a vertical gradient
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.96, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.72, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    ctx.restoreGState()

    // timer ring (three quarters, gap at top)
    let center = CGPoint(x: s/2, y: s/2)
    let ringRadius = s * 0.30
    let lineWidth = s * 0.075
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    let full = CGMutablePath()
    full.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.addPath(full); ctx.strokePath()

    let arc = CGMutablePath()
    arc.addArc(center: center, radius: ringRadius,
               startAngle: .pi / 2 + 0.5, endAngle: .pi / 2 - 0.5, clockwise: true)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.addPath(arc); ctx.strokePath()

    // pause bars (a break!)
    let barW = s * 0.055, barH = s * 0.16
    let gap = s * 0.045
    let bar1 = CGRect(x: center.x - gap/2 - barW, y: center.y - barH/2, width: barW, height: barH)
    let bar2 = CGRect(x: center.x + gap/2, y: center.y - barH/2, width: barW, height: barH)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(CGPath(roundedRect: bar1, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil))
    ctx.addPath(CGPath(roundedRect: bar2, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil))
    ctx.fillPath()

    img.unlockFocus()
    return img
}

func pngData(_ image: NSImage, size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    rep?.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep!)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep!.representation(using: .png, properties: [:])!
}

let master = drawIcon(size: 1024)
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes {
    let url = outDir.appendingPathComponent(name)
    try! pngData(master, size: px).write(to: url)
}
print("iconset written to \(outDir.path)")

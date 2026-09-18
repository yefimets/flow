import Cocoa

// Renders the ⌥ symbol on a macOS-style rounded tile into an .iconset, then iconutil makes the .icns.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()
    let s = CGFloat(px)
    let inset = s * 0.09  // macOS icons leave a margin inside the 1024 canvas
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.30, alpha: 1),
                                       NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 1)])!
    gradient.draw(in: path, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = max(1, s * 0.006)
    path.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "option", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor(calibratedRed: 0.48, green: 0.64, blue: 0.97, alpha: 1).set()
        let r = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: r)
        r.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let w = tinted.size.width, h = tinted.size.height
        tinted.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2 + s * 0.01, width: w, height: h))
    }
    image.unlockFocus()
    return image
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = render(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("iconset written")

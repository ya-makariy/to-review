// Renders the app icon: a Tahoe-style squircle with a blue→indigo gradient,
// a white git-merge glyph and a red "new review" dot.
// Usage: swift scripts/icon/render-icon.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // macOS icon grid: the squircle occupies ~82% of the canvas.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.95, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Gradient body
    squircle.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.62, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.33, green: 0.22, blue: 0.80, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -70)

    // Soft highlight at the top (glass feel)
    let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0), 0.0),
        (NSColor.white.withAlphaComponent(0), 0.45),
        (NSColor.white.withAlphaComponent(0.26), 1.0))!
    highlight.draw(in: rect, angle: 90)

    // Merge glyph: two branch nodes joining into one
    let s = rect.width
    let line = s * 0.075
    let nodeR = s * 0.085
    let cx = rect.midX, cy = rect.midY
    let leftX = cx - s * 0.17
    let topY = cy + s * 0.25
    let bottomY = cy - s * 0.25
    let rightX = cx + s * 0.17
    let rightY = cy + s * 0.12

    let path = NSBezierPath()
    path.lineWidth = line
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    // main trunk
    path.move(to: CGPoint(x: leftX, y: topY))
    path.line(to: CGPoint(x: leftX, y: bottomY))
    // branch curving in from the right node
    path.move(to: CGPoint(x: rightX, y: rightY))
    path.curve(to: CGPoint(x: leftX, y: bottomY + s * 0.02),
               controlPoint1: CGPoint(x: rightX, y: cy - s * 0.10),
               controlPoint2: CGPoint(x: leftX, y: cy - s * 0.02))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.setStroke()
    path.stroke()
    NSColor.white.setFill()
    for p in [CGPoint(x: leftX, y: topY), CGPoint(x: leftX, y: bottomY), CGPoint(x: rightX, y: rightY)] {
        NSBezierPath(ovalIn: CGRect(x: p.x - nodeR, y: p.y - nodeR, width: nodeR * 2, height: nodeR * 2)).fill()
    }
    ctx.restoreGState()

    // Notification dot
    let dotR = s * 0.075
    let dot = CGPoint(x: rect.maxX - s * 0.20, y: rect.maxY - s * 0.20)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.02, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2)).fill()
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.9).setStroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2))
    ring.lineWidth = s * 0.018
    ring.stroke()

    image.unlockFocus()
    return image
}

func save(_ image: NSImage, pixels: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    render(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
}

let master = render(size: 1024)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    save(master, pixels: pt * scale, name: "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png")
}
print("Icons written to \(outDir.path)")

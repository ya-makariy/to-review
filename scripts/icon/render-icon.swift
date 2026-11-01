// Renders the app icon: a Tahoe-style graphite squircle with a white "PR" monogram
// in SF Rounded and a bright red "new review" dot.
// Usage: swift scripts/icon/render-icon.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }

func circle(_ p: CGPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // macOS icon grid: the squircle occupies ~82% of the canvas.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let s = rect.width
    let cx = rect.midX, cy = rect.midY
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    rgb(0.16, 0.17, 0.20).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Graphite gradient + soft top highlight (glass feel)
    squircle.addClip()
    NSGradient(colors: [rgb(0.27, 0.29, 0.33), rgb(0.16, 0.17, 0.20), rgb(0.09, 0.10, 0.12)])!.draw(in: rect, angle: -70)
    NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0), 0.0),
        (NSColor.white.withAlphaComponent(0), 0.45),
        (NSColor.white.withAlphaComponent(0.18), 1.0))!.draw(in: rect, angle: 90)

    // "PR" monogram
    let base = NSFont.systemFont(ofSize: s * 0.46, weight: .heavy)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: s * 0.46) ?? base
    let text = NSAttributedString(string: "PR", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: -s * 0.02])
    let tsize = text.size()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    text.draw(at: CGPoint(x: cx - tsize.width / 2, y: cy - tsize.height / 2 - s * 0.01))
    ctx.restoreGState()

    // Notification dot — vivid red, white ring
    let dotR = s * 0.06
    let dot = CGPoint(x: cx + tsize.width / 2 + s * 0.02, y: cy + tsize.height * 0.30)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.02, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    rgb(1.0, 0.18, 0.16).setFill()
    circle(dot, dotR).fill()
    ctx.restoreGState()
    let ring = circle(dot, dotR)
    ring.lineWidth = s * 0.018
    NSColor.white.withAlphaComponent(0.95).setStroke()
    ring.stroke()

    image.unlockFocus()
    return image
}

func save(pixels: Int, name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    render(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    save(pixels: pt * scale, name: "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png")
}
print("Icons written to \(outDir.path)")

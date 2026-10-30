// Draws the Mac Island icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs iconutil, shipped with macOS)
import AppKit

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle-ish tile with the standard macOS icon inset.
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.24, blue: 0.36, alpha: 1),
                        NSColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1)])!
        .draw(in: tilePath, angle: -90)

    // The island: a black pill hanging from the top edge of the tile.
    let pillW = tile.width * 0.58
    let pillH = tile.height * 0.20
    let pill = NSRect(x: tile.midX - pillW / 2, y: tile.maxY - pillH - tile.height * 0.14,
                      width: pillW, height: pillH)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()

    // Status dot inside the pill, like the Claude status pill.
    let dot = pillH * 0.34
    NSColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.maxX - pillH * 0.75, y: pill.midY - dot / 2,
                                width: dot, height: dot)).fill()

    // An open panel under the pill: three tab dots and a terminal prompt.
    let panel = NSRect(x: tile.minX + tile.width * 0.14, y: tile.minY + tile.height * 0.14,
                       width: tile.width * 0.72, height: tile.height * 0.44)
    NSColor.black.withAlphaComponent(0.88).setFill()
    NSBezierPath(roundedRect: panel, xRadius: panel.height * 0.16, yRadius: panel.height * 0.16).fill()
    let prompt = NSBezierPath()
    let px = panel.minX + panel.width * 0.12, py = panel.midY
    prompt.move(to: NSPoint(x: px, y: py + panel.height * 0.14))
    prompt.line(to: NSPoint(x: px + panel.height * 0.16, y: py))
    prompt.line(to: NSPoint(x: px, y: py - panel.height * 0.14))
    prompt.lineWidth = max(2, s * 0.012)
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    NSColor(white: 0.92, alpha: 1).setStroke()
    prompt.stroke()
    NSColor(white: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: px + panel.height * 0.30, y: py - panel.height * 0.14,
                                     width: panel.width * 0.30, height: max(2, s * 0.012)),
                 xRadius: 2, yRadius: 2).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try draw(size: px).write(to: iconset.appendingPathComponent("\(name).png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try p.run()
p.waitUntilExit()
try? fm.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "wrote \(icns.path)" : "iconutil failed")
exit(p.terminationStatus)

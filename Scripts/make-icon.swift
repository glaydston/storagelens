#!/usr/bin/env swift
// Draws Resources/AppIcon.icns: a capacity ring over a rounded blue tile.
// Run with `make icon` — the .icns is committed, so this only needs rerunning
// when the artwork changes.
import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.06
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.96, alpha: 1),
        ending: NSColor(calibratedRed: 0.11, green: 0.27, blue: 0.72, alpha: 1)
    )?.draw(in: tilePath, angle: -90)

    // Capacity ring: a mostly-full gauge with the last quarter open.
    let ringWidth = size * 0.10
    let radius = size * 0.27
    let center = NSPoint(x: size / 2, y: size / 2)

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = ringWidth
    NSColor.white.withAlphaComponent(0.25).setStroke()
    track.stroke()

    let used = NSBezierPath()
    used.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -180, clockwise: true)
    used.lineWidth = ringWidth
    used.lineCapStyle = .round
    NSColor.white.setStroke()
    used.stroke()

    // Downward arrow in the middle: space going back down.
    let arrow = NSBezierPath()
    let armLength = size * 0.11
    arrow.move(to: NSPoint(x: center.x, y: center.y + armLength))
    arrow.line(to: NSPoint(x: center.x, y: center.y - armLength))
    arrow.move(to: NSPoint(x: center.x - armLength * 0.7, y: center.y - armLength * 0.3))
    arrow.line(to: NSPoint(x: center.x, y: center.y - armLength))
    arrow.line(to: NSPoint(x: center.x + armLength * 0.7, y: center.y - armLength * 0.3))
    arrow.lineWidth = size * 0.055
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor.white.setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for size in sizes {
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        let pixels = size * scale
        guard pixels <= 1024 else { continue }
        let rep = drawIcon(size: CGFloat(pixels))
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote Resources/AppIcon.icns")

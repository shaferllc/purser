#!/usr/bin/env swift
// Generates AppIcon.icns from a programmatic design.
// Usage: swift make-icon.swift  (run from the purser dir)

import AppKit
import Foundation

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: brass and deep water — the purser's counter.
    let radius = pf * 0.225
    let squircle = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
                                xRadius: radius, yRadius: radius)
    squircle.addClip()
    NSGradient(colors: [
        NSColor(red: 0.16, green: 0.42, blue: 0.62, alpha: 1),
        NSColor(red: 0.05, green: 0.16, blue: 0.32, alpha: 1),
    ])!.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    // The catalog: a 2×2 grid of app tiles, the goods on the shelf.
    let tile = pf * 0.20
    let gap = pf * 0.055
    let gridW = tile * 2 + gap
    let originX = (pf - gridW) / 2
    let originY = pf * 0.40

    let tints: [NSColor] = [
        NSColor(red: 0.98, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(red: 0.55, green: 0.85, blue: 0.92, alpha: 1),
        NSColor(red: 0.92, green: 0.55, blue: 0.55, alpha: 1),
        NSColor(white: 1, alpha: 0.92),
    ]

    for (index, tint) in tints.enumerated() {
        let column = CGFloat(index % 2)
        let row = CGFloat(index / 2)
        let rect = NSRect(x: originX + column * (tile + gap),
                          y: originY + (1 - row) * (tile + gap),
                          width: tile, height: tile)

        NSColor(white: 0, alpha: 0.22).setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -pf * 0.012),
                     xRadius: tile * 0.26, yRadius: tile * 0.26).fill()
        tint.setFill()
        NSBezierPath(roundedRect: rect, xRadius: tile * 0.26, yRadius: tile * 0.26).fill()
        NSColor(white: 1, alpha: 0.26).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + tile * 0.14, y: rect.midY,
                                         width: tile * 0.72, height: tile * 0.34),
                     xRadius: tile * 0.16, yRadius: tile * 0.16).fill()
    }

    // The install gesture: an arrow coming down onto a shelf.
    let shelfY = pf * 0.20
    let arrowX = pf * 0.5
    let arrowTop = originY - pf * 0.03
    let arrowBottom = shelfY + pf * 0.075

    NSColor(white: 1, alpha: 0.95).setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: arrowX, y: arrowTop))
    shaft.line(to: NSPoint(x: arrowX, y: arrowBottom))
    shaft.lineWidth = pf * 0.045
    shaft.lineCapStyle = .round
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowX - pf * 0.075, y: arrowBottom + pf * 0.065))
    head.line(to: NSPoint(x: arrowX, y: arrowBottom))
    head.line(to: NSPoint(x: arrowX + pf * 0.075, y: arrowBottom + pf * 0.065))
    head.lineWidth = pf * 0.045
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // The counter it lands on.
    let shelf = NSRect(x: pf * 0.20, y: shelfY - pf * 0.03, width: pf * 0.60, height: pf * 0.045)
    NSColor(white: 0, alpha: 0.25).setFill()
    NSBezierPath(roundedRect: shelf.offsetBy(dx: 0, dy: -pf * 0.012),
                 xRadius: shelf.height / 2, yRadius: shelf.height / 2).fill()
    NSColor(red: 0.98, green: 0.84, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: shelf, xRadius: shelf.height / 2, yRadius: shelf.height / 2).fill()

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")

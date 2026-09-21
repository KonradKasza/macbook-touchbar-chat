#!/usr/bin/env swift
import AppKit
import Foundation

/// Renders a generic, non-branded chat mark into an .iconset / .icns for the app bundle.
/// Neutral slate tile + simple speech bubble — no product logo / wordmark.

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: generate-app-icon.swift <output.icns>\n", stderr)
    exit(1)
}

let outICNS = URL(fileURLWithPath: args[1])
let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("TouchBarChatIcon-\(UUID().uuidString).iconset", isDirectory: true)

try? FileManager.default.removeItem(at: tmp)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocusFlipped(false)

    let scale = size / 1024.0
    func p(_ v: CGFloat) -> CGFloat { v * scale }

    // Soft rounded tile (generic utility look).
    let tile = NSBezierPath(
        roundedRect: NSRect(x: p(64), y: p(64), width: p(896), height: p(896)),
        xRadius: p(200),
        yRadius: p(200)
    )
    NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.23, alpha: 1).setFill()
    tile.fill()

    // Subtle inner highlight edge.
    let inset = NSBezierPath(
        roundedRect: NSRect(x: p(88), y: p(88), width: p(848), height: p(848)),
        xRadius: p(180),
        yRadius: p(180)
    )
    NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
    inset.lineWidth = max(p(8), 1)
    inset.stroke()

    // Speech bubble — plain geometric mark.
    let bubble = NSBezierPath()
    let body = NSRect(x: p(250), y: p(340), width: p(524), height: p(360))
    bubble.appendRoundedRect(body, xRadius: p(90), yRadius: p(90))
    // Tail
    bubble.move(to: NSPoint(x: p(340), y: p(340)))
    bubble.curve(
        to: NSPoint(x: p(280), y: p(220)),
        controlPoint1: NSPoint(x: p(320), y: p(300)),
        controlPoint2: NSPoint(x: p(290), y: p(250))
    )
    bubble.curve(
        to: NSPoint(x: p(420), y: p(340)),
        controlPoint1: NSPoint(x: p(320), y: p(250)),
        controlPoint2: NSPoint(x: p(380), y: p(320))
    )
    bubble.close()

    NSColor(calibratedRed: 0.42, green: 0.78, blue: 0.84, alpha: 1).setFill()
    bubble.fill()

    // Three soft dots inside the bubble.
    NSColor(calibratedRed: 0.14, green: 0.22, blue: 0.26, alpha: 0.85).setFill()
    for i in 0..<3 {
        let cx = p(380) + CGFloat(i) * p(110)
        let cy = p(500)
        NSBezierPath(ovalIn: NSRect(x: cx - p(28), y: cy - p(28), width: p(56), height: p(56))).fill()
    }

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let master = drawIcon(size: 1024)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("diana.k@example.org", 32),
    ("icon_32x32.png", 32),
    ("ivan.p@example.net", 64),
    ("icon_128x128.png", 128),
    ("wendy.h@example.net", 256),
    ("icon_256x256.png", 256),
    ("frank.g@example.org", 512),
    ("icon_512x512.png", 512),
    ("alice.j@example.com", 1024)
]

for (name, px) in entries {
    guard let data = pngData(from: master, pixelSize: px) else {
        fputs("failed to render \(name)\n", stderr)
        exit(1)
    }
    try data.write(to: tmp.appendingPathComponent(name))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", tmp.path, "-o", outICNS.path]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)

guard proc.terminationStatus == 0, FileManager.default.fileExists(atPath: outICNS.path) else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

print("Wrote \(outICNS.path)")

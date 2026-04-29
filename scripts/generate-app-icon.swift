#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset", isDirectory: true)
let pngOutput = root.appendingPathComponent("AppIcon.png")
let icnsOutput = root.appendingPathComponent("AppIcon.icns")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func iconShape(scale: CGFloat, inset: CGFloat = 74, radius: CGFloat = 214) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(
            x: inset * scale,
            y: inset * scale,
            width: (1024 - inset * 2) * scale,
            height: (1024 - inset * 2) * scale
        ),
        xRadius: radius * scale,
        yRadius: radius * scale
    )
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate icon bitmap")
    }

    let canvasSize = CGFloat(size)
    bitmap.size = NSSize(width: canvasSize, height: canvasSize)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create icon graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let scale = canvasSize / 1024
    func p(_ value: CGFloat) -> CGFloat { value * scale }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
    NSGraphicsContext.current?.shouldAntialias = true
    NSGraphicsContext.current?.imageInterpolation = .high

    let shape = iconShape(scale: scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = p(42)
    shadow.shadowOffset = NSSize(width: 0, height: -p(16))
    shadow.set()
    NSGradient(starting: color(0x1a2450), ending: color(0x060915))?.draw(in: shape, angle: -38)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    color(0xb7b2ff, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: p(86), y: p(692), width: p(520), height: p(280))).fill()
    NSGraphicsContext.restoreGraphicsState()

    let rim = iconShape(scale: scale, inset: 88, radius: 196)
    color(0x8d96c8, alpha: 0.22).setStroke()
    rim.lineWidth = p(4)
    rim.stroke()

    let heights: [CGFloat] = [122, 246, 392, 286, 184, 352, 250]
    let widths: [CGFloat] = [36, 38, 42, 38, 36, 42, 36]
    let colors = [color(0x5ff5d5), color(0x25bfff), color(0xffb95f)]
    let spacing: CGFloat = 42
    let totalWidth = widths.reduce(0, +) + spacing * CGFloat(widths.count - 1)
    var x = 512 - totalWidth / 2

    for index in heights.indices {
        let width = widths[index]
        let height = heights[index]
        roundedRect(
            NSRect(x: p(x), y: p(512 - height / 2), width: p(width), height: p(height)),
            radius: p(min(width / 2, 18)),
            fill: colors[index % colors.count]
        )
        x += width + spacing
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return bitmap
}

func savePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }
    try png.write(to: url)
}

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

try savePNG(drawIcon(size: 1024), to: pngOutput)

let iconFiles: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in iconFiles {
    try savePNG(drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

try? fileManager.removeItem(at: icnsOutput)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icnsOutput.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "GenerateAppIcon", code: Int(process.terminationStatus))
}

print("Generated AppIcon.png and AppIcon.icns")

#!/usr/bin/env swift
// Generates AppIcon.icns from the SF Symbol "timer"
// Usage: swift scripts/generate-icon.swift <output-path>

import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

let iconDir = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconDir)
try FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)

for size in sizes {
    guard let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil) else {
        fputs("Failed to load SF Symbol 'timer'\n", stderr)
        exit(1)
    }

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.7, weight: .medium)
    let configured = symbol.withSymbolConfiguration(config)!

    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Draw rounded rect background
    let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background: dark warm brown
    let gradient = NSGradient(starting: NSColor(red: 0.15, green: 0.08, blue: 0.05, alpha: 1.0),
                              ending: NSColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1.0))!
    gradient.draw(in: path, angle: -90)

    // Draw the symbol centered in orange
    let symbolSize = configured.size
    let x = (CGFloat(size) - symbolSize.width) / 2
    let y = (CGFloat(size) - symbolSize.height) / 2
    let drawRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)

    // Tint the symbol orange
    let tinted = NSImage(size: symbolSize)
    tinted.lockFocus()
    NSColor(red: 0.91, green: 0.45, blue: 0.29, alpha: 1.0).set() // #E8734A
    drawRect.offsetBy(dx: -x, dy: -y).fill(using: .sourceOver)
    configured.draw(in: NSRect(origin: .zero, size: symbolSize),
                    from: .zero, operation: .destinationIn, fraction: 1.0)
    tinted.unlockFocus()

    tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    image.unlockFocus()

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render icon at size \(size)\n", stderr)
        exit(1)
    }

    let filename: String
    if size == 1024 {
        filename = "icon_512x512@2x.png"
    } else if size >= 32 {
        // Write both 1x and 2x variants
        let halfSize = size / 2
        try pngData.write(to: URL(fileURLWithPath: "\(iconDir)/icon_\(halfSize)x\(halfSize)@2x.png"))
        // Also write 1x at this size
        filename = "icon_\(size)x\(size).png"
    } else {
        filename = "icon_\(size)x\(size).png"
    }
    try pngData.write(to: URL(fileURLWithPath: "\(iconDir)/\(filename)"))
}

// Convert iconset to icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconDir, "-o", outputPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Generated \(outputPath)")
} else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(atPath: iconDir)

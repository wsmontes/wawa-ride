#!/usr/bin/env swift
import AppKit

// Generate a 1024x1024 @1x app icon with motorcycle SF Symbol on orange background
let size = 1024.0
let rect = CGRect(x: 0, y: 0, width: size, height: size)

guard let symbol = NSImage(systemSymbolName: "motorcycle",
                           accessibilityDescription: "Motorcycle") else {
    print("❌ Could not load motorcycle SF Symbol")
    exit(1)
}

// Create bitmap context at exactly 1024x1024 pixels (1x)
guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ Could not create CGContext")
    exit(1)
}

// Draw background
context.setFillColor(CGColor(red: 0.96, green: 0.42, blue: 0.08, alpha: 1.0))
let cornerRadius = size * 0.225
let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
context.addPath(bgPath)
context.fillPath()

// Convert CGContext to NSGraphicsContext for NSImage drawing
let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

// Draw SF Symbol centered
let symbolSize: CGFloat = size * 0.50
let symbolRect = CGRect(
    x: (size - symbolSize) / 2,
    y: (size - symbolSize) / 2,
    width: symbolSize,
    height: symbolSize
)

let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
configuredSymbol.draw(in: symbolRect)

NSGraphicsContext.current = nil

// Extract CGImage and save as PNG
guard let cgImage = context.makeImage() else {
    print("❌ Could not create image from context")
    exit(1)
}

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("❌ Could not create PNG data")
    exit(1)
}

let outputPath = "Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
print("✅ App icon generated at \(outputPath) (\(pngData.count) bytes, \(cgImage.width)x\(cgImage.height))")

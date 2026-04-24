#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let inputURL = rootURL.appendingPathComponent("Icon-1024.png")
let outputURL = rootURL.appendingPathComponent("Icon.icns")

let sizes = [16, 32, 64, 128, 256, 512, 1024]

guard let source = NSImage(contentsOf: inputURL) else {
    fputs("Unable to load \(inputURL.path)\n", stderr)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    "com.apple.icns" as CFString,
    sizes.count,
    nil
) else {
    fputs("Unable to create icns destination\n", stderr)
    exit(1)
}

for size in sizes {
    guard let image = rasterizedImage(from: source, pixels: size) else {
        fputs("Unable to rasterize \(size)x\(size)\n", stderr)
        exit(1)
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPixelWidth: size,
        kCGImagePropertyPixelHeight: size,
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to finalize icns file\n", stderr)
    exit(1)
}

func rasterizedImage(from source: NSImage, pixels: Int) -> CGImage? {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage
}

#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = rootURL.appendingPathComponent("Icon.iconset", isDirectory: true)
let masterURL = rootURL.appendingPathComponent("Icon-1024.png")

let specs: [(filename: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for spec in specs {
    let image = makeIcon(size: CGFloat(spec.size))
    let destination = iconsetURL.appendingPathComponent(spec.filename)
    try savePNG(image: image, to: destination)
}

try savePNG(image: makeIcon(size: 1024), to: masterURL)

func makeIcon(size: CGFloat) -> NSImage {
    let pixels = Int(size.rounded())
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
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    drawBackground(in: rect)
    drawDisplayCluster(in: rect)
    drawHighlight(in: rect)

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

func drawBackground(in rect: NSRect) {
    let cornerRadius = rect.width * 0.225
    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.24, alpha: 1).setFill()
    backgroundPath.fill()

    let gradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.78, alpha: 1), 0.0),
        (NSColor(calibratedRed: 0.00, green: 0.73, blue: 0.84, alpha: 1), 0.52),
        (NSColor(calibratedRed: 0.03, green: 0.10, blue: 0.24, alpha: 1), 1.0)
    )!
    gradient.draw(in: backgroundPath, angle: -52)

    let glowRect = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
    let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: cornerRadius * 0.8, yRadius: cornerRadius * 0.8)
    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    glowPath.lineWidth = rect.width * 0.012
    glowPath.stroke()
}

func drawDisplayCluster(in rect: NSRect) {
    let scale = rect.width

    let left = NSRect(x: scale * 0.14, y: scale * 0.37, width: scale * 0.28, height: scale * 0.22)
    let center = NSRect(x: scale * 0.31, y: scale * 0.48, width: scale * 0.38, height: scale * 0.28)
    let right = NSRect(x: scale * 0.61, y: scale * 0.31, width: scale * 0.22, height: scale * 0.18)

    drawConnectorPath(in: rect, left: left, center: center, right: right)
    drawDisplay(left, corner: scale * 0.04, tint: NSColor(calibratedRed: 0.57, green: 0.79, blue: 1.00, alpha: 1), isPrimary: false)
    drawDisplay(center, corner: scale * 0.05, tint: NSColor(calibratedRed: 0.89, green: 0.97, blue: 1.00, alpha: 1), isPrimary: true)
    drawDisplay(right, corner: scale * 0.035, tint: NSColor(calibratedRed: 0.49, green: 0.95, blue: 0.96, alpha: 1), isPrimary: false)
}

func drawConnectorPath(in rect: NSRect, left: NSRect, center: NSRect, right: NSRect) {
    let stroke = rect.width * 0.026
    let connector = NSBezierPath()
    connector.lineCapStyle = .round
    connector.lineJoinStyle = .round
    connector.lineWidth = stroke

    connector.move(to: NSPoint(x: left.maxX - stroke * 0.5, y: left.midY + stroke * 0.3))
    connector.line(to: NSPoint(x: center.minX + stroke * 0.35, y: center.minY + stroke * 1.1))
    connector.line(to: NSPoint(x: right.minX + stroke * 0.2, y: right.midY + stroke * 0.2))

    NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.31, alpha: 0.95).setStroke()
    connector.stroke()

    let nodes = [
        NSPoint(x: left.maxX - stroke * 0.5, y: left.midY + stroke * 0.3),
        NSPoint(x: center.minX + stroke * 0.35, y: center.minY + stroke * 1.1),
        NSPoint(x: right.minX + stroke * 0.2, y: right.midY + stroke * 0.2),
    ]

    for node in nodes {
        let nodeRect = NSRect(x: node.x - stroke * 0.7, y: node.y - stroke * 0.7, width: stroke * 1.4, height: stroke * 1.4)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: nodeRect).fill()
    }
}

func drawDisplay(_ rect: NSRect, corner: CGFloat, tint: NSColor, isPrimary: Bool) {
    let shell = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    NSColor(calibratedWhite: 1, alpha: isPrimary ? 0.95 : 0.88).setFill()
    shell.fill()

    let screenInset = rect.width * (isPrimary ? 0.085 : 0.1)
    let screenRect = rect.insetBy(dx: screenInset, dy: screenInset)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: corner * 0.55, yRadius: corner * 0.55)

    let gradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.06, green: 0.15, blue: 0.33, alpha: 1), 0.0),
        (tint.withAlphaComponent(0.92), 1.0)
    )!
    gradient.draw(in: screen, angle: -40)

    let bezel = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
    bezel.lineWidth = rect.width * 0.022
    bezel.stroke()

    let shineRect = NSRect(x: screenRect.minX, y: screenRect.midY, width: screenRect.width, height: screenRect.height * 0.45)
    let shine = NSBezierPath(roundedRect: shineRect, xRadius: corner * 0.45, yRadius: corner * 0.45)
    NSColor(calibratedWhite: 1, alpha: isPrimary ? 0.18 : 0.12).setFill()
    shine.fill()

    let standWidth = rect.width * 0.22
    let standHeight = rect.height * 0.075
    let stand = NSBezierPath(roundedRect: NSRect(
        x: rect.midX - standWidth / 2,
        y: rect.minY - standHeight * 1.25,
        width: standWidth,
        height: standHeight
    ), xRadius: standHeight / 2, yRadius: standHeight / 2)
    NSColor(calibratedWhite: 1, alpha: 0.68).setFill()
    stand.fill()

    if isPrimary {
        let markerSize = rect.width * 0.09
        let markerRect = NSRect(x: rect.maxX - markerSize * 1.4, y: rect.maxY - markerSize * 1.4, width: markerSize, height: markerSize)
        NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.31, alpha: 1).setFill()
        NSBezierPath(ovalIn: markerRect).fill()
    }
}

func drawHighlight(in rect: NSRect) {
    let band = NSBezierPath()
    band.move(to: NSPoint(x: rect.width * 0.08, y: rect.height * 0.9))
    band.curve(
        to: NSPoint(x: rect.width * 0.88, y: rect.height * 0.6),
        controlPoint1: NSPoint(x: rect.width * 0.25, y: rect.height * 0.96),
        controlPoint2: NSPoint(x: rect.width * 0.64, y: rect.height * 0.78)
    )
    band.lineWidth = rect.width * 0.06
    band.lineCapStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
    band.stroke()
}

func savePNG(image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "RenderIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    try data.write(to: url)
}

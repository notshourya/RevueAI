#!/usr/bin/swift
// Renders the RevueAI orb app icon: a liquid-metal orb on graphite, at every
// size macOS needs. Compile with swiftc (script mode is unreliable on beta
// toolchains):
//   xcrun swiftc Tools/render-appicon.swift -o /tmp/render-appicon
//   /tmp/render-appicon MyApp/Assets.xcassets/AppIcon.appiconset
import AppKit

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let context = NSGraphicsContext.current!.cgContext

    // Background: near-black rounded square (system applies the final mask).
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.22
    let path = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.addPath(path)
    context.setFillColor(CGColor(red: 0.02, green: 0.024, blue: 0.025, alpha: 1))
    context.fillPath()

    let field = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(red: 0.02, green: 0.024, blue: 0.025, alpha: 1),
                                    CGColor(red: 0.075, green: 0.085, blue: 0.082, alpha: 1)] as CFArray,
                           locations: [0, 1])!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(field,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: size, y: size),
                               options: [])
    context.restoreGState()

    // Orb body.
    let orbDiameter = size * 0.56
    let orbRect = CGRect(x: (size - orbDiameter) / 2, y: (size - orbDiameter) / 2,
                         width: orbDiameter, height: orbDiameter)
    let colors = [
        CGColor(gray: 1, alpha: 0.92),
        CGColor(red: 0.18, green: 0.86, blue: 0.80, alpha: 0.92),
        CGColor(red: 0.34, green: 0.44, blue: 0.45, alpha: 1),
        CGColor(red: 0.025, green: 0.03, blue: 0.03, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: [0, 0.28, 0.62, 1])!
    context.saveGState()
    context.addEllipse(in: orbRect)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: orbRect.midX - orbDiameter * 0.14, y: orbRect.midY + orbDiameter * 0.2),
        startRadius: max(1, orbDiameter * 0.018),
        endCenter: CGPoint(x: orbRect.midX, y: orbRect.midY),
        endRadius: orbDiameter * 0.62,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Heated horizon band across the middle.
    let bandColors = [
        CGColor(red: 0.18, green: 0.86, blue: 0.80, alpha: 0.0),
        CGColor(red: 0.18, green: 0.86, blue: 0.80, alpha: 0.78),
        CGColor(red: 1.0, green: 0.64, blue: 0.28, alpha: 0.92),
        CGColor(red: 0.18, green: 0.86, blue: 0.80, alpha: 0.0),
    ] as CFArray
    let band = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: bandColors, locations: [0.0, 0.32, 0.62, 1.0])!
    let bandRect = CGRect(x: orbRect.minX, y: orbRect.midY - orbDiameter * 0.06,
                          width: orbDiameter, height: orbDiameter * 0.12)
    context.saveGState()
    context.clip(to: bandRect)
    context.drawLinearGradient(band,
                               start: CGPoint(x: bandRect.minX, y: bandRect.midY),
                               end: CGPoint(x: bandRect.maxX, y: bandRect.midY),
                               options: [])
    context.restoreGState()

    // Top specular highlight.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    let highlightCenter = CGPoint(x: orbRect.midX - orbDiameter * 0.12, y: orbRect.maxY - orbDiameter * 0.22)
    context.drawRadialGradient(highlight, startCenter: highlightCenter, startRadius: max(1, orbDiameter * 0.018),
                               endCenter: highlightCenter, endRadius: orbDiameter * 0.35,
                               options: .drawsBeforeStartLocation)
    context.restoreGState()

    // Thin rim.
    context.addEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
    context.setLineWidth(max(1, size * 0.004))
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDirArg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "MyApp/Assets.xcassets/AppIcon.appiconset"
let outputDir = URL(fileURLWithPath: outputDirArg)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for pixels in sizes {
    let rep = renderIcon(pixels: pixels)
    let url = outputDir.appendingPathComponent("icon_\(pixels).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

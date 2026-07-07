#!/usr/bin/swift
// Renders the onboarding tour artwork: the brand orb on near-black, one
// image per slide with its own accent hue and SF-symbol badge. 16:10 to
// match TourKit's image region. Usage:
//   swift Tools/render-tour-art.swift MyApp/Resources/TourArt
import AppKit

struct Slide {
    let name: String
    let accent: NSColor
    let symbol: String
}

let slides: [Slide] = [
    Slide(name: "tour_0", accent: NSColor(red: 0.58, green: 0.47, blue: 1.0, alpha: 1), symbol: "waveform"),
    Slide(name: "tour_1", accent: NSColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1), symbol: "lock.shield.fill"),
    Slide(name: "tour_2", accent: NSColor(red: 0.36, green: 0.52, blue: 1.0, alpha: 1), symbol: "mic.fill"),
    Slide(name: "tour_3", accent: NSColor(red: 0.92, green: 0.42, blue: 0.78, alpha: 1), symbol: "person.2.wave.2.fill"),
    Slide(name: "tour_4", accent: NSColor(red: 1.0, green: 0.4, blue: 0.43, alpha: 1), symbol: "record.circle"),
]

let width = 1280, height = 800

func render(_ slide: Slide) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let size = CGSize(width: CGFloat(width), height: CGFloat(height))

    // Near-black backdrop.
    context.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    // Soft accent bloom behind the orb.
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let accent = slide.accent.usingColorSpace(.deviceRGB)!
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [accent.withAlphaComponent(0.35).cgColor,
                                    accent.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    context.drawRadialGradient(bloom, startCenter: center, startRadius: 1,
                               endCenter: center, endRadius: size.height * 0.55, options: [])

    // Orb body.
    let diameter = size.height * 0.46
    let orbRect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                         width: diameter, height: diameter)
    let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [accent.withAlphaComponent(0.95).cgColor,
                                   accent.withAlphaComponent(0.45).cgColor,
                                   CGColor(red: 0.08, green: 0.07, blue: 0.1, alpha: 1)] as CFArray,
                          locations: [0, 0.55, 1])!
    context.saveGState()
    context.addEllipse(in: orbRect)
    context.clip()
    context.drawRadialGradient(
        body,
        startCenter: CGPoint(x: orbRect.midX - diameter * 0.14, y: orbRect.midY + diameter * 0.2),
        startRadius: 1,
        endCenter: CGPoint(x: orbRect.midX, y: orbRect.midY),
        endRadius: diameter * 0.62,
        options: .drawsAfterEndLocation
    )
    // Top specular highlight.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(gray: 1, alpha: 0.45), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    let highlightCenter = CGPoint(x: orbRect.midX - diameter * 0.12, y: orbRect.maxY - diameter * 0.22)
    context.drawRadialGradient(highlight, startCenter: highlightCenter, startRadius: 1,
                               endCenter: highlightCenter, endRadius: diameter * 0.35, options: [])
    context.restoreGState()

    // Thin rim.
    context.addEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.3))
    context.setLineWidth(2)
    context.strokePath()

    // SF-symbol badge at the orb's center.
    let config = NSImage.SymbolConfiguration(pointSize: diameter * 0.24, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: slide.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.withAlphaComponent(0.85).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let symbolRect = CGRect(x: center.x - tinted.size.width / 2,
                                y: center.y - tinted.size.height / 2,
                                width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: symbolRect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDirArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MyApp/Resources/TourArt"
let outputDir = URL(fileURLWithPath: outputDirArg)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for slide in slides {
    let rep = render(slide)
    let url = outputDir.appendingPathComponent("\(slide.name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

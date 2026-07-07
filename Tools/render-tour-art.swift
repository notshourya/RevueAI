#!/usr/bin/swift
// Renders the onboarding tour artwork: the liquid-metal brand orb on graphite,
// one image per slide with its own heat hue and SF-symbol badge. 16:10 to
// match TourKit's image region. Usage:
//   swift Tools/render-tour-art.swift MyApp/Resources/TourArt
import AppKit

struct Slide {
    let name: String
    let accent: NSColor
    let symbol: String
}

let slides: [Slide] = [
    Slide(name: "tour_0", accent: NSColor(red: 0.18, green: 0.86, blue: 0.80, alpha: 1), symbol: "waveform"),
    Slide(name: "tour_1", accent: NSColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1), symbol: "lock.shield.fill"),
    Slide(name: "tour_2", accent: NSColor(red: 0.40, green: 0.55, blue: 0.62, alpha: 1), symbol: "mic.fill"),
    Slide(name: "tour_3", accent: NSColor(red: 1.00, green: 0.64, blue: 0.28, alpha: 1), symbol: "person.2.wave.2.fill"),
    Slide(name: "tour_4", accent: NSColor(red: 1.00, green: 0.34, blue: 0.28, alpha: 1), symbol: "record.circle"),
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

    // Graphite backdrop.
    context.setFillColor(CGColor(red: 0.02, green: 0.024, blue: 0.025, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    let field = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(red: 0.02, green: 0.024, blue: 0.025, alpha: 1),
                                    CGColor(red: 0.07, green: 0.08, blue: 0.08, alpha: 1)] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(field,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: size.width, y: size.height),
                               options: [])

    // Soft heat bloom behind the orb.
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let accent = slide.accent.usingColorSpace(.deviceRGB)!
    let warm = NSColor(red: 1.0, green: 0.64, blue: 0.28, alpha: 1)
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [accent.withAlphaComponent(0.32).cgColor,
                                    accent.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    context.drawRadialGradient(bloom, startCenter: center, startRadius: 1,
                               endCenter: center, endRadius: size.height * 0.55, options: [])

    // Orb body.
    let diameter = size.height * 0.46
    let orbRect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                         width: diameter, height: diameter)
    let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(gray: 1, alpha: 0.92),
                                   accent.withAlphaComponent(0.82).cgColor,
                                   CGColor(red: 0.32, green: 0.42, blue: 0.43, alpha: 1),
                                   CGColor(red: 0.025, green: 0.03, blue: 0.03, alpha: 1)] as CFArray,
                          locations: [0, 0.26, 0.58, 1])!
    context.saveGState()
    context.addEllipse(in: orbRect)
    context.clip()
    context.drawRadialGradient(
        body,
        startCenter: CGPoint(x: orbRect.midX - diameter * 0.14, y: orbRect.midY + diameter * 0.2),
        startRadius: diameter * 0.018,
        endCenter: CGPoint(x: orbRect.midX, y: orbRect.midY),
        endRadius: diameter * 0.62,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // Heated horizon band.
    let band = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [accent.withAlphaComponent(0).cgColor,
                                   accent.withAlphaComponent(0.72).cgColor,
                                   warm.withAlphaComponent(0.86).cgColor,
                                   accent.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 0.32, 0.62, 1])!
    let bandRect = CGRect(x: orbRect.minX, y: orbRect.midY - diameter * 0.05,
                          width: diameter, height: diameter * 0.14)
    context.saveGState()
    context.clip(to: bandRect)
    context.drawLinearGradient(band,
                               start: CGPoint(x: bandRect.minX, y: bandRect.midY),
                               end: CGPoint(x: bandRect.maxX, y: bandRect.midY),
                               options: [])
    context.restoreGState()
    // Top specular highlight.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(gray: 1, alpha: 0.45), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    let highlightCenter = CGPoint(x: orbRect.midX - diameter * 0.12, y: orbRect.maxY - diameter * 0.22)
    context.drawRadialGradient(highlight, startCenter: highlightCenter, startRadius: diameter * 0.018,
                               endCenter: highlightCenter, endRadius: diameter * 0.35,
                               options: .drawsBeforeStartLocation)
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

// Renders the onboarding tour artwork: the liquid glass blob on neutral
// near-black, one image per slide with a different phase and an SF-symbol
// badge. 16:10 to match TourKit's image region. Compile with swiftc:
//   xcrun swiftc Tools/render-tour-art.swift -o /tmp/render-tour-art
//   /tmp/render-tour-art MyApp/Resources/TourArt
import AppKit

struct Slide {
    let name: String
    let phase: CGFloat
    let symbol: String
}

let slides: [Slide] = [
    Slide(name: "tour_0", phase: 2.1, symbol: "waveform"),
    Slide(name: "tour_1", phase: 3.4, symbol: "lock.shield.fill"),
    Slide(name: "tour_2", phase: 4.8, symbol: "mic.fill"),
    Slide(name: "tour_3", phase: 0.9, symbol: "person.2.wave.2.fill"),
    Slide(name: "tour_4", phase: 5.7, symbol: "record.circle"),
]

let width = 1280, height = 800

func blobPath(center: CGPoint, baseRadius: CGFloat, phase: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 240
    for i in 0...steps {
        let theta = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let radius = baseRadius * (1.0
            + 0.055 * sin(3 * theta + phase)
            + 0.038 * sin(5 * theta - phase * 0.7 + 1.7)
            + 0.024 * sin(8 * theta + phase * 1.4 + 4.2))
        let point = CGPoint(x: center.x + cos(theta) * radius, y: center.y + sin(theta) * radius)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func render(_ slide: Slide) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let size = CGSize(width: CGFloat(width), height: CGFloat(height))

    // Neutral near-black backdrop.
    context.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.062, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let radius = size.height * 0.24
    let blob = blobPath(center: center, baseRadius: radius, phase: slide.phase)

    // Translucent glass body.
    context.saveGState()
    context.addPath(blob)
    context.clip()
    let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.72, green: 0.82, blue: 0.90, alpha: 0.34),
                                   CGColor(red: 0.45, green: 0.55, blue: 0.66, alpha: 0.16),
                                   CGColor(red: 0.20, green: 0.25, blue: 0.32, alpha: 0.10)] as CFArray,
                          locations: [0, 0.55, 1])!
    context.drawRadialGradient(
        body,
        startCenter: CGPoint(x: center.x - radius * 0.25, y: center.y + radius * 0.35),
        startRadius: 1,
        endCenter: center,
        endRadius: radius * 1.25,
        options: .drawsAfterEndLocation
    )
    let spec = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(gray: 1, alpha: 0.50), CGColor(gray: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    let specCenter = CGPoint(x: center.x - radius * 0.30, y: center.y + radius * 0.42)
    context.drawRadialGradient(spec, startCenter: specCenter, startRadius: 1,
                               endCenter: specCenter, endRadius: radius * 0.55, options: [])
    let inner = blobPath(center: center, baseRadius: radius * 0.78, phase: slide.phase + 0.9)
    context.addPath(inner)
    context.setStrokeColor(CGColor(red: 0.80, green: 0.88, blue: 0.95, alpha: 0.20))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // Bright glass rim + soft glow.
    context.addPath(blob)
    context.setStrokeColor(CGColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.85))
    context.setLineWidth(4)
    context.strokePath()
    context.addPath(blob)
    context.setStrokeColor(CGColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.20))
    context.setLineWidth(16)
    context.strokePath()

    // SF-symbol badge at the blob's center.
    let config = NSImage.SymbolConfiguration(pointSize: radius * 0.42, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: slide.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.withAlphaComponent(0.88).set()
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

// Renders the RevueAI app icon: a liquid glass blob — translucent body,
// bright rim, wandering specular — on a neutral near-black square. Compile
// with swiftc (script mode is unreliable on beta toolchains):
//   xcrun swiftc Tools/render-appicon.swift -o /tmp/render-appicon
//   /tmp/render-appicon MyApp/Assets.xcassets/AppIcon.appiconset
import AppKit

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

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let context = NSGraphicsContext.current!.cgContext

    // Neutral near-black rounded square.
    let corner = size * 0.22
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.addPath(bg)
    context.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.062, alpha: 1))
    context.fillPath()

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.30
    let blob = blobPath(center: center, baseRadius: radius, phase: 2.1)

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
    // Specular highlight inside the body.
    let spec = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    let specCenter = CGPoint(x: center.x - radius * 0.30, y: center.y + radius * 0.42)
    context.drawRadialGradient(spec, startCenter: specCenter, startRadius: 1,
                               endCenter: specCenter, endRadius: radius * 0.55, options: [])
    // Inner refraction hint.
    let inner = blobPath(center: center, baseRadius: radius * 0.78, phase: 3.0)
    context.addPath(inner)
    context.setStrokeColor(CGColor(red: 0.80, green: 0.88, blue: 0.95, alpha: 0.20))
    context.setLineWidth(max(1, size * 0.006))
    context.strokePath()
    context.restoreGState()

    // Bright glass rim.
    context.addPath(blob)
    context.setStrokeColor(CGColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.85))
    context.setLineWidth(max(1, size * 0.009))
    context.strokePath()
    // Soft rim glow.
    context.addPath(blob)
    context.setStrokeColor(CGColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.22))
    context.setLineWidth(max(2, size * 0.03))
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

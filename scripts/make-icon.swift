import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
// Draw in a fixed design space, then rasterize each representation independently.
// The transparent margin matches the visual footprint of macOS application icons.
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func gradient(_ path: NSBezierPath, _ colors: [NSColor], _ angle: CGFloat = -90) {
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}
func shadow(_ blur: CGFloat, _ y: CGFloat, _ opacity: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: y)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}
func drawIcon(small: Bool) {
    let tile = rounded(100, 100, 824, 824, 185)
    shadow(24, -14, 0.28) {
        gradient(tile, [color(0.16, 0.71, 1), color(0.035, 0.43, 0.96), color(0.07, 0.25, 0.79)])
    }
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    // A broad highlight gives the tile a soft convex surface.
    let glow = NSGradient(starting: color(0.45, 0.95, 1, 0.42), ending: color(0.45, 0.95, 1, 0))!
    glow.draw(fromCenter: NSPoint(x: 340, y: 910), radius: 0,
              toCenter: NSPoint(x: 340, y: 910), radius: 730, options: [])
    NSGraphicsContext.restoreGraphicsState()
    gradient(rounded(102, 102, 820, 820, 183), [color(1, 1, 1, 0.45), color(1, 1, 1, 0.04)], -90)
    gradient(rounded(105, 105, 814, 814, 180), [color(0.13, 0.68, 1), color(0.035, 0.43, 0.96), color(0.07, 0.25, 0.79)])
    NSGraphicsContext.saveGraphicsState()
    rounded(105, 105, 814, 814, 180).addClip()
    glow.draw(fromCenter: NSPoint(x: 330, y: 920), radius: 0,
              toCenter: NSPoint(x: 330, y: 920), radius: 680, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Tapered aluminum support, with the foot grounding the display.
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: 468, y: 374))
    neck.line(to: NSPoint(x: 556, y: 374))
    neck.curve(to: NSPoint(x: 579, y: 260), controlPoint1: NSPoint(x: 554, y: 304), controlPoint2: NSPoint(x: 561, y: 275))
    neck.line(to: NSPoint(x: 445, y: 260))
    neck.curve(to: NSPoint(x: 468, y: 374), controlPoint1: NSPoint(x: 463, y: 282), controlPoint2: NSPoint(x: 470, y: 311))
    neck.close()
    gradient(neck, [color(0.47, 0.54, 0.65), color(0.88, 0.92, 0.96), color(0.67, 0.74, 0.83)])
    shadow(12, -7, 0.23) {
        gradient(rounded(390, 244, 244, 24, 12), [color(0.97, 0.99, 1), color(0.65, 0.73, 0.84)])
    }
    // A single strong silhouette remains readable in the 16 px Finder slot.
    let body = rounded(207, 346, 610, 434, 35)
    shadow(26, -16, 0.33) {
        gradient(body, [color(0.99, 1, 1), color(0.80, 0.86, 0.93), color(0.62, 0.70, 0.81)])
    }
    color(1, 1, 1, 0.7).setStroke()
    body.lineWidth = 2
    body.stroke()
    let bezel = rounded(221, 399, 582, 367, 23)
    gradient(bezel, [color(0.12, 0.17, 0.25), color(0.035, 0.065, 0.12)])
    let screen = rounded(231, 409, 562, 347, 15)
    gradient(screen, [color(0.02, 0.12, 0.38), color(0.055, 0.35, 0.73), color(0.12, 0.70, 0.90)], -45)
    NSGraphicsContext.saveGraphicsState()
    screen.addClip()
    // Abstract macOS-like wallpaper: flowing bands, no UI or tiny details.
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 200, y: 410))
    wave.curve(to: NSPoint(x: 810, y: 704), controlPoint1: NSPoint(x: 454, y: 740), controlPoint2: NSPoint(x: 625, y: 432))
    wave.line(to: NSPoint(x: 830, y: 385))
    wave.line(to: NSPoint(x: 200, y: 385))
    wave.close()
    gradient(wave, [color(0.29, 0.94, 0.98), color(0.04, 0.61, 0.90), color(0.06, 0.30, 0.77)], -100)
    let foreground = NSBezierPath()
    foreground.move(to: NSPoint(x: 190, y: 410))
    foreground.curve(to: NSPoint(x: 830, y: 592), controlPoint1: NSPoint(x: 450, y: 610), controlPoint2: NSPoint(x: 659, y: 390))
    foreground.line(to: NSPoint(x: 830, y: 380))
    foreground.line(to: NSPoint(x: 190, y: 380))
    foreground.close()
    gradient(foreground, [color(0.25, 0.49, 0.98), color(0.23, 0.24, 0.76)], -70)
    gradient(rounded(231, 409, 562, 347, 15), [color(1, 1, 1, 0.12), color(1, 1, 1, 0)], -90)
    NSGraphicsContext.restoreGraphicsState()
    if !small {
        color(0.29, 0.36, 0.46, 0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: 507, y: 370, width: 10, height: 10)).fill()
    }
}
for base in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let size = base * multiplier
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = CGFloat(size) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        drawIcon(small: size <= 32)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = multiplier == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
// Small icon slots need planar RGB + a separate alpha mask. IconServices can
// interpret PNG bytes in icp4/icp5 as raw pixels, producing multicolored noise.
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var payload = Data()
func appendChunk(_ type: String, _ data: Data) {
    payload.append(Data(type.utf8)); payload.append(bigEndian(data.count + 8)); payload.append(data)
}
for (size, rgbType, alphaType) in [(16, "is32", "s8mk"), (32, "il32", "l8mk"), (128, "it32", "t8mk")] {
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: destination.appendingPathComponent("icon_\(size)x\(size).png")))!
    precondition(bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel == 4 && !bitmap.bitmapFormat.contains(.alphaFirst))
    var channels = [[UInt8]](repeating: [], count: 4)
    for y in 0..<size {
        for x in 0..<size {
            // Preserve encoded sRGB bytes; NSColor conversion would apply gamma twice.
            var pixel = [UInt](repeating: 0, count: 4)
            bitmap.getPixel(&pixel, atX: x, y: y)
            for channel in 0..<4 { channels[channel].append(UInt8(pixel[channel])) }
        }
    }
    var rgb = Data(count: size == 128 ? 4 : 0)
    // ICNS RLE: literal packets hold 1...128 bytes with a (count - 1) prefix.
    for channel in channels.prefix(3) {
        for offset in stride(from: 0, to: channel.count, by: 128) {
            let end = min(offset + 128, channel.count)
            rgb.append(UInt8(end - offset - 1))
            rgb.append(contentsOf: channel[offset..<end])
        }
    }
    appendChunk(rgbType, rgb)
    appendChunk(alphaType, Data(channels[3]))
}
let chunks = [("ic08", "256x256"), ("ic09", "512x512"), ("ic10", "512x512@2x"),
              ("ic11", "16x16@2x"), ("ic12", "32x32@2x"),
              ("ic13", "128x128@2x"), ("ic14", "256x256@2x")]
for (type, filename) in chunks {
    let png = try Data(contentsOf: destination.appendingPathComponent("icon_\(filename).png"))
    appendChunk(type, png)
}
var container = Data("icns".utf8)
container.append(bigEndian(payload.count + 8)); container.append(payload)
try container.write(to: destination.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))

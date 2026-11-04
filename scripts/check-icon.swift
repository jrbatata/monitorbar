import AppKit

// Compare the source PNGs with Apple's own decoding of the final ICNS.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let decoded = URL(fileURLWithPath: CommandLine.arguments[2])
var passed = 0
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        let expected = NSBitmapImageRep(data: try Data(contentsOf: source.appendingPathComponent(filename)))!
        let actual = NSBitmapImageRep(data: try Data(contentsOf: decoded.appendingPathComponent(filename)))!
        precondition(actual.pixelsWide == base * scale && actual.pixelsHigh == base * scale, "Wrong dimensions: \(filename)")
        var maxDifference: CGFloat = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let b = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let av = [a.redComponent * a.alphaComponent, a.greenComponent * a.alphaComponent, a.blueComponent * a.alphaComponent, a.alphaComponent]
                let bv = [b.redComponent * b.alphaComponent, b.greenComponent * b.alphaComponent, b.blueComponent * b.alphaComponent, b.alphaComponent]
                for i in 0..<4 { maxDifference = max(maxDifference, abs(av[i] - bv[i]) * 255) }
            }
        }
        guard maxDifference <= 3 else {
            print("FAIL \(filename): pixel difference \(maxDifference)/255")
            exit(1)
        }
        print("PASS \(filename): maximum pixel difference \(String(format: "%.2f", Double(maxDifference)))/255")
        passed += 1
    }
}
print("Verified all \(passed) icon representations with the macOS decoder.")

import AppKit

// A small, dependency-free DMG layout writer. The Finder metadata uses a single
// leaf DS_Store tree and a path-based Alias v2, so no image mounting is required.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let previewURL = URL(fileURLWithPath: CommandLine.arguments[3])
let volumeName = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "MonitorBar"
let width = 720, height = 460
let ink = NSColor(red: 0.10, green: 0.20, blue: 0.23, alpha: 1)
let secondary = NSColor(red: 0.34, green: 0.43, blue: 0.44, alpha: 1)
let teal = NSColor(red: 0.18, green: 0.49, blue: 0.44, alpha: 1)

func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, centered: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let value = string as NSString
    let textWidth = value.size(withAttributes: attributes).width
    value.draw(at: CGPoint(x: centered ? x - textWidth / 2 : x, y: CGFloat(height) - y - size * 1.2), withAttributes: attributes)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}
func drawBackground() {
    NSGradient(starting: NSColor(red: 0.97, green: 0.985, blue: 0.975, alpha: 1),
               ending: NSColor(red: 0.89, green: 0.95, blue: 0.93, alpha: 1))!
        .draw(in: NSBezierPath(rect: rect(0, 0, 720, 460)), angle: -35)
    // Quiet contour lines, with all decoration outside the draggable icon area.
    for i in 0..<5 {
        let curve = NSBezierPath()
        curve.move(to: CGPoint(x: 475 + i * 22, y: 460))
        curve.curve(to: CGPoint(x: 745, y: 320 - i * 18),
                    controlPoint1: CGPoint(x: 530 + i * 22, y: 370), controlPoint2: CGPoint(x: 650, y: 460 - i * 25))
        teal.withAlphaComponent(0.07).setStroke(); curve.lineWidth = 1; curve.stroke()
    }
    text("M O N I T O R B A R", x: 44, y: 34, size: 10, color: teal, weight: .bold)
    text("Seu setup começa aqui.", x: 44, y: 62, size: 30, color: ink, weight: .semibold)
    text("Arraste o MonitorBar para a pasta Applications.", x: 44, y: 106, size: 14, color: secondary)

    NSColor.white.withAlphaComponent(0.56).setFill()
    let tray = NSBezierPath(roundedRect: rect(38, 160, 644, 178), xRadius: 24, yRadius: 24)
    tray.fill(); teal.withAlphaComponent(0.09).setStroke(); tray.lineWidth = 1; tray.stroke()
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 292, y: 229))
    arrow.curve(to: CGPoint(x: 425, y: 229), controlPoint1: CGPoint(x: 333, y: 248), controlPoint2: CGPoint(x: 383, y: 248))
    arrow.move(to: CGPoint(x: 413, y: 244)); arrow.line(to: CGPoint(x: 428, y: 229)); arrow.line(to: CGPoint(x: 409, y: 224))
    teal.setStroke(); arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    text("ARRASTE", x: 360, y: 256, size: 9, color: secondary, weight: .medium, centered: true)

    text("Depois de abrir, encontre o ícone na barra de menus.", x: 360, y: 369, size: 13, color: secondary, centered: true)
    text("Feito para o seu Mac. Do seu jeito.", x: 360, y: 411, size: 11, color: teal, centered: true)
}
func render(scale: Int, icons: Bool) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = CGSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // bitmap.size already establishes the pixel-to-point scale for this context.
    drawBackground()
    if icons {
        NSImage(contentsOf: iconURL)?.draw(in: rect(132, 182, 96, 96))
        // Read the system artwork directly: icon services may be unavailable in CI.
        NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns")?
            .draw(in: rect(492, 182, 96, 96))
        NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AliasBadgeIcon.icns")?
            .draw(in: rect(492, 254, 22, 22))
        text("MonitorBar", x: 180, y: 288, size: 13, color: ink, centered: true)
        text("Applications", x: 540, y: 288, size: 13, color: ink, centered: true)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
let reps = [render(scale: 1, icons: false), render(scale: 2, icons: false)]
let tiff = NSBitmapImageRep.representationOfImageReps(in: reps, using: .tiff, properties: [.compressionFactor: 1])!
try tiff.write(to: root.appendingPathComponent(".background.tiff"))
try render(scale: 2, icons: true).representation(using: .png, properties: [:])!.write(to: previewURL)

func u16(_ value: Int) -> Data { var v = UInt16(truncatingIfNeeded: value).bigEndian; return withUnsafeBytes(of: &v) { Data($0) } }
func u32(_ value: Int) -> Data { var v = UInt32(truncatingIfNeeded: value).bigEndian; return withUnsafeBytes(of: &v) { Data($0) } }
func ascii(_ value: String) -> Data { Data(value.utf8) }
func pascal(_ value: String, count: Int) -> Data {
    let bytes = ascii(value).prefix(count - 1)
    return Data([UInt8(bytes.count)]) + bytes + Data(count: count - bytes.count - 1)
}
func tag(_ type: Int, _ data: Data) -> Data { u16(type) + u16(data.count) + data + Data(count: data.count % 2) }

// Alias v2: resolve the hidden background by volume name and volume-relative path.
// CNIDs are deliberately unknown, since the HFS catalog is built after this step.
var alias = Data(count: 4) + u16(0) + u16(2) + u16(0)
alias += pascal(volumeName, count: 28) + u32(0) + ascii("H+") + u16(5)
alias += u32(0) + pascal(".background.tiff", count: 64) + u32(0) + u32(0)
alias += Data(count: 8) + u16(-1) + u16(-1) + u32(0) + Data(count: 12)
precondition(alias.count == 150)
alias += tag(2, ascii("\(volumeName):.background.tiff"))
for (type, value) in [(14, ".background.tiff"), (15, volumeName)] {
    let utf16 = value.data(using: .utf16BigEndian)!
    alias += tag(type, u16(utf16.count / 2) + utf16)
}
// Tag 18 must be rooted at the VOLUME root, not a bare relative filename.
alias += tag(18, ascii("/.background.tiff"))
alias += tag(19, ascii("/Volumes/\(volumeName)"))
alias += u16(-1) + u16(0)
alias.replaceSubrange(4..<6, with: u16(alias.count))
guard CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault, alias as CFData) != nil else {
    fatalError("O macOS rejeitou o alias da imagem de fundo.")
}

let window: [String: Any] = ["WindowBounds": "{{160, 140}, {720, 460}}", "ShowToolbar": false,
    "ShowStatusBar": false, "ShowPathbar": false, "ShowSidebar": false, "ShowTabView": false,
    "ContainerShowSidebar": false, "SidebarWidth": 0]
let icons: [String: Any] = ["viewOptionsVersion": 1, "backgroundType": 2, "backgroundImageAlias": alias,
    "backgroundColorRed": 0.95, "backgroundColorGreen": 0.98, "backgroundColorBlue": 0.96,
    "iconSize": 96.0, "textSize": 13.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
    "arrangeBy": "none", "labelOnBottom": true, "showIconPreview": false, "showItemInfo": false,
    "scrollPositionX": 0.0, "scrollPositionY": 0.0]
func plist(_ object: [String: Any]) throws -> Data { try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0) }
struct Entry {
    let file: String, key: String, type: String
    let payload: Data
    var bytes: Data {
        let name = file.data(using: .utf16BigEndian)!
        return u32(name.count / 2) + name + ascii(key) + ascii(type) + (type == "blob" ? u32(payload.count) : Data()) + payload
    }
}
let entries = [
    Entry(file: ".", key: "bwsp", type: "blob", payload: try plist(window)),
    Entry(file: ".", key: "icvp", type: "blob", payload: try plist(icons)),
    Entry(file: ".", key: "vstl", type: "type", payload: ascii("icnv")),
    Entry(file: ".", key: "vSrn", type: "long", payload: u32(1)),
    Entry(file: "Applications", key: "Iloc", type: "blob", payload: u32(540) + u32(230) + u32(-1) + u32(0xffff0000)),
    Entry(file: "MonitorBar.app", key: "Iloc", type: "blob", payload: u32(180) + u32(230) + u32(-1) + u32(0xffff0000))
].sorted { ($0.file.lowercased(), $0.key) < ($1.file.lowercased(), $1.key) }
var leaf = u32(0) + u32(entries.count)
for entry in entries { leaf += entry.bytes }
precondition(leaf.count < 4096)
// Finder reserves offsets 0...63. Keep DSDB outside that header reservation.
// Buddy blocks: 0=allocator at 2048, 1=DSDB at 64, 2=leaf at 4096.
var allocator = u32(3) + u32(0) + u32(2048 | 11) + u32(64 | 5) + u32(4096 | 12) + Data(count: 253 * 4)
allocator += u32(1) + Data([4]) + ascii("DSDB") + u32(1)
for power in 0..<32 {
    if power == 5 { allocator += u32(1) + u32(96); continue }
    let free = (7...10).contains(power) || (13...30).contains(power)
    allocator += u32(free ? 1 : 0)
    if free { allocator += u32(1 << power) }
}
var store = Data(count: 8196)
func put(_ bytes: Data, at offset: Int) { store.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
put(u32(1) + ascii("Bud1") + u32(2048) + u32(2048) + u32(2048)
    + u32(0x100c) + u32(0x87) + u32(0x200b) + u32(0), at: 0)
put(u32(2) + u32(0) + u32(entries.count) + u32(1) + u32(4096), at: 68)
put(allocator, at: 2052)
put(leaf, at: 4100)
try store.write(to: root.appendingPathComponent(".DS_Store"))
print("Finder: 720×460, ícones 96 pt, app (180,230), Applications (540,230).")
print("Prévia de composição: \(previewURL.path)")

import AppKit
import SwiftUI
import MonitorCore

/// Exports editorial layouts containing the app's actual SwiftUI views.
/// Uses only DemoDriver data; it never starts the hardware driver or login item.
@MainActor enum StoreAssetsRenderer {
    private static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    private static let output = root.appendingPathComponent("docs/app-store/pt-BR")
    private static let ink = NSColor(srgbRed: 0.94, green: 0.97, blue: 1, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.64, green: 0.73, blue: 0.86, alpha: 1)
    private static let blue = NSColor(srgbRed: 0.42, green: 0.74, blue: 1, alpha: 1)
    private static var frames: [NSImage] = []

    static func run() {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let store = demoStore()
            let login = LaunchAtLogin()
            let menu = capture(QuickPanel(launchAtLogin: login, store: store, organize: {}),
                               size: NSSize(width: 390, height: 740))
            let lightMenu = capture(QuickPanel(launchAtLogin: login, store: store, organize: {}),
                                    size: NSSize(width: 390, height: 740), scheme: .light)
            let arrangement = capture(ArrangementView(store: store), size: NSSize(width: 960, height: 600))
            let builtIn = capture(DisplayCard(store: store, display: store.displays[0], number: 1)
                .padding(1), size: NSSize(width: 390, height: 250), scheme: .light)
            let external = capture(DisplayCard(store: store, display: store.displays[1], number: 2)
                .padding(1), size: NSSize(width: 390, height: 250), scheme: .light)
            let externalDark = capture(DisplayCard(store: store, display: store.displays[1], number: 2)
                .padding(1), size: NSSize(width: 390, height: 250))

            try canvas("01-todas-as-telas.png", index: 1) {
                branding()
                title("Todas as telas. Um só lugar.")
                picture(menu, x: 465, y: 145, width: 510)
            }
            try canvas("02-organize-seu-espaco.png", index: 2) {
                branding()
                title("Sua mesa, na tela.")
                picture(arrangement, x: 165, y: 155, width: 1110)
            }
            try canvas("03-brilho-por-monitor.png", index: 3, light: true) {
                branding(light: true)
                title("Brilho na medida certa.", light: true)
                picture(builtIn, x: 310, y: 165, width: 820, light: true)
                picture(external, x: 310, y: 525, width: 820, light: true)
            }

            // Prepare a real pending transaction on the simulated backend.
            let confirmationStore = demoStore()
            Task { try? await confirmationStore.session.preview(confirmationStore.settings) }
            let deadline = Date().addingTimeInterval(2)
            while confirmationStore.session.deadline == nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            confirmationStore.remaining = 20
            let confirmation = capture(ConfirmationView(store: confirmationStore)
                .background(Color(red: 0.12, green: 0.17, blue: 0.25)),
                size: NSSize(width: 440, height: 230))
            try canvas("04-ajuste-e-confirme.png", index: 4) {
                branding()
                title("Ajuste e confirme.")
                picture(externalDark, x: 185, y: 185, width: 1070)
                picture(confirmation, x: 670, y: 610, width: 620)
            }
            try canvas("05-claro-ou-escuro.png", index: 5) {
                branding()
                title("Claro ou escuro.")
                picture(lightMenu, x: 195, y: 155, width: 490)
                picture(menu, x: 755, y: 155, width: 490)
            }
            try contactSheet()
            print("Exported 5 screenshots at 2880 × 1800 and a contact sheet to \(output.path)")
        } catch {
            fputs("Screenshot export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func demoStore() -> MonitorStore {
        let store = MonitorStore(demo: true)
        store.displays = (try? store.driver.displays()) ?? []
        for display in store.displays {
            store.brightness[display.id] = BrightnessState(value: display.builtIn ? 0.65 : 0.8, method: .native)
        }
        return store
    }

    private static func capture<V: View>(_ view: V, size: NSSize, scheme: ColorScheme = .dark) -> NSImage {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // Fixed-height snapshot hosts may center intrinsic-height views. Trim only
        // transparent outer rows; no application content is removed or repainted.
        var top = 0, bottom = bitmap.pixelsHigh - 1
        func alpha(_ y: Int) -> CGFloat {
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.alphaComponent ?? 0
        }
        while top < bottom && alpha(top) < 0.01 { top += 1 }
        while bottom > top && alpha(bottom) < 0.01 { bottom -= 1 }
        let cg = bitmap.cgImage!.cropping(to: CGRect(x: 0, y: top, width: bitmap.pixelsWide, height: bottom - top + 1))!
        return NSImage(cgImage: cg, size: NSSize(width: size.width, height: CGFloat(bottom - top + 1) * size.width / CGFloat(bitmap.pixelsWide)))
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: 900 - y - h, width: w, height: h)
    }
    private static func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
                             weight: NSFont.Weight = .regular, color: NSColor? = nil,
                             tracking: CGFloat = 0, lineHeight: CGFloat? = nil) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if let lineHeight { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight }
        let attributed = NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color ?? ink,
            .kern: tracking, .paragraphStyle: paragraph
        ])
        attributed.draw(in: rect(x, y, width, 320))
    }
    private static func title(_ value: String, light: Bool = false) {
        text(value, x: 520, y: 65, width: 850, size: 36, weight: .semibold,
             color: light ? NSColor(srgbRed: 0.07, green: 0.14, blue: 0.25, alpha: 1) : ink, tracking: -1)
    }
    private static func branding(light: Bool = false) {
        if let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/Branding/MonitorBar.png")) {
            icon.draw(in: rect(80, 54, 58, 58))
        }
        text("MonitorBar", x: 151, y: 71, width: 500, size: 22, weight: .semibold,
             color: light ? NSColor(srgbRed: 0.07, green: 0.14, blue: 0.25, alpha: 1) : ink)
    }
    private static func picture(_ image: NSImage, x: CGFloat, y: CGFloat, width: CGFloat, light: Bool = false) {
        let height = width * image.size.height / image.size.width
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 32
        shadow.shadowOffset = NSSize(width: 0, height: -15)
        shadow.set()
        let bounds = rect(x, y, width, height)
        (light ? NSColor.white : NSColor(srgbRed: 0.12, green: 0.17, blue: 0.25, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).addClip()
        image.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        border.lineWidth = 1
        border.stroke()
    }
    private static func canvas(_ filename: String, index: Int, light: Bool = false, draw: () -> Void) throws {
        // RGB without alpha, exact Mac App Store dimensions, sRGB color metadata.
        let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8,
            bytesPerRow: 2880 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let transform = NSAffineTransform(); transform.scale(by: 2); transform.concat()
        let ground = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let colors: [NSColor] = light ? [NSColor(srgbRed: 0.96, green: 0.98, blue: 1, alpha: 1), NSColor(srgbRed: 0.83, green: 0.90, blue: 0.99, alpha: 1)]
            : [NSColor(srgbRed: 0.025, green: 0.065, blue: 0.13, alpha: 1), NSColor(srgbRed: 0.06, green: 0.19, blue: 0.37, alpha: 1)]
        NSGradient(colors: colors)!.draw(in: ground, angle: 15)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        bitmap.setProperty(.colorSyncProfileData, withValue: NSColorSpace.sRGB.iccProfileData!)
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent(filename))
        frames.append(NSImage(data: data)!)
    }
    private static func contactSheet() throws {
        let image = NSImage(size: NSSize(width: 1440, height: 1383))
        image.lockFocus()
        NSColor(srgbRed: 0.03, green: 0.06, blue: 0.1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1440, height: 1383).fill()
        for (index, frame) in frames.enumerated() {
            let col = index % 2, row = index / 2
            frame.draw(in: NSRect(x: CGFloat(col) * 720 + 12, y: 1383 - CGFloat(row + 1) * 459 + 12,
                                  width: 696, height: 435))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("docs/screenshots/overview.png"))
    }
}

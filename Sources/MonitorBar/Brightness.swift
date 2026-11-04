import AppKit
import DisplayBridge
import MonitorCore

enum BrightnessMethod: String { case probing = "Verificando…", native = "Brilho da tela", ddc = "Brilho DDC/CI", unsupported = "Controle físico indisponível", dimmer = "Dimmer por software" }
struct BrightnessState { var value: Double = 1; var method: BrightnessMethod = .probing }

/// All hardware operations are serialized off the main thread.
actor BrightnessHardware {
    private var connections: [UInt32: (MBDDC, UInt16)] = [:]
    func probe(_ displays: [DisplayInfo]) -> [UInt32: BrightnessState] {
        connections.removeAll()
        let candidates = MBDDC.connections()
        var used = Set<String>()
        var result: [UInt32: BrightnessState] = [:]
        for display in displays {
            var value: Float = 1
            if MBGetBrightness(display.id, &value) == 0, value.isFinite, value >= 0, value <= 1 {
                result[display.id] = BrightnessState(value: Double(value), method: .native); continue
            }
            let details = MBDisplayDetails(display.id) as? [String: Any]
            let location = details?["IODisplayLocation"] as? String
            let serial = (details?["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            let names = details?["DisplayProductName"] as? [String: String]
            let name = names?["en_US"] ?? names?.values.first ?? display.name
            let matches = candidates.filter { candidate in
                guard !used.contains(candidate.location) else { return false }
                if let location, !location.isEmpty, candidate.location == location { return true }
                // Name + nonzero unique serial only. Identical anonymous monitors must not control each other.
                return serial != 0 && candidate.serial.uint32Value == serial && candidate.name == name
            }
            if matches.count == 1, let candidate = matches.first {
                var current: UInt16 = 0, maximum: UInt16 = 0
                if candidate.readBrightness(&current, maximum: &maximum), maximum > 0 {
                    connections[display.id] = (candidate, maximum); used.insert(candidate.location)
                    result[display.id] = BrightnessState(value: Double(current) / Double(maximum), method: .ddc)
                    continue
                }
            }
            result[display.id] = BrightnessState(method: .unsupported)
        }
        return result
    }
    func set(_ id: UInt32, method: BrightnessMethod, value: Double) -> Bool {
        let value = min(1, max(0.05, value))
        if method == .native { return MBSetBrightness(id, Float(value)) == 0 }
        if method == .ddc, let (connection, maximum) = connections[id] {
            return connection.setBrightness(UInt16((Double(maximum) * value).rounded()))
        }
        return false
    }
}

@MainActor final class DimmerController {
    private var windows: [UInt32: NSWindow] = [:]
    private var values: [UInt32: Double] = [:]
    func set(_ id: UInt32, value: Double) {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }) else { return }
        let window: NSWindow
        if let existing = windows[id] { window = existing }
        else {
            window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black; window.isOpaque = false; window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.sharingType = .none
            windows[id] = window
        }
        values[id] = value; window.setFrame(screen.frame, display: false)
        window.alphaValue = 1 - min(1, max(0.2, value)) // Never make the menu unreadably dark.
        window.orderFrontRegardless()
    }
    func refresh() {
        let ids = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        for id in Array(windows.keys) where !ids.contains(id) { remove(id) }
        for (id, value) in values { set(id, value: value) }
    }
    func remove(_ id: UInt32) { windows.removeValue(forKey: id)?.close(); values.removeValue(forKey: id) }
    func removeAll() { for id in Array(windows.keys) { remove(id) } }
}

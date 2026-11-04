import AppKit
import CoreGraphics
import DisplayBridge
import MonitorCore

@MainActor final class DisplayDriver: DisplayConfiguring {
    func displays() throws -> [DisplayInfo] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), "listar monitores")
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), "listar monitores")
        return ids.prefix(Int(count)).map { id in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let details = MBDisplayDetails(id) as? [String: Any]
            let names = details?["DisplayProductName"] as? [String: String]
            let current = CGDisplayCopyDisplayMode(id).map(Self.describe)
            var modes = Self.rawModes(id).map(Self.describe)
            if let current, !modes.contains(where: { $0.id == current.id }) { modes.append(current) }
            modes.sort { ($0.width, $0.height, $0.pixelWidth, $0.hz) > ($1.width, $1.height, $1.pixelWidth, $1.hz) }
            var seen = Set<Int>(); modes = modes.filter { seen.insert($0.id).inserted }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "display-\(id)"
            return DisplayInfo(id: id, identity: uuid,
                               name: screen?.localizedName ?? names?["pt_BR"] ?? names?["en_US"] ?? names?.values.first ?? "Monitor \(id)",
                               builtIn: CGDisplayIsBuiltin(id) != 0, main: CGDisplayIsMain(id) != 0,
                               bounds: CGDisplayBounds(id), mirror: CGDisplayMirrorsDisplay(id),
                               rotation: Int(CGDisplayRotation(id)), canRotate: MBCanRotate(id), current: current, modes: modes)
        }.sorted { ($0.main ? 0 : 1, $0.id) < ($1.main ? 0 : 1, $1.id) }
    }

    static func rawModes(_ id: UInt32) -> [CGDisplayMode] {
        CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary) as? [CGDisplayMode] ?? []
    }
    static func describe(_ mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(id: Int(mode.ioDisplayModeID), width: mode.width, height: mode.height,
                    pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, hz: mode.refreshRate)
    }

    func apply(_ settings: [DisplaySetting], permanently: Bool) async throws {
        let live = try displays()
        for setting in settings {
            guard live.contains(where: { $0.id == setting.id && $0.identity == setting.identity }) else {
                throw MonitorError.message("Um monitor foi desconectado. Atualize a disposição.")
            }
            if Int(CGDisplayRotation(setting.id)) != setting.rotation {
                guard MBSetRotation(setting.id, Int32(setting.rotation)) else {
                    throw MonitorError.message("Rotação indisponível para esta tela nesta versão do macOS.")
                }
                var rotated = false
                for _ in 0..<40 {
                    try await Task.sleep(for: .milliseconds(100))
                    if Int(CGDisplayRotation(setting.id)) == setting.rotation { rotated = true; break }
                }
                guard rotated else { throw MonitorError.message("O macOS não confirmou a rotação. Restaurando a configuração anterior.") }
            }
        }
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), "iniciar a configuração")
        var committed = false
        defer { if !committed { CGCancelDisplayConfiguration(config) } }
        // Set origins BEFORE mirroring: setting an origin breaks the display's mirror set.
        for setting in settings {
            try check(CGConfigureDisplayMirrorOfDisplay(config, setting.id, kCGNullDirectDisplay), "preparar o espelhamento")
            if let requested = setting.mode {
                let modes = Self.rawModes(setting.id)
                let mode = modes.first(where: { Int($0.ioDisplayModeID) == requested.id })
                    ?? modes.first(where: { $0.width == requested.width && $0.height == requested.height && $0.pixelWidth == requested.pixelWidth && abs($0.refreshRate - requested.hz) < 1 })
                guard let mode else { throw MonitorError.message("A resolução selecionada não está mais disponível.") }
                try check(CGConfigureDisplayWithDisplayMode(config, setting.id, mode, nil), "alterar a resolução")
            }
            if setting.mirror == 0 {
                try check(CGConfigureDisplayOrigin(config, setting.id, Int32(setting.origin.x.rounded()), Int32(setting.origin.y.rounded())), "posicionar o monitor")
            }
        }
        for setting in settings where setting.mirror != 0 {
            try check(CGConfigureDisplayMirrorOfDisplay(config, setting.id, setting.mirror), "espelhar o monitor")
        }
        // App-only previews are automatically dropped by WindowServer if the process exits.
        let result = CGCompleteDisplayConfiguration(config, permanently ? .permanently : .forAppOnly)
        committed = true
        try check(result, "aplicar a configuração")
    }
    private func check(_ result: CGError, _ operation: String) throws {
        if result != .success { throw MonitorError.message("Não foi possível \(operation) (macOS: \(result.rawValue)).") }
    }
}

@MainActor final class DemoDriver: DisplayConfiguring {
    var items: [DisplayInfo] = {
        let retina = DisplayMode(id: 1, width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800, hz: 60)
        let large = DisplayMode(id: 2, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, hz: 60)
        let smaller = DisplayMode(id: 3, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, hz: 60)
        return [DisplayInfo(id: 1, identity: "demo-1", name: "MacBook Air", builtIn: true, main: false,
                            bounds: CGRect(x: -1440, y: 540, width: 1440, height: 900), current: retina, modes: [retina]),
                DisplayInfo(id: 2, identity: "demo-2", name: "Studio Display", builtIn: false, main: true,
                            bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440), canRotate: true, current: large, modes: [large, smaller])]
    }()
    func displays() -> [DisplayInfo] { items }
    func apply(_ settings: [DisplaySetting], permanently: Bool) async throws {
        items = items.map { item in
            guard let setting = settings.first(where: { $0.id == item.id }) else { return item }
            let size = setting.mode.map { CGSize(width: $0.width, height: $0.height) } ?? item.bounds.size
            return DisplayInfo(id: item.id, identity: item.identity, name: item.name, builtIn: item.builtIn,
                               main: setting.origin == .zero && setting.mirror == 0, bounds: CGRect(origin: setting.origin, size: size),
                               mirror: setting.mirror, rotation: setting.rotation, canRotate: item.canRotate,
                               current: setting.mode, modes: item.modes)
        }
    }
}

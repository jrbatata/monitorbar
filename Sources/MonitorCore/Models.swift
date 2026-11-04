import Foundation
import CoreGraphics

public struct DisplayMode: Identifiable, Equatable, Codable, Sendable {
    public let id: Int
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hz: Double
    public var hiDPI: Bool { pixelWidth > width }
    public var resolutionKey: String { "\(width)x\(height)-\(pixelWidth)x\(pixelHeight)" }
    public var resolutionLabel: String { "\(width) × \(height)" + (hiDPI ? " · HiDPI" : "") }
    public var rateLabel: String { hz > 0 ? String(format: "%.0f Hz", hz) : "Padrão" }
    public init(id: Int, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, hz: Double) {
        self.id = id; self.width = width; self.height = height
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.hz = hz
    }
}

public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let identity: String
    public let name: String
    public let builtIn: Bool
    public let main: Bool
    public let bounds: CGRect
    public let mirror: UInt32
    public let rotation: Int
    public let canRotate: Bool
    public let current: DisplayMode?
    public let modes: [DisplayMode]
    public init(id: UInt32, identity: String, name: String, builtIn: Bool, main: Bool, bounds: CGRect,
                mirror: UInt32 = 0, rotation: Int = 0, canRotate: Bool = false, current: DisplayMode?, modes: [DisplayMode]) {
        self.id = id; self.identity = identity; self.name = name; self.builtIn = builtIn; self.main = main
        self.bounds = bounds; self.mirror = mirror; self.rotation = rotation; self.canRotate = canRotate
        self.current = current; self.modes = modes
    }
    public var resolutions: [DisplayMode] {
        var seen = Set<String>()
        return modes.filter { seen.insert($0.resolutionKey).inserted }
    }
}

public struct DisplaySetting: Codable, Equatable, Sendable {
    public var id: UInt32
    public var identity: String
    public var origin: CGPoint
    public var mode: DisplayMode?
    public var mirror: UInt32
    public var rotation: Int
    public init(_ display: DisplayInfo) {
        id = display.id; identity = display.identity; origin = display.bounds.origin
        mode = display.current; mirror = display.mirror; rotation = display.rotation
    }
}

public enum Layout {
    public static func makingMain(_ id: UInt32, in settings: [DisplaySetting]) -> [DisplaySetting] {
        guard let target = settings.first(where: { $0.id == id }), target.mirror == 0 else { return settings }
        return settings.map { item in
            var item = item
            item.origin.x -= target.origin.x; item.origin.y -= target.origin.y
            return item
        }
    }

    public static func snapped(_ rect: CGRect, to others: [CGRect], threshold: CGFloat) -> CGPoint {
        var point = rect.origin
        var dx = threshold, dy = threshold
        for other in others {
            // Only snap an edge if the perpendicular spans overlap or nearly touch.
            if rect.maxY >= other.minY - threshold && rect.minY <= other.maxY + threshold {
                for x in [other.minX - rect.width, other.maxX, other.minX, other.maxX - rect.width] {
                    if abs(x - rect.minX) < dx { dx = abs(x - rect.minX); point.x = x }
                }
            }
            if rect.maxX >= other.minX - threshold && rect.minX <= other.maxX + threshold {
                for y in [other.minY - rect.height, other.maxY, other.minY, other.maxY - rect.height] {
                    if abs(y - rect.minY) < dy { dy = abs(y - rect.minY); point.y = y }
                }
            }
        }
        return CGPoint(x: point.x.rounded(), y: point.y.rounded())
    }

    public static func validate(_ settings: [DisplaySetting]) throws {
        guard !settings.isEmpty else { throw MonitorError.message("Nenhum monitor disponível.") }
        let ids = Set(settings.map(\.id))
        guard ids.count == settings.count else { throw MonitorError.message("Monitores duplicados na configuração.") }
        for item in settings {
            guard item.origin.x.isFinite, item.origin.y.isFinite,
                  abs(item.origin.x) < 100_000, abs(item.origin.y) < 100_000 else {
                throw MonitorError.message("Posição de monitor inválida.")
            }
            if item.mirror != 0 {
                guard item.mirror != item.id, let target = settings.first(where: { $0.id == item.mirror }), target.mirror == 0 else {
                    throw MonitorError.message("Selecione uma tela estendida como origem do espelhamento.")
                }
            }
        }
        guard settings.contains(where: { $0.mirror == 0 && $0.origin == .zero }) else {
            throw MonitorError.message("A tela principal deve estar na origem da disposição.")
        }
    }
}

public enum MonitorError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

@MainActor public protocol DisplayConfiguring: AnyObject {
    func displays() throws -> [DisplayInfo]
    func apply(_ settings: [DisplaySetting], permanently: Bool) async throws
}

/// Keeps the original snapshot until both applying AND confirming have succeeded.
@MainActor public final class ConfigurationSession {
    public private(set) var original: [DisplaySetting]?
    public private(set) var proposed: [DisplaySetting]?
    public private(set) var deadline: Date?
    private let backend: DisplayConfiguring
    public init(backend: DisplayConfiguring) { self.backend = backend }

    public func preview(_ settings: [DisplaySetting]) async throws {
        guard original == nil else { throw MonitorError.message("Confirme ou reverta a alteração anterior.") }
        try Layout.validate(settings)
        original = try backend.displays().map(DisplaySetting.init)
        do {
            try await backend.apply(settings, permanently: false)
            proposed = try backend.displays().map(DisplaySetting.init)
            deadline = Date().addingTimeInterval(20)
        } catch {
            let applyError = error
            do { try await revert() }
            catch { throw MonitorError.message("Falha ao aplicar: \(applyError.localizedDescription). Falha ao restaurar: \(error.localizedDescription)") }
            throw applyError
        }
    }

    public func confirm() async throws {
        guard let proposed else { return }
        try await backend.apply(proposed, permanently: true)
        clear()
    }

    public func revert() async throws {
        guard let original else { return }
        let current = try backend.displays()
        // Restore only the same physical displays still attached, with remapped transient IDs.
        let mapped: [DisplaySetting] = original.compactMap { old in
            guard let live = current.first(where: { $0.identity == old.identity }) else { return nil }
            var item = old; item.id = live.id
            if old.mirror != 0 {
                let targetIdentity = original.first(where: { $0.id == old.mirror })?.identity
                item.mirror = current.first(where: { $0.identity == targetIdentity })?.id ?? 0
            }
            return item
        }
        if !mapped.isEmpty { try await backend.apply(mapped, permanently: false) }
        clear()
    }

    public func expired(at date: Date) -> Bool { deadline.map { date >= $0 } ?? false }
    private func clear() { original = nil; proposed = nil; deadline = nil }
}

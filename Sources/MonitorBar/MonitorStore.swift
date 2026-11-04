import AppKit
import Combine
import MonitorCore

@MainActor final class MonitorStore: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var brightness: [UInt32: BrightnessState] = [:]
    @Published var error: String?
    @Published var busy = false
    @Published var pending = false
    @Published var remaining = 20
    let demo: Bool
    let driver: DisplayConfiguring
    let session: ConfigurationSession
    let hardware = BrightnessHardware()
    let dimmers = DimmerController()
    var showConfirmation: (() -> Void)?
    var closeConfirmation: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var writes: [UInt32: Task<Void, Never>] = [:]
    private var probeGeneration = 0
    private var revertFailed = false
    private var journal: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MonitorBar/pending-configuration.json")
    }

    init(demo: Bool = false) {
        self.demo = demo
        driver = demo ? DemoDriver() : DisplayDriver()
        session = ConfigurationSession(backend: driver)
        if !demo {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func start() async {
        await recoverInterruptedConfiguration()
        await refresh()
    }
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
    func refresh() async {
        do {
            let fresh = try driver.displays()
            let oldIDs = Set(displays.map(\.identity)), newIDs = Set(fresh.map(\.identity))
            displays = fresh
            if !demo { dimmers.refresh() }
            if pending, oldIDs != newIDs, !busy {
                error = "As telas conectadas mudaram. Restaurando as telas ainda disponíveis."
                await revert()
            }
            // Cancel delayed writes before re-associating transient IDs with hardware.
            for task in writes.values { task.cancel() }
            writes.removeAll()
            probeGeneration += 1
            let generation = probeGeneration
            if demo {
                for display in fresh where brightness[display.id] == nil { brightness[display.id] = BrightnessState(value: display.builtIn ? 0.65 : 0.8, method: .native) }
                return
            }
            let values = await hardware.probe(fresh)
            guard generation == probeGeneration else { return }
            brightness = values.merging(brightness.filter { values[$0.key] != nil && $0.value.method == .dimmer }) { _, dimmer in dimmer }
        } catch { self.error = error.localizedDescription }
    }
    func setBrightness(_ display: DisplayInfo, _ value: Double) {
        guard var state = brightness[display.id], ![.unsupported, .probing].contains(state.method) else { return }
        let previous = state.value
        state.value = value; brightness[display.id] = state
        if demo { return }
        if state.method == .dimmer { dimmers.set(display.id, value: value); return }
        writes[display.id]?.cancel()
        let method = state.method, generation = probeGeneration
        writes[display.id] = Task {
            do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
            guard generation == probeGeneration else { return }
            let success = await hardware.set(display.id, method: method, value: value)
            guard !Task.isCancelled, generation == probeGeneration else { return }
            if !success {
                brightness[display.id] = BrightnessState(value: previous, method: .unsupported)
                error = "\(display.name) não respondeu ao ajuste de brilho. Você pode ativar o dimmer por software."
            }
        }
    }
    func enableDimmer(_ display: DisplayInfo) {
        brightness[display.id] = BrightnessState(value: 1, method: .dimmer)
        if !demo { dimmers.set(display.id, value: 1) }
    }
    func disableDimmer(_ display: DisplayInfo) {
        dimmers.remove(display.id)
        brightness[display.id] = BrightnessState(method: .unsupported)
        Task { await refresh() }
    }
    var settings: [DisplaySetting] { displays.map(DisplaySetting.init) }

    func preview(_ proposed: [DisplaySetting]) async {
        guard !busy, !pending else { return }
        busy = true; error = nil; revertFailed = false
        do {
            try saveJournal(settings)
            try await session.preview(proposed)
            pending = true; remaining = 20
            showConfirmation?()
        } catch {
            self.error = error.localizedDescription
            if session.original == nil { clearJournal() }
            else { pending = true; revertFailed = true; showConfirmation?() }
        }
        busy = false
        await refresh()
    }
    func confirm() async {
        guard !busy else { return }; busy = true
        do {
            try await session.confirm()
            if session.original == nil { finish() }
        } catch { self.error = error.localizedDescription }
        busy = false
    }
    func revert() async {
        guard !busy else { return }; busy = true
        do { try await session.revert(); finish() }
        catch { self.error = error.localizedDescription; revertFailed = true }
        busy = false
        do { displays = try driver.displays() } catch { self.error = error.localizedDescription }
    }
    private func finish() { pending = false; revertFailed = false; clearJournal(); closeConfirmation?() }
    private func tick() {
        guard pending else { return }
        if let deadline = session.deadline { remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))) }
        if session.expired(at: Date()), !busy, !revertFailed { Task { await revert() } }
    }
    func changeMode(_ display: DisplayInfo, _ mode: DisplayMode) async {
        var proposed = settings
        guard let index = proposed.firstIndex(where: { $0.id == display.id }) else { return }
        proposed[index].mode = mode
        await preview(proposed)
    }
    func rotate(_ display: DisplayInfo, _ angle: Int) async {
        var proposed = settings
        guard let index = proposed.firstIndex(where: { $0.id == display.id }) else { return }
        proposed[index].rotation = angle
        proposed[index].mode = nil // Rotating changes the mode catalogue; let macOS choose its native counterpart.
        await preview(proposed)
    }
    func mirror(_ display: DisplayInfo, target: UInt32) async {
        var proposed = settings
        guard let index = proposed.firstIndex(where: { $0.id == display.id }) else { return }
        if target != 0 {
            // A display with dependents cannot itself become a mirror.
            for i in proposed.indices where proposed[i].mirror == display.id { proposed[i].mirror = target }
            if display.main { proposed = Layout.makingMain(target, in: proposed) }
            proposed[index].mirror = target
        } else {
            proposed[index].mirror = 0
            if let main = displays.first(where: \.main) { proposed[index].origin = CGPoint(x: main.bounds.maxX, y: 0) }
        }
        await preview(proposed)
    }
    private func saveJournal(_ settings: [DisplaySetting]) throws {
        guard !demo else { return }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: journal, options: .atomic)
    }
    private func clearJournal() { if !demo { try? FileManager.default.removeItem(at: journal) } }
    private func recoverInterruptedConfiguration() async {
        guard !demo, FileManager.default.fileExists(atPath: journal.path) else { return }
        do {
            let saved = try JSONDecoder().decode([DisplaySetting].self, from: Data(contentsOf: journal))
            let live = try driver.displays()
            let restore = saved.compactMap { old -> DisplaySetting? in
                guard let display = live.first(where: { $0.identity == old.identity }) else { return nil }
                var value = old; value.id = display.id
                let targetIdentity = saved.first(where: { $0.id == old.mirror })?.identity
                value.mirror = live.first(where: { $0.identity == targetIdentity })?.id ?? 0
                return value
            }
            if !restore.isEmpty { try await driver.apply(restore, permanently: false) }
            clearJournal()
        } catch { self.error = "Não foi possível recuperar a última prévia: \(error.localizedDescription)" }
    }
    func stop() async {
        if pending { await revert() }
        dimmers.removeAll()
    }
}

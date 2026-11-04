import SwiftUI
import AppKit

@main enum EntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--render-store-assets") {
            StoreAssetsRenderer.run()
        } else if CommandLine.arguments.contains("--render-preview") {
            PreviewRenderer.run()
        } else {
            MonitorBarApp.main()
        }
    }
}

struct MonitorBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("MonitorBar", systemImage: "display.2") {
            QuickPanel(launchAtLogin: delegate.launchAtLogin, store: delegate.store, organize: { delegate.windows.showOrganizer() })
                .onAppear { Task { await delegate.store.refresh() } }
        }.menuBarExtraStyle(.window)
    }
}

@MainActor enum PreviewRenderer {
    static func run() {
        let store = MonitorStore(demo: true)
        store.displays = (try? store.driver.displays()) ?? []
        for display in store.displays { store.brightness[display.id] = BrightnessState(value: display.builtIn ? 0.65 : 0.8, method: .native) }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        save(QuickPanel(launchAtLogin: LaunchAtLogin(), store: store, organize: {}), size: CGSize(width: 390, height: 740), to: output.appendingPathComponent("preview-menu.png"))
        save(QuickPanel(launchAtLogin: LaunchAtLogin(), store: store, organize: {}), size: CGSize(width: 390, height: 740), to: output.appendingPathComponent("preview-menu-light.png"), scheme: .light)
        save(ArrangementView(store: store), size: CGSize(width: 880, height: 640), to: output.appendingPathComponent("preview-arrangement.png"))
    }
    static func save<V: View>(_ view: V, size: CGSize, to url: URL, scheme: ColorScheme = .dark) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.frame = CGRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MonitorStore(demo: CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-preview"))
    let launchAtLogin = LaunchAtLogin()
    lazy var windows = WindowCoordinator(store: store)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !CommandLine.arguments.contains("--render-preview") { launchAtLogin.enableByDefaultOnFirstRun() }
        store.showConfirmation = { [weak self] in self?.windows.showConfirmation() }
        store.closeConfirmation = { [weak self] in self?.windows.closeConfirmation() }
        Task {
            await store.start()
            if CommandLine.arguments.contains("--organize") { windows.showOrganizer() }
            if CommandLine.arguments.contains("--diagnostics") {
                for display in store.displays {
                    print("\(display.name): \(display.id), \(display.current?.resolutionLabel ?? "sem modo"), brilho: \(store.brightness[display.id]?.method.rawValue ?? "desconhecido"), rotação: \(display.canRotate)")
                }
                print("Monitores detectados: \(store.displays.count)")
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !store.busy else { return .terminateCancel }
        Task { await store.stop(); NSApp.reply(toApplicationShouldTerminate: !store.pending) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showOrganizer(); return false
    }
}

@MainActor final class WindowCoordinator: NSObject, NSWindowDelegate {
    let store: MonitorStore
    private var organizer: NSWindow?
    private var confirmation: NSWindow?
    init(store: MonitorStore) { self.store = store }
    func showOrganizer() {
        if organizer == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Organizar monitores · MonitorBar"
            window.contentView = NSHostingView(rootView: ArrangementView(store: store))
            window.minSize = NSSize(width: 780, height: 570)
            window.isReleasedWhenClosed = false; window.center(); organizer = window
        }
        NSApp.activate(ignoringOtherApps: true); organizer?.makeKeyAndOrderFront(nil)
    }
    func showConfirmation() {
        if confirmation == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Confirmar alteração"
            window.contentView = NSHostingView(rootView: ConfirmationView(store: store))
            window.isReleasedWhenClosed = false; window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            confirmation = window
        }
        confirmation?.center(); NSApp.activate(ignoringOtherApps: true); confirmation?.makeKeyAndOrderFront(nil)
    }
    func closeConfirmation() { confirmation?.orderOut(nil) }
}

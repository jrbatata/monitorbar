import SwiftUI
import Sparkle

/// Thin wrapper around Sparkle's standard updater (checks automatically and from the menu).
@MainActor final class Updater: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published var canCheck = true
    private var observation: NSKeyValueObservation?
    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }
    func check() { NSApp.activate(ignoringOtherApps: true); controller.checkForUpdates(nil) }
}

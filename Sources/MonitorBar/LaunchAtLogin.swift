import ServiceManagement
import SwiftUI

/// Controla a abertura automática do app ao iniciar a sessão (macOS 13+).
@MainActor final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    private let configuredKey = "launchAtLogin.configured"

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    /// Na primeira execução, ativa por padrão. Depois disso respeita a escolha do usuário.
    func enableByDefaultOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { refresh(); return }
        UserDefaults.standard.set(true, forKey: configuredKey)
        set(true)
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MonitorBar: falha ao alterar início automático: \(error.localizedDescription)")
        }
        refresh()
    }
}

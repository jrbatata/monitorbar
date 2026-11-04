import SwiftUI
import MonitorCore

// Opaque surfaces keep contrast stable over any desktop wallpaper.
private enum MonitorTheme {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(light: 0xF0F4FA, dark: 0x151D2B)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x242E40)
    static let primary = adaptive(light: 0x162237, dark: 0xF5F8FF)
    static let secondary = adaptive(light: 0x4D5D73, dark: 0xBDCBE0)
    static let border = adaptive(light: 0xC9D4E4, dark: 0x53647D)
    static let badge = adaptive(light: 0xE5EDF9, dark: 0x35445D)
    static let accent = adaptive(light: 0x005DBB, dark: 0x78C1FF)
    static let tint = Color(red: 0.04, green: 0.43, blue: 0.89)
    static let action = LinearGradient(colors: [Color(red: 0.035, green: 0.39, blue: 0.82),
                                               Color(red: 0.07, green: 0.30, blue: 0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}
private let accent = MonitorTheme.accent

private struct MonitorListHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct QuickPanel: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var store: MonitorStore
    var organize: () -> Void
    @State private var contentHeight: CGFloat = 300
    @State private var availableScreenHeight: CGFloat = 800

    private var listHeight: CGFloat {
        // Reserve room for the header, actions, menu-bar margins and optional banners.
        let chrome: CGFloat = 240 + (store.pending ? 44 : 0)
        let limit = max(80, min(560, availableScreenHeight - chrome))
        return min(max(1, contentHeight), limit)
    }
    private func updateScreenHeight() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        availableScreenHeight = screen?.visibleFrame.height ?? 800
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display.2").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MonitorBar").font(.headline)
                    Text("Seu espaço, do seu jeito.").font(.caption).foregroundStyle(MonitorTheme.secondary)
                }
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                else { Text("\(store.displays.count) \(store.displays.count == 1 ? "tela" : "telas")").font(.caption).foregroundStyle(MonitorTheme.secondary) }
            }.padding(18)
            Divider()
            if store.pending {
                Button("Confirmar alteração · \(store.remaining)s") { store.showConfirmation?() }
                    .buttonStyle(.borderedProminent).tint(MonitorTheme.tint).padding(.top, 12)
            }
            ScrollView {
                VStack(spacing: 12) {
                    if store.displays.isEmpty {
                        ContentUnavailableView("Nenhuma tela disponível", systemImage: "display.trianglebadge.exclamationmark", description: Text("Abra o app em uma sessão gráfica do macOS."))
                    }
                    ForEach(Array(store.displays.enumerated()), id: \.element.id) { index, display in
                        DisplayCard(store: store, display: display, number: index + 1)
                    }
                    ErrorBanner(store: store)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MonitorListHeight.self, value: proxy.size.height)
                    }
                }
            }
            // A ScrollView has no useful intrinsic height. A maxHeight alone lets
            // MenuBarExtra compress it to a tiny viewport during fitting-size layout.
            .frame(height: listHeight)
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(MonitorListHeight.self) { measured in
                guard measured.isFinite, measured > 0, abs(measured - contentHeight) > 0.5 else { return }
                contentHeight = measured.rounded(.up)
            }
            Divider()
            Button(action: organize) {
                HStack { Image(systemName: "rectangle.3.group"); Text("Organizar monitores"); Spacer(); Image(systemName: "arrow.up.right") }
                    .foregroundStyle(.white)
                    .padding(12).background(MonitorTheme.action, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
            }.buttonStyle(.plain).padding(14)
            HStack {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Atualizar monitores")
                Button("Ajustes do macOS") { openDisplaySettings() }
                Spacer()
                Toggle("Iniciar com o Mac", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                    .toggleStyle(.checkbox).help(launchAtLogin.needsApproval ? "Aprove em Ajustes do Sistema › Geral › Itens de Login" : "Abrir o MonitorBar ao iniciar a sessão")
                Button("Sair") { NSApp.terminate(nil) }.disabled(store.busy)
            }.buttonStyle(.borderless).font(.caption).foregroundStyle(MonitorTheme.secondary).padding([.horizontal, .bottom], 18)
        }
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(MonitorTheme.primary)
        .background(MonitorTheme.background).tint(MonitorTheme.tint)
        .onAppear { updateScreenHeight() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateScreenHeight()
        }
    }
}

struct DisplayCard: View {
    @ObservedObject var store: MonitorStore
    let display: DisplayInfo
    let number: Int
    var state: BrightnessState { store.brightness[display.id] ?? BrightnessState() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: display.builtIn ? "laptopcomputer" : "display")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(accent).frame(width: 35)
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(display.main ? "Tela principal" : display.mirror != 0 ? "Espelhada" : "Tela estendida")
                        .font(.caption).foregroundStyle(MonitorTheme.secondary)
                }
                Spacer()
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(MonitorTheme.secondary)
                    .padding(6).background(MonitorTheme.badge, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(state.method.rawValue).font(.caption).foregroundStyle(MonitorTheme.secondary)
                    Spacer()
                    if state.method != .unsupported && state.method != .probing {
                        Text("\(Int(state.value * 100))% ").font(.caption.monospacedDigit())
                    }
                }
                if state.method == .unsupported {
                    Text("O monitor não oferece controle de brilho nesta conexão.").font(.caption).foregroundStyle(MonitorTheme.secondary)
                    Button("Usar dimmer por software") { store.enableDimmer(display) }.font(.caption)
                } else if state.method == .probing {
                    ProgressView().controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").foregroundStyle(MonitorTheme.secondary)
                        Slider(value: Binding(get: { state.value }, set: { store.setBrightness(display, $0) }), in: (state.method == .dimmer ? 0.2 : 0.05)...1)
                            .accessibilityLabel("Brilho de \(display.name)")
                        Image(systemName: "sun.max.fill").foregroundStyle(accent)
                    }
                    if state.method == .dimmer {
                        HStack {
                            Text("Escurece a imagem, não a iluminação.").font(.caption2).foregroundStyle(MonitorTheme.secondary)
                            Spacer()
                            Button("Desativar") { store.disableDimmer(display) }.font(.caption2)
                        }
                    }
                }
            }
            VStack(spacing: 8) {
                HStack {
                    Text("Escala / resolução").font(.caption).foregroundStyle(MonitorTheme.secondary)
                    Spacer()
                    Menu {
                        ForEach(display.resolutions) { mode in
                            Button(mode.resolutionLabel) {
                                let choices = display.modes.filter { $0.resolutionKey == mode.resolutionKey }
                                let best = choices.min { abs($0.hz - (display.current?.hz ?? 60)) < abs($1.hz - (display.current?.hz ?? 60)) } ?? mode
                                Task { await store.changeMode(display, best) }
                            }
                        }
                    } label: { Text(display.current?.resolutionLabel ?? "Indisponível").font(.caption) }
                    .menuStyle(.borderlessButton).tint(accent).accentColor(accent).foregroundStyle(accent).fixedSize()
                    .disabled(store.busy || store.pending || display.mirror != 0 || display.modes.isEmpty)
                }
                HStack {
                    Menu {
                        ForEach(display.modes.filter { $0.resolutionKey == display.current?.resolutionKey }) { mode in
                            Button(mode.rateLabel) { Task { await store.changeMode(display, mode) } }
                        }
                    } label: { Label(display.current?.rateLabel ?? "Hz", systemImage: "waveform.path") }
                    .disabled(store.busy || store.pending || display.mirror != 0)
                    Spacer()
                    Menu {
                        if display.canRotate {
                            ForEach([0, 90, 180, 270], id: \.self) { angle in
                                Button("\(angle)°") { Task { await store.rotate(display, angle) } }
                            }
                        } else { Button("Ajustar no macOS…") { openDisplaySettings() } }
                    } label: { Label("\(display.rotation)°", systemImage: "rotate.right") }
                    .disabled(store.busy || store.pending || display.mirror != 0)
                    Spacer()
                    Menu {
                        if !display.main && display.mirror == 0 {
                            Button("Definir como principal") { Task { await store.preview(Layout.makingMain(display.id, in: store.settings)) } }
                        }
                        if display.mirror != 0 {
                            Button("Usar como tela estendida") { Task { await store.mirror(display, target: 0) } }
                        }
                        ForEach(store.displays.filter { $0.id != display.id && $0.mirror == 0 }) { other in
                            Button("Espelhar \(other.name)") { Task { await store.mirror(display, target: other.id) } }
                        }
                    } label: { Text("Usar como") }
                    .disabled(store.busy || store.pending || store.displays.count < 2)
                }.font(.caption).menuStyle(.borderlessButton).tint(accent).accentColor(accent).foregroundStyle(accent)
            }
        }.padding(14).background(MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(MonitorTheme.border))
    }
}

struct ArrangementView: View {
    @ObservedObject var store: MonitorStore
    @State private var draft: [DisplaySetting] = []
    @State private var selected: UInt32?
    @State private var dragStart: CGPoint?
    @State private var dragBounds: CGRect?
    @State private var dirty = false
    @State private var mainID: UInt32?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Tudo no lugar.").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Arraste as telas para acompanhar sua mesa. As bordas se encaixam automaticamente.")
                        .font(.callout).foregroundStyle(MonitorTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image(systemName: "rectangle.3.group").font(.system(size: 29, weight: .light)).foregroundStyle(accent)
            }
            HStack {
                Label("\(store.displays.count) monitores conectados", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(accent)
                Spacer()
                Text(dirty ? "Alterações ainda não aplicadas" : "Disposição atual").font(.caption).foregroundStyle(MonitorTheme.secondary)
            }
            canvas.frame(minHeight: 250)
            HStack(spacing: 14) {
                if let display = store.displays.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name).font(.headline)
                        Text(display.current?.resolutionLabel ?? "").font(.caption).foregroundStyle(MonitorTheme.secondary)
                    }
                    Spacer()
                    if display.mirror != 0 {
                        Button("Usar como estendida") { Task { await store.mirror(display, target: 0) } }.disabled(store.busy || store.pending)
                    } else {
                        Button(mainID == display.id ? "Tela principal" : "Definir como principal") {
                            draft = Layout.makingMain(display.id, in: draft); mainID = display.id; dirty = true
                        }.disabled(mainID == display.id || store.busy || store.pending)
                    }
                } else {
                    Text("Selecione uma tela para ver os detalhes.").foregroundStyle(MonitorTheme.secondary)
                    Spacer()
                }
            }.frame(height: 43)
            ErrorBanner(store: store)
            Divider()
            HStack(alignment: .center, spacing: 16) {
                Text("Você terá 20 segundos para confirmar.\nSem confirmação, a alteração será desfeita.")
                    .font(.caption).foregroundStyle(MonitorTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Restaurar prévia") { resetDraft() }.disabled(!dirty || store.pending || store.busy)
                    .fixedSize()
                Button(store.pending ? "Confirmar…" : "Aplicar disposição") {
                    if store.pending { store.showConfirmation?() }
                    else { Task { await store.preview(draft); if store.pending { dirty = false } } }
                }.buttonStyle(.borderedProminent).tint(MonitorTheme.tint)
                    .fixedSize()
                    .disabled(store.busy || (!dirty && !store.pending))
            }
        }.padding(28).frame(minWidth: 724, minHeight: 510).foregroundStyle(MonitorTheme.primary)
        .background(MonitorTheme.background).tint(MonitorTheme.tint)
        .onAppear { resetDraft() }
        .onChange(of: store.displays) { _, _ in
            // Never keep a draft whose transient IDs or source geometry have changed externally.
            resetDraft()
        }
    }
    private func resetDraft() {
        draft = store.settings; mainID = store.displays.first(where: \.main)?.id
        if !store.displays.contains(where: { $0.id == selected }) { selected = mainID ?? store.displays.first?.id }
        dirty = false
    }
    private var canvas: some View {
        GeometryReader { geometry in
            let active = store.displays.filter { $0.mirror == 0 }
            let rectangles = active.map { display in CGRect(origin: draft.first(where: { $0.id == display.id })?.origin ?? display.bounds.origin, size: display.bounds.size) }
            let bounds = rectangles.reduce(CGRect.null) { $0.union($1) }
            let safeBounds = dragBounds ?? (bounds.isNull || bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1920, height: 1080) : bounds)
            let scale = min((geometry.size.width - 110) / max(safeBounds.width, 1), (geometry.size.height - 100) / max(safeBounds.height, 1), 0.18)
            let offset = CGPoint(x: (geometry.size.width - safeBounds.width * scale) / 2 - safeBounds.minX * scale,
                                 y: (geometry.size.height - safeBounds.height * scale) / 2 - safeBounds.minY * scale)
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.025))
                Canvas { context, size in
                    for x in stride(from: CGFloat(16), to: size.width, by: 20) {
                        for y in stride(from: CGFloat(16), to: size.height, by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.18)))
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 16))
                if store.displays.isEmpty { Text("Conecte um monitor para organizar as telas.").foregroundStyle(MonitorTheme.secondary) }
                ForEach(Array(active.enumerated()), id: \.element.id) { index, display in
                    let origin = draft.first(where: { $0.id == display.id })?.origin ?? display.bounds.origin
                    let width = display.bounds.width * scale, height = display.bounds.height * scale
                    VStack(spacing: 6) {
                        if mainID == display.id { Capsule().fill(.white.opacity(0.85)).frame(height: 4).padding(.horizontal, 10).padding(.top, 7) }
                        Spacer(minLength: 2)
                        Text("\(index + 1)").font(.system(size: min(32, height * 0.28), weight: .light, design: .rounded))
                        Text(display.name).font(.system(size: 10, weight: .medium)).lineLimit(1).padding(.horizontal, 5)
                        if store.displays.contains(where: { $0.mirror == display.id }) { Image(systemName: "rectangle.on.rectangle").font(.caption) }
                        Spacer(minLength: 4)
                    }.foregroundStyle(.white)
                        .frame(width: max(width, 35), height: max(height, 35))
                        .background(LinearGradient(colors: mainID == display.id ? [Color(red: 0.04, green: 0.40, blue: 0.82), Color(red: 0.07, green: 0.24, blue: 0.59)] : [Color(red: 0.29, green: 0.35, blue: 0.47), Color(red: 0.13, green: 0.17, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected == display.id ? accent : .white.opacity(0.25), lineWidth: selected == display.id ? 2 : 1))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 5)
                        .position(x: offset.x + (origin.x + display.bounds.width / 2) * scale,
                                  y: offset.y + (origin.y + display.bounds.height / 2) * scale)
                        .onTapGesture { selected = display.id }
                        .gesture(DragGesture().onChanged { value in
                            guard !store.busy, !store.pending, let i = draft.firstIndex(where: { $0.id == display.id }) else { return }
                            selected = display.id
                            if dragStart == nil { dragStart = draft[i].origin; dragBounds = safeBounds }
                            let start = dragStart ?? origin
                            let proposed = CGRect(origin: CGPoint(x: start.x + value.translation.width / scale, y: start.y + value.translation.height / scale), size: display.bounds.size)
                            let others = active.filter { $0.id != display.id }.map { other in
                                CGRect(origin: draft.first(where: { $0.id == other.id })?.origin ?? other.bounds.origin, size: other.bounds.size)
                            }
                            draft[i].origin = Layout.snapped(proposed, to: others, threshold: 12 / scale); dirty = true
                        }.onEnded { _ in
                            dragStart = nil; dragBounds = nil
                            if let mainID { draft = Layout.makingMain(mainID, in: draft) }
                        })
                        .accessibilityLabel("\(display.name), \(mainID == display.id ? "principal" : "estendida")")
                }
            }
        }
    }
}

struct ConfirmationView: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "display.trianglebadge.exclamationmark").font(.largeTitle).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ficou tudo certo?").font(.headline)
                    Text(store.session.deadline == nil ? "Use Reverter agora para tentar restaurar." : "Revertendo em \(store.remaining) segundos.").foregroundStyle(MonitorTheme.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ErrorBanner(store: store)
            HStack {
                Button("Reverter agora") { Task { await store.revert() } }.keyboardShortcut(.cancelAction)
                Button("Manter alterações") { Task { await store.confirm() } }
                    .buttonStyle(.borderedProminent).tint(MonitorTheme.tint).keyboardShortcut(.defaultAction)
                    .disabled(store.session.proposed == nil)
            }.disabled(store.busy)
        }.padding(24).frame(width: 392).fixedSize(horizontal: false, vertical: true)
    }
}

struct ErrorBanner: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        if let error = store.error {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(error).font(.caption).textSelection(.enabled)
                Spacer(minLength: 2)
                Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Fechar aviso")
            }.padding(10).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

func openDisplaySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") { NSWorkspace.shared.open(url) }
}

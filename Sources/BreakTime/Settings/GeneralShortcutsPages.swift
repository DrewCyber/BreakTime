import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox

// MARK: - General page

/// Curated status item icons (SF Symbols), in the spirit of the original's picker.
enum StatusIconChoice: String, CaseIterable, Identifiable {
    case none
    case timer, timerMedium, timerDark
    case palmTree, umbrella, tree, leaf, sun, cup, waves, pause
    case walking, cardio, strength, flexibility, mind, cooldown

    var id: String { rawValue }

    var symbolName: String? {
        switch self {
        case .none: return nil
        case .timer: return "timer"
        case .timerMedium: return "timer"
        case .timerDark: return "timer"
        case .palmTree: return "tree"
        case .umbrella: return "umbrella"
        case .tree: return "tree.fill"
        case .leaf: return "leaf"
        case .sun: return "sun.max"
        case .cup: return "cup.and.saucer"
        case .waves: return "water.waves"
        case .pause: return "pause"
        case .walking: return "figure.walk"
        case .cardio: return "figure.run"
        case .strength: return "figure.strengthtraining.traditional"
        case .flexibility: return "figure.flexibility"
        case .mind: return "figure.mind.and.body"
        case .cooldown: return "figure.cooldown"
        }
    }

    var label: String {
        switch self {
        case .none: return "No Icon"
        case .timer: return "Light App Icon"
        case .timerMedium: return "Medium App Icon"
        case .timerDark: return "Dark App Icon"
        case .palmTree: return "Palm Tree"
        case .umbrella: return "Beach Umbrella"
        case .tree: return "Tree"
        case .leaf: return "Leaf"
        case .sun: return "Sun on Horizon"
        case .cup: return "Cup and Saucer"
        case .waves: return "Water Waves"
        case .pause: return "Pause"
        case .walking: return "Walking"
        case .cardio: return "Mixed Cardio"
        case .strength: return "Strength Training"
        case .flexibility: return "Flexibility"
        case .mind: return "Mind and Body"
        case .cooldown: return "Cooldown"
        }
    }

    var iconAlpha: Double {
        switch self {
        case .timer: return 0.45
        case .timerMedium: return 0.7
        case .timerDark: return 1.0
        default: return 1.0
        }
    }

    static func fromSymbol(_ symbol: String) -> StatusIconChoice {
        allCases.first { $0.rawValue == symbol } ?? .timer
    }
}

struct GeneralPage: View {
    @EnvironmentObject var store: Store

    @State private var loginError: String?

    var body: some View {
        TabForm {
            // Login item — no divider, description text under settings
            Toggle("Automatically start BreakTime when you log in to this computer",
                   isOn: loginBinding)
            if let error = loginError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Dock
            Picker("", selection: dockBinding) {
                Text("Show the BreakTime icon in the Dock").tag(true)
                Text("Don't include BreakTime in the Dock").tag(false)
            }
            .pickerStyle(.radioGroup)
            VStack(alignment: .leading, spacing: 6) {
                Text("It appears in the Dock and the Cmd-Tab app switcher, with its own menus. Clicking the menu bar status item opens this Settings window.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .opacity(store.settings.showDockIcon ? 1 : 0.4)
                Text("It stays out of the Dock and the app switcher. Clicking the menu bar status item shows break info and options in a panel, and you can click an item to edit it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .opacity(store.settings.showDockIcon ? 0.4 : 1)
            }
            .frame(maxWidth: 520, alignment: .leading)

            // Menu bar status
            Toggle("Show BreakTime status in the menu bar",
                   isOn: Binding(
                    get: { store.settings.labelMode != .onlyIcon },
                    set: { store.settings.labelMode = $0 ? .countdownBrief : .onlyIcon }))
            Text("The status item can also display a label with the time of your next or last break, next to the icon.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if store.settings.labelMode != .onlyIcon {
                HStack(spacing: 10) {
                    Picker("", selection: $store.settings.labelMode) {
                        ForEach(MenuBarLabelMode.allCases.filter { $0 != .onlyIcon }) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 290)
                }
                .padding(.leading, 14)
            }

            HStack(spacing: 10) {
                iconPicker
                    .padding(.leading, 14)
            }
            Text("Pick the icon shown in the menu bar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 14)

            Toggle("Only include long breaks", isOn: $store.settings.onlyLongBreaksInMenuBar)
                .padding(.leading, 14)
            Text("Skips Micro breaks in the menu bar label.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 14)

            // Sidebar times
            Text("In the list of breaks, display next due using:")
                .font(.system(size: 13))
            Picker("", selection: $store.settings.relativeTimesInSidebar) {
                Text("Absolute dates").tag(false)
                Text("Relative times").tag(true)
            }
            .pickerStyle(.radioGroup)
            .padding(.leading, 14)
        }
    }

    /// The icon picker dropdown, grouped like the reference menu.
    private var iconPicker: some View {
        Menu {
            ForEach([StatusIconChoice.none, .timer, .timerMedium, .timerDark]) { choice in
                iconItem(choice)
            }
            Divider()
            ForEach([StatusIconChoice.palmTree, .umbrella, .tree, .leaf,
                     .sun, .cup, .waves, .pause]) { choice in
                iconItem(choice)
            }
            Divider()
            ForEach([StatusIconChoice.walking, .cardio, .strength,
                     .flexibility, .mind, .cooldown]) { choice in
                iconItem(choice)
            }
        } label: {
            HStack(spacing: 4) {
                if let symbol = StatusIconChoice.fromSymbol(store.settings.statusBarIcon).symbolName {
                    Image(systemName: symbol)
                        .foregroundStyle(.forestGreen)
                }
                Text("App Icon")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func iconItem(_ choice: StatusIconChoice) -> some View {
        Button {
            store.settings.statusBarIcon = choice.rawValue
        } label: {
            if let symbol = choice.symbolName {
                Label(choice.label, systemImage: symbol)
            } else {
                Text(choice.label)
            }
        }
    }

    private var dockBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showDockIcon },
            set: { newValue in
                store.settings.showDockIcon = newValue
                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            })
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { newValue in
                store.settings.launchAtLogin = newValue
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                } catch {
                    loginError = "Could not update the login item: \(error.localizedDescription)"
                    store.settings.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            })
    }
}

// MARK: - Shortcuts page

struct ShortcutsPage: View {
    @EnvironmentObject var store: Store

    @State private var recordingAction: ShortcutAction?

    var body: some View {
        TabForm {
            Text("Optional keyboard shortcuts that work from any app.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(ShortcutAction.allCases) { action in
                SettingsRow(action.label) {
                    RecordShortcutButton(
                        spec: specBinding(action),
                        isRecording: recordingAction == action) {
                            recordingAction = action
                        } onStop: {
                            recordingAction = nil
                        }
                }
            }
        }
        .onDisappear { HotKeysBridge.refresh() }
    }

    private func specBinding(_ action: ShortcutAction) -> Binding<ShortcutSpec> {
        Binding(
            get: { store.settings.shortcuts[action.rawValue] ?? ShortcutSpec() },
            set: { store.settings.shortcuts[action.rawValue] = $0.isSet ? $0 : nil
                   HotKeysBridge.refresh() })
    }
}

// MARK: - Record button

struct RecordShortcutButton: View {
    @Binding var spec: ShortcutSpec
    let isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if spec.isSet {
                Text(HotKeyCenter.displayString(keyCode: spec.keyCode, modifiers: spec.modifiers))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06)))
                Button {
                    spec = ShortcutSpec()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this shortcut")
            }

            Button(isRecording ? "Press keys…" : "Record Shortcut") {
                if isRecording {
                    onStop()
                } else {
                    onStart()
                }
            }
            .buttonStyle(.bordered)
            .disabled(spec.isSet)
        }
        .background(recordingCapture)
    }

    /// Local event monitor that captures the next key combination while recording.
    private var recordingCapture: some View {
        Group {
            if isRecording {
                RecorderSink(onCapture: { keyCode, modifiers in
                    spec = ShortcutSpec(keyCode: keyCode, modifiers: modifiers)
                    onStop()
                }, onCancel: {
                    onStop()
                })
            }
        }
    }
}

/// Invisible helper view that installs/removes the NSEvent monitor.
private struct RecorderSink: View {
    let onCapture: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                    let mods = event.modifierFlags
                        .intersection(.deviceIndependentFlagsMask)
                    if event.keyCode == kVK_Escape {
                        onCancel()
                        return nil
                    }
                    let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                    guard !mods.intersection(mask).isEmpty else { return event }
                    onCapture(UInt32(event.keyCode), HotKeyCenter.carbonModifiers(from: mods))
                    return nil
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }
}

// MARK: - Hot keys bridge (rebuilds Carbon registrations from settings)

enum HotKeysBridge {
    static func refresh() {
        let specs = Store.shared.settings.shortcuts
        guard !specs.isEmpty, let scheduler = AppDelegate.shared?.scheduler else {
            HotKeyCenter.shared.update([:], handlers: [:])
            return
        }

        var handlers: [String: () -> Void] = [:]
        handlers[ShortcutAction.startNormal.rawValue] = {
            if let normal = Store.shared.breaks.first(where: { $0.kind == .normal && $0.enabled })
                ?? Store.shared.breaks.first(where: { $0.enabled }) {
                scheduler.beginBreak(normal.id)
            }
        }
        handlers[ShortcutAction.startNext.rawValue] = {
            if let next = scheduler.nextBreakInfo() {
                scheduler.beginBreak(next.cfg.id)
            }
        }
        handlers[ShortcutAction.postponeNext1.rawValue] = {
            if let next = scheduler.nextBreakInfo() ?? currentOrNext(scheduler) {
                let minutes = next.cfg.controls.postponeOptions.first ?? 5
                scheduler.postpone(next.cfg.id, minutes: minutes)
            }
        }
        handlers[ShortcutAction.postponeNext2.rawValue] = {
            if let next = scheduler.nextBreakInfo() ?? currentOrNext(scheduler) {
                let options = next.cfg.controls.postponeOptions
                let minutes = options.count > 1 ? options[1] : (options.first ?? 10)
                scheduler.postpone(next.cfg.id, minutes: minutes)
            }
        }
        handlers[ShortcutAction.skipNext.rawValue] = {
            if let current = scheduler.activeBreakID {
                scheduler.skip(current)
            } else if let next = scheduler.nextBreakInfo() {
                scheduler.skip(next.cfg.id)
            }
        }
        handlers[ShortcutAction.pauseAll.rawValue] = {
            scheduler.pause(forMinutes: -1)
        }
        handlers[ShortcutAction.resumeAll.rawValue] = {
            scheduler.resume()
        }
        handlers[ShortcutAction.resetAll.rawValue] = {
            scheduler.resetAll()
        }
        handlers[ShortcutAction.stopSound.rawValue] = {
            SoundPlayer.stopAll()
        }

        HotKeyCenter.shared.update(specs, handlers: handlers)
    }

    private static func currentOrNext(_ scheduler: Scheduler) -> (cfg: BreakConfig, runtime: BreakRuntime)? {
        if let id = scheduler.activeBreakID, let cfg = Store.shared.breakByID(id) {
            return (cfg, BreakRuntime(nextStart: Date(), phase: .active, phaseEnd: Date()))
        }
        return nil
    }
}

import Foundation
import AppKit
import SwiftUI

/// The app's accent color, a dark forest green like the reference design.
extension Color {
    static let forestGreen = Color(red: 0.18, green: 0.42, blue: 0.27)
}

extension ShapeStyle where Self == Color {
    static var forestGreen: Color { Color.forestGreen }
}

/// External navigation state so the menu bar panel can jump the settings
/// window to any page, even after the window was created.
final class SettingsNavModel: ObservableObject {
    @Published var selection: SettingsSelection?
}

/// Manages the single Settings window (NSWindow + SwiftUI content).
final class SettingsWindowController {
    static var shared: SettingsWindowController?

    private var window: NSWindow?
    private let nav = SettingsNavModel()

    func show(initialSelection: SettingsSelection? = nil) {
        if window == nil {
            let content = SettingsRootView(nav: nav)
                .environmentObject(Store.shared)
                .environmentObject(AppDelegate.shared!.scheduler)
                .environmentObject(AppDelegate.shared!.log)
                .environmentObject(Clock.shared)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable,
                            .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "BreakTime Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            // user-fixed minimum width (900 pt); enforced on three levels,
            // plus the frame itself is autosaved
            w.minSize = NSSize(width: 900, height: 580)
            w.contentMinSize = NSSize(width: 900, height: 580)
            w.contentView = NSHostingView(rootView:
                content.frame(minWidth: 900, minHeight: 580))
            if !w.setFrameAutosaveName("BreakTimeSettings") {
                w.center()  // first launch: no saved frame yet
            } else if w.frame.width < 900 {
                // a stale saved frame from before the new minimum: fix it up
                var frame = w.frame
                frame.size.width = 900
                w.setFrame(frame, display: true)
            }
            window = w
        }
        if let selection = initialSelection {
            nav.selection = selection
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Selection

enum BreakTab: String, Hashable, CaseIterable, Identifiable {
    case name, schedule, themes, controls, actions
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SettingsSelection: Hashable {
    case activity(ActivityTab)
    case breakTab(UUID, BreakTab)
    case general
    case shortcuts
    case rules
    case advanced

    /// Stable identity for keeping sidebar highlight.
    var sidebarID: String {
        switch self {
        case .activity: return "activity"
        case .breakTab(let id, _): return "break-\(id.uuidString)"
        case .general: return "general"
        case .shortcuts: return "shortcuts"
        case .rules: return "rules"
        case .advanced: return "advanced"
        }
    }

    /// Parses a `--select` launch argument value (dev/testing aid).
    static func parse(_ raw: String) -> SettingsSelection? {
        let store = Store.shared
        let firstBreak = store.breaks.first
        switch raw.lowercased() {
        case "activity", "log": return .activity(.log)
        case "statistics": return .activity(.statistics)
        case "general": return .general
        case "shortcuts": return .shortcuts
        case "rules": return .rules
        case "advanced": return .advanced
        case "name", "schedule", "themes", "controls", "actions":
            guard let cfg = firstBreak,
                  let tab = BreakTab(rawValue: raw.lowercased()) else { return nil }
            return .breakTab(cfg.id, tab)
        default: return nil
        }
    }
}

enum ActivityTab: Hashable {
    case log, statistics
}

// MARK: - Root view

struct SettingsRootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var log: ActivityLog
    @ObservedObject var nav: SettingsNavModel

    /// Resizable sidebar width (user-fixed minimum of ~296 pt; wider is allowed).
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 296
    @State private var prevDragWidth: CGFloat = 0

    private var selection: SettingsSelection? {
        get { nav.selection }
    }

    private var defaultSelection: SettingsSelection {
        store.breaks.first.map { .breakTab($0.id, .schedule) } ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $nav.selection)
                .frame(width: sidebarWidth)
                .background(Color(nsColor: .controlBackgroundColor))

            SidebarDivider(width: $sidebarWidth, prevDragWidth: $prevDragWidth)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.forestGreen)
        .onAppear {
            if nav.selection == nil { nav.selection = defaultSelection }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .breakTab(let id, let tab):
            if store.breaks.contains(where: { $0.id == id }) {
                BreakTabPage(cfgID: id, tab: tab, onTabChange: { nav.selection = .breakTab(id, $0) })
                    .id(id)   // fresh view state per break — no bleed-over of
                              // pickers/steppers between breaks
            } else {
                missingPage
            }
        case .activity(let tab):
            ActivityPage(tab: tab) { nav.selection = .activity($0) }
        case .general:
            GeneralPage()
        case .shortcuts:
            ShortcutsPage()
        case .rules:
            RulesPage()
        case .advanced:
            AdvancedPage()
        case nil:
            Text("Select an item in the sidebar")
                .foregroundStyle(.secondary)
        }
    }

    private var missingPage: some View {
        Text("This break no longer exists")
            .foregroundStyle(.secondary)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: SettingsSelection?
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var log: ActivityLog

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            toolbarRow
                .padding(.horizontal, 10)
                .padding(.top, 34)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    SidebarRow(selection: $selection, id: .activity(.log),
                               title: "Activity", icon: "list.bullet.rectangle")

                    sectionHeader("Breaks")
                    ForEach(store.breaks) { cfg in
                        BreakSidebarRow(cfg: cfg,
                                        isSelected: selection?.sidebarID == "break-\(cfg.id.uuidString)") {
                            selection = .breakTab(cfg.id, .schedule)
                        } onStart: {
                            scheduler.beginBreak(cfg.id)
                        } onEdit: {
                            selection = .breakTab(cfg.id, .name)
                        } onDuplicate: {
                            duplicateBreak(cfg)
                        } onMakeDueIn: { minutes in
                            scheduler.makeDueIn(cfg.id, minutes: minutes)
                        } onPostpone: { minutes in
                            scheduler.postpone(cfg.id, minutes: minutes)
                        } onSkip: {
                            scheduler.skip(cfg.id)
                        } onPauseBreak: { minutes in
                            scheduler.pauseBreak(cfg.id, minutes: minutes)
                        } onResetBreak: {
                            scheduler.resetBreak(cfg.id)
                        } onDisableToggle: {
                            if let i = store.breaks.firstIndex(where: { $0.id == cfg.id }) {
                                store.breaks[i].enabled.toggle()
                            }
                        } onDelete: {
                            deleteBreak(cfg)
                        }
                        .onDrag {
                            BreakDragState.draggingID = cfg.id
                            return NSItemProvider(object: cfg.id.uuidString as NSString)
                        }
                        .onDrop(of: [.plainText],
                                delegate: BreakDropDelegate(store: store, targetID: cfg.id))
                    }

                    sectionHeader("Options")
                    SidebarRow(selection: $selection, id: .general, title: "General", icon: "slider.horizontal.3")
                    SidebarRow(selection: $selection, id: .shortcuts, title: "Shortcuts", icon: "keyboard")
                    SidebarRow(selection: $selection, id: .rules, title: "Rules", icon: "list.bullet.circle")
                    SidebarRow(selection: $selection, id: .advanced, title: "Advanced", icon: "gearshape.2")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Toolbar (+, pause, gear, help)

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            SidebarToolButton(icon: "plus", help: "Add a break") {
                var cfg = BreakConfig(id: UUID(), name: "Custom Break", kind: .custom)
                cfg.scheduleMode = .everyMinutes(60)
                cfg.durationSec = 300
                store.breaks.append(cfg)
                selection = .breakTab(cfg.id, .name)
            }

            Menu {
                ForEach(StatusBarController.pauseChoices, id: \.min) { option in
                    Button(option.label) { scheduler.pause(forMinutes: option.min) }
                }
                if scheduler.isPaused {
                    Divider()
                    Button("Resume Breaks") { scheduler.resume() }
                }
            } label: {
                SidebarToolLabel(icon: "pause.fill")
            } primaryAction: {
                scheduler.pause(forMinutes: -1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pause or resume all breaks")

            Menu {
                Button("Open BreakTime Settings…") { AppDelegate.shared?.openSettings() }
                Divider()
                Button("Reset Break Timers") { scheduler.resetAll() }
            } label: {
                SidebarToolLabel(icon: "gearshape")
            } primaryAction: {
                AppDelegate.shared?.openSettings()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("BreakTime options")

            Menu {
                Button("BreakTime Help") {
                    if let url = URL(string: "https://developer.apple.com") { NSWorkspace.shared.open(url) }
                }
                Button("Welcome to BreakTime") {
                    WelcomeWindowController.shared = WelcomeWindowController()
                    WelcomeWindowController.shared?.show {}
                }
            } label: {
                SidebarToolLabel(icon: "questionmark.circle")
            } primaryAction: {}
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Help")

            Spacer()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }

    /// Duplicate a break, inserting the copy right after the original.
    private func duplicateBreak(_ cfg: BreakConfig) {
        var copy = cfg
        copy.id = UUID()
        copy.name = "\(cfg.name) Copy"
        if let idx = store.breaks.firstIndex(where: { $0.id == cfg.id }) {
            store.breaks.insert(copy, at: idx + 1)
        } else {
            store.breaks.append(copy)
        }
    }

    private func deleteBreak(_ cfg: BreakConfig) {
        guard store.breaks.count > 1, !store.settings.isHidden("delete") else { return }
        store.breaks.removeAll { $0.id == cfg.id }
        if case .breakTab(cfg.id, _) = selection {
            selection = nil
        }
    }
}

// MARK: - Resizable sidebar divider

/// A draggable split between the sidebar and the content area.
/// The chosen width is stored in UserDefaults ("sidebarWidth").
struct SidebarDivider: View {
    @Binding var width: Double
    @Binding var prevDragWidth: CGFloat
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(hovering ? 0.25 : 0.12))
                .frame(width: 1)
            Rectangle()
                .fill(.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: 9)
        .onHover { h in
            hovering = h
            if h {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let delta = value.translation.width - prevDragWidth
                    prevDragWidth = value.translation.width
                    width = min(820, max(296, width + delta))
                }
                .onEnded { _ in
                    prevDragWidth = 0
                }
        )
    }
}

// MARK: - Sidebar rows

/// Simple sidebar row with icon + title; green selection pill and green hover,
/// like the original's menu highlighting.
struct SidebarRow: View {
    @Binding var selection: SettingsSelection?
    let id: SettingsSelection
    let title: String
    let icon: String
    @State private var isHovered = false

    private var isSelected: Bool { selection?.sidebarID == id.sidebarID }
    private var isHighlighted: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: { selection = id }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHighlighted ? Color.forestGreen : Color.clear)
            )
            .foregroundStyle(isHighlighted ? .white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Rich break row: status dot (or mini pie), name, countdown + status lines.
/// The Start and Options ▾ controls stay hidden until the row is hovered,
/// like the reference design.
struct BreakSidebarRow: View {
    let cfg: BreakConfig
    let isSelected: Bool
    var onSelect: () -> Void = {}
    let onStart: () -> Void
    var onEdit: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onMakeDueIn: (Int) -> Void = { _ in }
    var onPostpone: (Int) -> Void = { _ in }
    var onSkip: () -> Void = {}
    var onPauseBreak: (Int) -> Void = { _ in }
    var onResetBreak: () -> Void = {}
    var onDisableToggle: () -> Void = {}
    var onDelete: () -> Void = {}

    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var clock: Clock
    @State private var isHovered = false

    private static let makeDueInChoices = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 45, 60]

    /// Rows are highlighted (green + white) when selected OR hovered,
    /// like the original's menu item highlighting.
    private var isHighlighted: Bool { isSelected || isHovered }

    /// Fixed row height that fits the stacked Start/Options buttons, so the
    /// layout never shifts when they appear on hover.
    private static let rowHeight: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // icon column: the drag handle overlays the dot — no size change
            ZStack {
                if cfg.showPieChart {
                    MiniPie(counters: store.counters(for: cfg.id), hex: cfg.labelHex)
                        .frame(width: 14, height: 14)
                        .opacity(isHovered ? 0 : 1)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .opacity(isHovered ? 0 : 1)
                }
                if isHovered {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(cfg.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(scheduler.sidebarDueLine(for: cfg))
                    .font(.system(size: 11))
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                if let status = scheduler.sidebarStatusLine(for: cfg) {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(isHighlighted ? .white.opacity(0.7) : .secondary)
                }
            }
            Spacer()

            if isHovered {
                VStack(spacing: 4) {
                    Button(action: onStart) {
                        Text("Start")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 78)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(buttonFill))
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                    .help("Start this break now")

                    optionsButton
                        .help("Break options")
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? Color.forestGreen : Color.clear)
        )
        .foregroundStyle(isHighlighted ? .white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) { onSelect() }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            BreakDragState.draggingID = cfg.id
            return NSItemProvider(object: cfg.id.uuidString as NSString)
        }
        .contextMenu {
            Button("Start Break Now", action: onStart)
            Divider()
            Button("Edit Break…", action: onEdit)
            Divider()
            Button("Delete Break", role: .destructive, action: onDelete)
                .disabled(!canDelete)
        }
    }

    /// The Options ▾ button: a plain capsule with our own right-side chevron
    /// that opens a fully native NSMenu (with submenus), like the original.
    private var optionsButton: some View {
        Button(action: showOptionsNSMenu) {
            HStack(spacing: 3) {
                Text("Options")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .frame(width: 78)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(buttonFill))
            .foregroundStyle(Color.black)
        }
        .buttonStyle(.plain)
    }

    /// Builds and shows the native options menu at the mouse location:
    /// Edit / Make Due In ▸ / Postpone… / Skip / Pause Break ▸ / Reset / Disable / Duplicate / Delete.
    private func showOptionsNSMenu() {
        let target = NativeMenuPopup.shared

        func item(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let i = NSMenuItem(title: title,
                               action: #selector(NativeMenuPopup.invoke(_:)),
                               keyEquivalent: "")
            i.target = target
            i.representedObject = action
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                i.image = img
            }
            return i
        }

        func submenuParent(_ title: String, _ symbol: String, _ sub: NSMenu) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                i.image = img
            }
            i.submenu = sub
            return i
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Edit Break", "square.and.pencil", onEdit))

        if !store.settings.isHidden("makeDue") {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for minutes in Self.makeDueInChoices {
                sub.addItem(item(TimeFmt.minutesLong(minutes), "clock", { onMakeDueIn(minutes) }))
            }
            menu.addItem(submenuParent("Make Due In", "clock", sub))
        }

        for minutes in cfg.controls.postponeOptions {
            menu.addItem(item("Postpone \(TimeFmt.minutesLong(minutes))",
                              "forward.end.fill", { onPostpone(minutes) }))
        }
        menu.addItem(item("Skip Break", "forward.end", onSkip))

        if !store.settings.isHidden("pause") {
            let sub = NSMenu()
            sub.autoenablesItems = false
            if scheduler.isBreakPaused(cfg.id) {
                sub.addItem(item("Resume Break", "play.fill", { onPauseBreak(0) }))
                sub.addItem(NSMenuItem.separator())
            }
            for option in StatusBarController.pauseChoices where option.min > 0 {
                sub.addItem(item(option.label, "pause.fill", { onPauseBreak(option.min) }))
            }
            sub.addItem(item("Indefinitely", "pause.circle", { onPauseBreak(-1) }))
            menu.addItem(submenuParent("Pause Break", "pause.fill", sub))
        }

        if !store.settings.isHidden("reset") {
            menu.addItem(item("Reset Break", "arrow.counterclockwise", onResetBreak))
        }
        if !store.settings.isHidden("disable") {
            menu.addItem(item(cfg.enabled ? "Disable Break" : "Enable Break",
                              "power", onDisableToggle))
        }
        if !store.settings.isHidden("delete") {
            menu.addItem(NSMenuItem.separator())
            let dup = item("Duplicate Break", "plus.square.on.square", onDuplicate)
            menu.addItem(dup)
            menu.addItem(NSMenuItem.separator())
            let del = item("Delete Break", "trash", onDelete)
            del.isEnabled = canDelete
            menu.addItem(del)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Solid white on highlighted (selected or hovered) rows so the buttons
    /// never blend into the row or the open menu's green highlight.
    private var buttonFill: Color {
        isHighlighted ? Color.white : Color.primary.opacity(0.08)
    }

    private var pauseChoicesForBreak: [(min: Int, label: String)] {
        var choices = StatusBarController.pauseChoices
        if scheduler.isBreakPaused(cfg.id) {
            choices.insert((0, "Resume Break"), at: 0)
        }
        return choices
    }

    private var canDelete: Bool {
        store.breaks.count > 1 && !store.settings.isHidden("delete")
    }

    private var statusColor: Color {
        guard cfg.enabled else { return .gray }
        if scheduler.isPaused || scheduler.isBreakPaused(cfg.id) { return .orange }
        switch scheduler.runtimes[cfg.id]?.phase {
        case .active, .ready: return .green
        case .idle, .none:
            if let rt = scheduler.runtimes[cfg.id], rt.nextStart.timeIntervalSince(clock.now) < 60 {
                return .red
            }
            return .yellow
        }
    }
}

// MARK: - Mini pie chart (postponed / skipped / done today)

/// The whole pie uses the break's Label color — that's what the color is for.
/// With no events today it shows a full solid ring; with events, the ring is
/// split into done (solid), postponed (55%), skipped (30%) — together always
/// a complete circle.
struct MiniPie: View {
    let counters: DayCounters
    let hex: String

    private var color: Color { Color(hex: hex) }

    private var total: Double {
        Double(max(1, counters.postponed + counters.skipped + counters.done))
    }

    private var isEmpty: Bool {
        counters.done + counters.postponed + counters.skipped == 0
    }

    var body: some View {
        ZStack {
            if isEmpty {
                Circle()
                    .stroke(color, lineWidth: 3)
            } else {
                Circle()
                    .trim(from: 0, to: Double(counters.done) / total)
                    .stroke(color, lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: Double(counters.postponed) / total)
                    .stroke(color.opacity(0.55), lineWidth: 3)
                    .rotationEffect(.degrees(-90 + 360.0 * Double(counters.done) / total))
                Circle()
                    .trim(from: 0, to: Double(counters.skipped) / total)
                    .stroke(color.opacity(0.3), lineWidth: 3)
                    .rotationEffect(.degrees(-90 + 360.0 * Double(counters.done + counters.postponed) / total))
            }
        }
        .help("Today: \(counters.done) done, \(counters.postponed) postponed, \(counters.skipped) skipped")
    }
}

// MARK: - Drag to reorder (priority, top to bottom)

enum BreakDragState {
    static var draggingID: UUID?
}

struct BreakDropDelegate: DropDelegate {
    let store: Store
    let targetID: UUID

    func dropEntered(info: DropInfo) {
        guard let dragging = BreakDragState.draggingID,
              let from = store.breaks.firstIndex(where: { $0.id == dragging }),
              let to = store.breaks.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        let moved = store.breaks.remove(at: from)
        store.breaks.insert(moved, at: to)
    }

    func performDrop(info: DropInfo) -> Bool {
        BreakDragState.draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Small toolbar pieces

struct SidebarToolButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SidebarToolLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 26)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

// Pause choices shared with the status menu.
extension StatusBarController {
    static let pauseChoices: [(min: Int, label: String)] = [
        (1, "1 Minute"), (2, "2 Minutes"), (5, "5 Minutes"), (10, "10 Minutes"),
        (15, "15 Minutes"), (30, "30 Minutes"),
        (60, "1 Hour"), (120, "2 Hours"), (180, "3 Hours"), (240, "4 Hours"),
        (300, "5 Hours"), (480, "8 Hours"), (720, "12 Hours"), (1440, "24 Hours"),
        (-1, "Indefinitely")
    ]
}

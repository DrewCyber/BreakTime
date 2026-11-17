import Foundation
import AppKit
import SwiftUI
import Combine

/// Menu bar status item: icon + optional countdown label, with a menu that
/// shows each break's countdown and controls (begin / make due / postpone / skip,
/// pause, settings). Respects the "Hide" items from Advanced settings.
final class StatusBarController: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let scheduler: Scheduler
    private let store: Store

    private var breakMenus: [UUID: NSMenu] = [:]
    private var pauseMenu: NSMenu!
    private var resumeItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var resetItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var statusMenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()

    /// Pause durations offered in the Pause Breaks submenu, in minutes (-1 = indefinitely).
    private static let pauseOptions: [(min: Int, label: String)] = [
        (1, "1 Minute"), (2, "2 Minutes"), (5, "5 Minutes"), (10, "10 Minutes"),
        (15, "15 Minutes"), (30, "30 Minutes"),
        (60, "1 Hour"), (120, "2 Hours"), (180, "3 Hours"), (240, "4 Hours"),
        (300, "5 Hours"), (480, "8 Hours"), (720, "12 Hours"), (1440, "24 Hours"),
        (-1, "Indefinitely")
    ]

    init(scheduler: Scheduler, store: Store) {
        self.scheduler = scheduler
        self.store = store
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))

        buildMenu()

        store.$breaks
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        store.$settings
            .dropFirst()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        refresh()
    }

    // MARK: Click behavior (popover without Dock icon, menu on right-click)

    private(set) var popover: NSPopover?

    func menuDidClose(_ menu: NSMenu) {
        // restore click handling once the right-click menu closes
        statusItem.menu = nil
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusMenu.delegate = self
            statusItem.menu = statusMenu
            // with a menu assigned, the synthesized click opens the menu directly
            _ = sender.performClick(nil)
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let content = StatusPopoverView()
            .environmentObject(store)
            .environmentObject(scheduler)
            .environmentObject(AppDelegate.shared!.log)
            .environmentObject(Clock.shared)
        let p = NSPopover()
        p.behavior = .transient
        let hosting = NSHostingController(rootView: content)
        // size the panel to its content, so there's no empty space below
        let fit = hosting.view.fittingSize
        hosting.preferredContentSize = NSSize(width: 272, height: max(fit.height, 200))
        p.contentViewController = hosting
        p.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        popover = p
    }

    // MARK: - Menu construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 260

        let summary = NSMenuItem()
        summary.view = NSHostingView(rootView:
            StatusSummaryRow()
                .environmentObject(scheduler)
                .environmentObject(store)
                .environmentObject(Clock.shared))
        menu.addItem(summary)

        menu.addItem(.separator())

        for cfg in store.breaks {
            let submenu = NSMenu()
            submenu.autoenablesItems = false

            submenu.addItem(item("Begin Break Now", action: #selector(beginBreak(_:)),
                                 tag: tagFor(cfg), keyEquivalent: ""))
            if !store.settings.isHidden("makeDue") {
                submenu.addItem(item("Make Due Now", action: #selector(makeDue(_:)),
                                     tag: tagFor(cfg), keyEquivalent: ""))
            }

            let postponeOptions = cfg.controls.postponeOptions
            if !postponeOptions.isEmpty {
                submenu.addItem(.separator())
                for minutes in postponeOptions {
                    submenu.addItem(item("Postpone \(TimeFmt.minutesLong(minutes))",
                                         action: #selector(postponeBreak(_:)),
                                         tag: tagFor(cfg) * 100 + minutes, keyEquivalent: ""))
                }
            }

            submenu.addItem(.separator())
            submenu.addItem(item("Skip This Break", action: #selector(skipBreak(_:)),
                                 tag: tagFor(cfg), keyEquivalent: ""))
            breakMenus[cfg.id] = submenu

            let parent = item(cfg.name, action: nil, tag: 0, keyEquivalent: "")
            parent.submenu = submenu
            menu.addItem(parent)
        }

        menu.addItem(.separator())

        pauseMenu = NSMenu()
        pauseMenu.autoenablesItems = false
        for (index, option) in Self.pauseOptions.enumerated() {
            pauseMenu.addItem(item(option.label, action: #selector(pauseBreaks(_:)),
                                   tag: index, keyEquivalent: ""))
        }
        pauseItem = item("Pause Breaks", action: nil, tag: 0, keyEquivalent: "")
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)

        resumeItem = item("Resume Breaks", action: #selector(resumeBreaks(_:)),
                          tag: 0, keyEquivalent: "")
        menu.addItem(resumeItem)

        resetItem = item("Reset Breaks", action: #selector(resetBreaks(_:)),
                         tag: 0, keyEquivalent: "")
        menu.addItem(resetItem)

        menu.addItem(.separator())
        menu.addItem(item("Open BreakTime Settings…", action: #selector(openSettings(_:)),
                          tag: 0, keyEquivalent: ","))
        if !store.settings.isHidden("quit") {
            menu.addItem(.separator())
            quitItem = item("Quit BreakTime", action: #selector(quit(_:)),
                            tag: 0, keyEquivalent: "q")
            menu.addItem(quitItem)
        }

        statusItem.menu = nil
        statusMenu = menu
        refresh()
    }

    private func item(_ title: String, action: Selector?, tag: Int, keyEquivalent: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        i.target = self
        i.tag = tag
        i.isEnabled = true
        return i
    }

    /// Encode break index in the tag; postpone items add the minutes.
    private func tagFor(_ cfg: BreakConfig) -> Int {
        guard let idx = store.breaks.firstIndex(where: { $0.id == cfg.id }) else { return 0 }
        return idx + 1
    }

    private func cfgFromTag(_ tag: Int) -> BreakConfig? {
        let idx = tag - 1
        guard store.breaks.indices.contains(idx) else { return nil }
        return store.breaks[idx]
    }

    // MARK: - Refresh (every second)

    private func refresh() {
        let button = statusItem.button
        if scheduler.isPaused {
            setStatusIcon("pause.circle", for: button)
            if button?.title != "" { button?.title = "" }
        } else {
            let choice = StatusIconChoice.fromSymbol(store.settings.statusBarIcon)
            setStatusIcon(choice.symbolName, for: button)
            let title = scheduler.menuBarTitle() ?? ""
            if button?.title != title { button?.title = title }
        }

        for cfg in store.breaks {
            guard let parent = statusMenu?.items.first(where: {
                $0.submenu === breakMenus[cfg.id]
            }) else { continue }
            let title = "\(cfg.name) — \(scheduler.menuSubtitle(for: cfg))"
            if parent.title != title { parent.title = title }
        }

        let paused = scheduler.isPaused
        resumeItem.isHidden = !paused
        pauseItem.isHidden = paused || store.settings.isHidden("pause")
        resetItem.isHidden = store.settings.isHidden("reset")
    }

    /// Sets the button image only when the symbol changes — allocating an
    /// SF Symbol image every second showed up in CPU profiles.
    private var cachedSymbol: String?
    private var cachedImage: NSImage?

    private func setStatusIcon(_ symbol: String?, for button: NSStatusBarButton?) {
        if let symbol, symbol == cachedSymbol, let image = cachedImage {
            if button?.image !== image { button?.image = image }
            return
        }
        if let symbol {
            // never let a missing symbol hide the item — fall back to the timer
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BreakTime")
                ?? NSImage(systemSymbolName: "timer", accessibilityDescription: "BreakTime")
            cachedSymbol = symbol
            cachedImage = image
            button?.image = image
        } else {
            cachedSymbol = nil
            cachedImage = nil
            button?.image = nil
        }
    }

    // MARK: - Actions

    @objc private func beginBreak(_ sender: NSMenuItem) {
        if let cfg = cfgFromTag(sender.tag) {
            scheduler.beginBreak(cfg.id)
        }
    }

    @objc private func makeDue(_ sender: NSMenuItem) {
        if let cfg = cfgFromTag(sender.tag) {
            scheduler.makeDue(cfg.id)
        }
    }

    @objc private func postponeBreak(_ sender: NSMenuItem) {
        let minutes = sender.tag % 100
        if let cfg = cfgFromTag(sender.tag / 100) {
            scheduler.postpone(cfg.id, minutes: minutes)
        }
    }

    @objc private func skipBreak(_ sender: NSMenuItem) {
        if let cfg = cfgFromTag(sender.tag) {
            scheduler.skip(cfg.id)
        }
    }

    @objc private func pauseBreaks(_ sender: NSMenuItem) {
        let option = Self.pauseOptions[sender.tag]
        scheduler.pause(forMinutes: option.min)
    }

    @objc private func resumeBreaks(_ sender: NSMenuItem) {
        scheduler.resume()
    }

    @objc private func resetBreaks(_ sender: NSMenuItem) {
        scheduler.resetAll()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        AppDelegate.shared?.openSettings()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

/// The top summary row in the status menu: next break name, countdown and progress.
struct StatusSummaryRow: View {
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var store: Store
    @EnvironmentObject var clock: Clock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = scheduler.pauseReason {
                Label(reason, systemImage: "pause.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if let next = scheduler.nextBreakInfo() {
                let cfg = next.cfg
                let rt = next.runtime
                let target = rt.nextStart
                let remaining = max(0, target.timeIntervalSince(clock.now))
                let total = cfg.scheduleMode.interval
                let done = min(1, max(0, 1 - remaining / total))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Next: \(cfg.name) break")
                        .font(.system(size: 13, weight: .semibold))
                    Text("in \(TimeFmt.short(remaining))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ProgressView(value: done)
                        .progressViewStyle(.linear)
                        .frame(width: 210)
                }
                .padding(.vertical, 4)
            } else {
                Text("No breaks scheduled")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: 240, alignment: .leading)
    }
}

// MARK: - Menu bar popover (shown when the Dock icon is hidden)

/// A compact version of the settings sidebar that drops from the status item,
/// in the spirit of the original app's menu bar panel.
struct StatusPopoverView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var log: ActivityLog

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Spacer()
                SidebarToolButton(icon: "plus", help: "Add a break") {
                    var cfg = BreakConfig(id: UUID(), name: "Custom Break", kind: .custom)
                    cfg.scheduleMode = .everyMinutes(60)
                    cfg.durationSec = 300
                    store.breaks.append(cfg)
                    open(.breakTab(cfg.id, .name))
                }
                pauseToolbarMenu
                gearToolbarMenu
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                popoverRow("Activity", "list.bullet.rectangle") {
                    open(.activity(.log))
                }

                Text("BREAKS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                ForEach(store.breaks) { cfg in
                    BreakSidebarRow(cfg: cfg, isSelected: false) {
                        open(.breakTab(cfg.id, .schedule))
                    } onStart: {
                        scheduler.beginBreak(cfg.id)
                    } onEdit: {
                        open(.breakTab(cfg.id, .name))
                    } onDuplicate: {
                        var copy = cfg
                        copy.id = UUID()
                        copy.name = "\(cfg.name) Copy"
                        if let i = store.breaks.firstIndex(where: { $0.id == cfg.id }) {
                            store.breaks.insert(copy, at: i + 1)
                        }
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
                        guard store.breaks.count > 1,
                              !store.settings.isHidden("delete") else { return }
                        store.breaks.removeAll { $0.id == cfg.id }
                    }
                }

                Text("OPTIONS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                popoverRow("General", "slider.horizontal.3") { open(.general) }
                popoverRow("Shortcuts", "keyboard") { open(.shortcuts) }
                popoverRow("Rules", "list.bullet.circle") { open(.rules) }
                popoverRow("Advanced", "gearshape.2") { open(.advanced) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 272)
        .tint(.forestGreen)
    }

    private func open(_ selection: SettingsSelection) {
        if let popover = AppDelegate.shared?.statusBar?.popover, popover.isShown {
            popover.performClose(nil)
        }
        AppDelegate.shared?.openSettings(initialSelection: selection)
    }

    private func popoverRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        PopoverPlainRow(title: title, icon: icon, action: action)
    }

    private var pauseToolbarMenu: some View {
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
    }

    private var gearToolbarMenu: some View {
        Menu {
            Button("Open BreakTime Settings…") { open(.general) }
            Divider()
            Button("Reset Break Timers") { scheduler.resetAll() }
        } label: {
            SidebarToolLabel(icon: "gearshape")
        } primaryAction: {
            open(.general)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// A plain popover row with the green hover highlight of a menu item.
struct PopoverPlainRow: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.forestGreen : Color.clear)
            )
            .foregroundStyle(isHovered ? .white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

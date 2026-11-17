import SwiftUI

// MARK: - Pill tab bar (Name | Schedule | Themes | Controls | Actions)

struct BreakTabBar: View {
    let tab: BreakTab
    let onTabChange: (BreakTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BreakTab.allCases) { t in
                Button {
                    onTabChange(t)
                } label: {
                    Text(t.label)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(tab == t ? Color.forestGreen : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            Capsule().strokeBorder(tab == t ? Color.forestGreen : Color.primary.opacity(0.15),
                                                   lineWidth: 1)
                        )
                        .foregroundStyle(tab == t ? .white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Break page container

struct BreakTabPage: View {
    let cfgID: UUID
    let tab: BreakTab
    let onTabChange: (BreakTab) -> Void

    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler

    private var cfg: Binding<BreakConfig> {
        Binding(
            get: { store.breaks.first { $0.id == cfgID } ?? BreakConfig(id: cfgID, name: "?", kind: .custom) },
            set: { newValue in
                if let i = store.breaks.firstIndex(where: { $0.id == cfgID }) {
                    store.breaks[i] = newValue
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BreakTabBar(tab: tab, onTabChange: onTabChange)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .name: NameTab(cfg: cfg)
                case .schedule: ScheduleTab(cfg: cfg)
                case .themes: ThemesTab(cfg: cfg)
                case .controls: ControlsTab(cfg: cfg)
                case .actions: ActionsTab(cfg: cfg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .tint(.forestGreen)
    }
}

// MARK: - Shared form pieces

/// Shared form metrics: the label column width of settings rows.
enum FormMetrics {
    static var labelWidth: CGFloat { 155 }
}

/// A settings row in the reference layout: the label is right-aligned toward
/// a fixed column, and the control starts just after it (not pushed to the
/// pane's right edge).
struct SettingsRow<Control: View>: View {
    let title: String
    var helpText: String? = nil
    var labelWidth: CGFloat? = nil
    @ViewBuilder var control: () -> Control

    init(_ title: String, helpText: String? = nil, labelWidth: CGFloat? = nil,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.helpText = helpText
        self.labelWidth = labelWidth
        self.control = control
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .frame(width: labelWidth ?? FormMetrics.labelWidth, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            control()
            Spacer(minLength: 0)
        }
        .help(helpText ?? "")
    }
}

struct TabForm<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(20)
        }
    }
}

struct SectionDivider: View {
    var body: some View {
        Divider().padding(.vertical, 2)
    }
}

/// A color swatch that opens the system color panel right next to the
/// settings window (SwiftUI's ColorPicker drops it in a screen corner).
struct ColorSwatchButton: View {
    @Binding var hex: String
    @State private var observer: NSObjectProtocol?

    var body: some View {
        Button(action: openPanel) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: hex))
                .frame(width: 44, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .onDisappear { detachObserver() }
    }

    private func openPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(nil)
        detachObserver()
        panel.color = NSColor(hexString: hex)
        let binding = $hex
        observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel, queue: .main) { note in
            guard let p = note.object as? NSColorPanel else { return }
            binding.wrappedValue = p.color.hexStringValue
        }
        // position the panel beside the settings window, not in a screen corner
        if let win = NSApp.windows.first(where: { $0.title == "BreakTime Settings" }) {
            panel.setFrameOrigin(NSPoint(x: win.frame.minX + 280, y: win.frame.minY + 180))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func detachObserver() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}

// MARK: - Name tab

struct NameTab: View {
    @Binding var cfg: BreakConfig
    @EnvironmentObject var store: Store

    var body: some View {
        TabForm {
            SettingsRow("Name:") {
                TextField("Name", text: $cfg.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            SettingsRow("Label:") {
                ColorSwatchButton(hex: $cfg.labelHex)
            }

            Toggle(isOn: $cfg.showPieChart) {
                Text("Show as mini pie chart of postponed/skipped/done today")
            }

            SectionDivider()

            SettingsRow("Comments:") {
                TextEditor(text: $cfg.comments)
                    .font(.system(size: 12))
                    .frame(width: 340, height: 88)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.15)))
            }

            Text("Notes about this break, shown only here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            SectionDivider()

            if !store.settings.isHidden("disable") {
                Toggle("Include this break", isOn: $cfg.enabled)
            }

            if !store.settings.isHidden("delete") && store.breaks.count > 1 {
                HStack {
                    Spacer()
                    Button("Delete Break", role: .destructive) {
                        if let i = store.breaks.firstIndex(where: { $0.id == cfg.id }) {
                            store.breaks.remove(at: i)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Schedule tab

/// Duration units for the "Break for" dropdowns, like the original.
enum DurationUnit: String, CaseIterable, Identifiable {
    case seconds, minutes, hours
    var id: String { rawValue }

    var multiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        }
    }
}

struct ScheduleTab: View {
    @Binding var cfg: BreakConfig
    @EnvironmentObject var scheduler: Scheduler
    @EnvironmentObject var store: Store

    /// Shared, persisted across all breaks and relaunches.
    private var showMoreOptions: Binding<Bool> {
        $store.settings.moreOptionsExpanded
    }

    /// The reference's duration presets for the number dropdown.
    private static let durationNumbers = [0, 1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 90, 120]

    @State private var durNumber: Int = 10
    @State private var durUnit: DurationUnit = .minutes

    @State private var everyNum: Int = 60
    @State private var everyUnit: DurationUnit = .minutes

    private var everyNumbers: [Int] {
        var numbers = Self.durationNumbers.filter { $0 > 0 }
        if !numbers.contains(everyNum) {
            numbers.append(everyNum)
            numbers.sort()
        }
        return numbers
    }

    /// Interval units: minutes or hours (like the original's "1 hour").
    private var everyUnits: [DurationUnit] { [.minutes, .hours] }

    private func syncEveryFromConfig() {
        let minutes = currentIntervalMinutes
        if minutes >= 60 && minutes % 60 == 0 {
            everyUnit = .hours
            everyNum = minutes / 60
        } else {
            everyUnit = .minutes
            everyNum = minutes
        }
    }

    private func writeEveryToConfig() {
        // the interval pickers only exist in Every/Randomly modes; don't let
        // their appear-sync rewrite a Manual/Once break into an interval one
        guard showsInterval else { return }
        let minutes = max(1, everyNum * everyUnit.multiplier / 60)
        switch cfg.scheduleMode {
        case .random: cfg.scheduleMode = .random(minutes)
        default: cfg.scheduleMode = .everyMinutes(minutes)
        }
    }

    // "Reset after a natural break longer than N" state
    @State private var natResetNum: Int = 10
    @State private var natResetUnit: DurationUnit = .minutes

    private func syncNaturalResetFromConfig() {
        let total = cfg.resetAfterNaturalLongerThanSec
        if total >= 3600 && total % 3600 == 0 {
            natResetUnit = .hours
            natResetNum = total / 3600
        } else if total >= 60 && total % 60 == 0 {
            natResetUnit = .minutes
            natResetNum = total / 60
        } else {
            natResetUnit = .seconds
            natResetNum = max(1, total)
        }
    }

    private func writeNaturalResetToConfig() {
        // while the option is off, only the toggle itself may change the value —
        // otherwise the appear-sync (1 sec defaults) would silently re-enable it
        guard cfg.resetAfterNaturalLongerThanSec > 0 else { return }
        cfg.resetAfterNaturalLongerThanSec = max(1, natResetNum * natResetUnit.multiplier)
    }

    private var durationNumbers: [Int] {
        var numbers = Self.durationNumbers
        if !numbers.contains(durNumber) {
            numbers.append(durNumber)
            numbers.sort()
        }
        return numbers
    }

    /// Loads cfg.durationSec into the number/unit pair.
    private func syncDurationFromConfig() {
        let total = cfg.durationSec
        let unit: DurationUnit
        if total >= 3600 && total % 3600 == 0 {
            unit = .hours
        } else if total >= 60 && total % 60 == 0 {
            unit = .minutes
        } else {
            unit = .seconds
        }
        durUnit = unit
        durNumber = max(1, total / unit.multiplier)
    }

    private func writeDurationToConfig() {
        cfg.durationSec = max(5, durNumber * durUnit.multiplier)
    }

    /// The reference's "Every" mode dropdown: Manually / Once / Every / Randomly.
    private var modeBinding: Binding<Int> {
        Binding(
            get: {
                switch cfg.scheduleMode {
                case .manual: return 0
                case .once: return 1
                case .everyMinutes, .timesPerHour: return 2
                case .random: return 3
                }
            },
            set: { newValue in
                let minutes = currentIntervalMinutes
                switch newValue {
                case 0: cfg.scheduleMode = .manual
                case 1: cfg.scheduleMode = .once
                case 3: cfg.scheduleMode = .random(minutes)
                default: cfg.scheduleMode = .everyMinutes(minutes)
                }
            })
    }

    private var currentIntervalMinutes: Int {
        let minutes: Int
        switch cfg.scheduleMode {
        case .everyMinutes(let m), .random(let m): minutes = m
        case .timesPerHour(let n): minutes = max(1, Int((3600.0 / Double(max(1, n)) / 60).rounded()))
        default: minutes = 60
        }
        return max(1, minutes)
    }

    private var showsInterval: Bool {
        switch cfg.scheduleMode {
        case .everyMinutes, .timesPerHour, .random: return true
        default: return false
        }
    }

    /// "work for 50 minutes"-style hint under the Every row, per mode.
    private var workHint: String {
        switch cfg.scheduleMode {
        case .manual:
            return "Manual-only breaks do not have a due date; use Start instead."
        case .once:
            return "Starts once at the Next due date below."
        case .random:
            return "(random interval, up to every \(intervalLabel))"
        default:
            let workSec = Int(cfg.scheduleMode.interval - cfg.duration)
            guard workSec > 0 else { return "(longer than the interval)" }
            if workSec >= 3600 {
                let h = workSec / 3600, m = (workSec % 3600) / 60
                return m > 0 ? "(work for \(h) hour\(h == 1 ? "" : "s") \(m) min)"
                             : "(work for \(h) hour\(h == 1 ? "" : "s"))"
            }
            let m = workSec / 60
            return "(work for \(m) minute\(m == 1 ? "" : "s"))"
        }
    }

    private var intervalLabel: String {
        let minutes = currentIntervalMinutes
        if minutes >= 60 && minutes % 60 == 0 {
            let h = minutes / 60
            return "\(h) hour\(h == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private var nextDue: Binding<Date> {
        Binding(
            get: { scheduler.runtimes[cfg.id]?.nextStart ?? Date() },
            set: { scheduler.setNextStart(cfg.id, to: $0) })
    }

    /// "Between 9:00 and 17:00" time bindings (seconds since midnight ↔ Date).
    private static var timeReferenceDay: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var fromTimeBinding: Binding<Date> {
        Binding(
            get: { Self.timeReferenceDay.addingTimeInterval(TimeInterval(cfg.avail.fromSec)) },
            set: { cfg.avail.fromSec = Int($0.timeIntervalSince(Self.timeReferenceDay)) })
    }

    private var toTimeBinding: Binding<Date> {
        Binding(
            get: { Self.timeReferenceDay.addingTimeInterval(TimeInterval(cfg.avail.toSec)) },
            set: { cfg.avail.toSec = Int($0.timeIntervalSince(Self.timeReferenceDay)) })
    }

    var body: some View {
        TabForm {
            SettingsRow("Break for:") {
                AmountUnitField(amount: $durNumber, unit: $durUnit,
                                presets: durationNumbers, range: 0...120)
            }
            .onChange(of: durNumber) { _ in writeDurationToConfig() }
            .onChange(of: durUnit) { _ in writeDurationToConfig() }
            .onAppear {
                syncDurationFromConfig()
                syncNaturalResetFromConfig()
            }

            // "Every" row like the reference: the mode dropdown always sits in
            // the same left position; account for BOTH 6pt gaps so the NUMBER
            // dropdown starts exactly at the shared control column (labelWidth + 10).
            HStack(spacing: 6) {
                let modeWidth: CGFloat = 110
                Color.clear.frame(width: FormMetrics.labelWidth + 10 - modeWidth - 2 * 6, height: 1)

                Picker("", selection: modeBinding) {
                    Text("Manually").tag(0)
                    Text("Once").tag(1)
                    Text("Every").tag(2)
                    Text("Randomly").tag(3)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)

                if showsInterval {
                    AmountUnitField(amount: $everyNum, unit: $everyUnit,
                                    presets: everyNumbers, range: 1...120)
                }
                Spacer(minLength: 0)
            }
            .onChange(of: everyNum) { _ in writeEveryToConfig() }
            .onChange(of: everyUnit) { _ in writeEveryToConfig() }
            .onAppear { syncEveryFromConfig() }
            Text(workHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, FormMetrics.labelWidth + 10)
                .padding(.top, -8)

            if !cfg.scheduleMode.isManual {
                if cfg.scheduleMode != .once {
                    SettingsRow("From:") {
                        Picker("", selection: $cfg.anchor) {
                            ForEach(ScheduleAnchor.allCases) { anchor in
                                Text(anchor.label).tag(anchor)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                        .help("Where the next interval counts from.")
                    }
                }

                SettingsRow("Available:") {
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { cfg.avail.mode },
                            set: { cfg.avail.mode = $0 })) {
                            ForEach(AvailabilityMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 105)

                        if cfg.avail.mode != .everyDay {
                            WeekdayChips(mask: Binding(
                                get: { cfg.avail.daysMask },
                                set: { cfg.avail.daysMask = $0 }))
                        }
                    }
                }

                if cfg.avail.mode == .between {
                    SettingsRow("") {
                        HStack(spacing: 8) {
                            DatePicker("", selection: fromTimeBinding,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(width: 90)
                            Text("and")
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: toTimeBinding,
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(width: 90)
                        }
                    }
                }

                SettingsRow("Next due:") {
                    SecondsDatePicker(date: nextDue)
                        .fixedSize()
                }
            }

            MoreOptionsToggle(isExpanded: showMoreOptions)

            if showMoreOptions.wrappedValue {
                VStack(alignment: .leading, spacing: 12) {
                    // label starts at the form's leading edge; popup right after it
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("When taking a natural break (the Mac is idle):")
                        Picker("", selection: $cfg.idleMode) {
                            ForEach(IdleMode.displayOrder) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        Spacer(minLength: 0)
                    }
                    Text("The idle threshold is set in Advanced as the “natural break” threshold.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { cfg.resetAfterNaturalLongerThanSec > 0 },
                        set: { cfg.resetAfterNaturalLongerThanSec = $0 ? 600 : 0
                               syncNaturalResetFromConfig() })) {
                        HStack(spacing: 6) {
                            Text("Reset this break after a natural break longer than")
                            Picker("", selection: $natResetNum) {
                                ForEach(durationNumbers, id: \.self) { n in
                                    Text("\(n)").tag(n)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 60)
                            .disabled(cfg.resetAfterNaturalLongerThanSec == 0)

                            Picker("", selection: $natResetUnit) {
                                ForEach(DurationUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 100)
                            .disabled(cfg.resetAfterNaturalLongerThanSec == 0)
                        }
                    }
                    .onChange(of: natResetNum) { _ in writeNaturalResetToConfig() }
                    .onChange(of: natResetUnit) { _ in writeNaturalResetToConfig() }

                    Toggle("Reset this break after finishing one with a higher priority",
                           isOn: $cfg.resetAfterHigherPriorityFinish)

                    Toggle(isOn: Binding(
                        get: { cfg.skipIfHigherPriorityDueWithinMin > 0 },
                        set: { cfg.skipIfHigherPriorityDueWithinMin = $0 ? 5 : 0 })) {
                        HStack(spacing: 6) {
                            Text("Skip this break if one with a higher priority is due within")
                            Stepper("\(cfg.skipIfHigherPriorityDueWithinMin) min",
                                    value: $cfg.skipIfHigherPriorityDueWithinMin, in: 0...120, step: 5)
                                .fixedSize()
                                .disabled(cfg.skipIfHigherPriorityDueWithinMin == 0)
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 4)
            }

            if !cfg.scheduleMode.isManual {
                SectionDivider()

                SettingsRow("When this break is due:") {
                    HStack(spacing: 6) {
                        Picker("", selection: Binding(
                            get: { cfg.readySeconds > 0 },
                            set: { cfg.readySeconds = $0 ? 10 : 0 })) {
                            Text("Start Immediately").tag(false)
                            Text("Get Ready Countdown").tag(true)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180)

                        if cfg.readySeconds > 0 {
                            Picker("", selection: $cfg.readySeconds) {
                                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { s in
                                    Text("\(s) sec").tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 80)
                        }
                    }
                }
            }

            SectionDivider()

            HStack {
                Button("Preview Break") {
                    scheduler.beginBreak(cfg.id, preview: true)
                }
                Spacer()
            }

            Text("Drag the breaks to order in priority, top to bottom. Higher-priority breaks are at the top.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Themes tab

struct ThemesTab: View {
    @Binding var cfg: BreakConfig
    @EnvironmentObject var scheduler: Scheduler

    private var screenName: String {
        NSScreen.main?.localizedName ?? "Display"
    }

    var body: some View {
        TabForm {
            // Preview card, in the spirit of the original's display preview
            VStack(alignment: .leading, spacing: 6) {
                Text(screenName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: cfg.appearance.backgroundHex)
                            .opacity(cfg.appearance.opacity))
                        .frame(width: 240, height: 132)
                    VStack(spacing: 6) {
                        Text("\(cfg.name) Break")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        if cfg.appearance.countdownStyle == .ring {
                            ZStack {
                                Circle().stroke(.white.opacity(0.3), lineWidth: 5)
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text(TimeFmt.clock(cfg.duration))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 52, height: 52)
                        } else if cfg.appearance.countdownStyle == .bar {
                            VStack(spacing: 4) {
                                Text(TimeFmt.clock(cfg.duration))
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Capsule().fill(.white.opacity(0.3)).frame(width: 110, height: 5)
                                GeometryReader { geo in
                                    Capsule().fill(.white)
                                        .frame(width: geo.size.width * 0.7, height: 5)
                                }
                                .frame(width: 110, height: 5)
                            }
                        } else {
                            Text(TimeFmt.clock(cfg.duration))
                                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.15))
                        .frame(width: 244, height: 136)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)

            SettingsRow("Background:") {
                ColorSwatchButton(hex: $cfg.appearance.backgroundHex)
            }

            SettingsRow("Opacity:") {
                HStack {
                    Slider(value: $cfg.appearance.opacity, in: 0.2...1.0)
                        .frame(width: 160)
                    Text("\(Int(cfg.appearance.opacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            SectionDivider()

            Text("Countdown style:")
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: $cfg.appearance.countdownStyle) {
                ForEach(BreakAppearance.CountdownStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.radioGroup)
            .padding(.leading, 14)

            Toggle("Show on all screens", isOn: $cfg.appearance.showOnAllScreens)

            SettingsRow("Get Ready style:", labelWidth: 155) {
                Picker("", selection: $cfg.appearance.readyStyle) {
                    ForEach(BreakAppearance.ReadyStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            Text("Banner keeps the screen usable during the countdown — stop music, close windows — before the break.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            SectionDivider()

            HStack {
                Button("Preview Break") {
                    scheduler.beginBreak(cfg.id, preview: true)
                }
                Spacer()
            }
            Text("BreakTime uses solid colors; HTML themes are not included.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Controls tab

struct ControlsTab: View {
    @Binding var cfg: BreakConfig
    @EnvironmentObject var store: Store

    /// Shared, persisted across all breaks and relaunches.
    private var showMoreOptions: Binding<Bool> {
        $store.settings.moreOptionsExpanded
    }

    var body: some View {
        TabForm {
            SettingsRow("Fade in over:") {
                Stepper(String(format: "%.1f sec", cfg.controls.fadeInSeconds),
                        value: $cfg.controls.fadeInSeconds, in: 0...5, step: 0.5)
                    .fixedSize()
            }

            SettingsRow("Fade out over:") {
                Stepper(String(format: "%.1f sec", cfg.controls.fadeOutSeconds),
                        value: $cfg.controls.fadeOutSeconds, in: 0...5, step: 0.5)
                    .fixedSize()
            }

            SectionDivider()

            Text("Break controls:")
                .font(.system(size: 13, weight: .semibold))

            Toggle(isOn: $cfg.controls.showPostpone1) {
                HStack(spacing: 6) {
                    Text("Show button to postpone")
                    Stepper("\(cfg.controls.postpone1Minutes) min",
                            value: $cfg.controls.postpone1Minutes, in: 1...240)
                        .fixedSize()
                    Text("minutes")
                }
            }
            .disabled(!cfg.controls.showPostpone1)

            Toggle(isOn: $cfg.controls.showPostpone2) {
                HStack(spacing: 6) {
                    Text("Show button to postpone")
                    Stepper("\(cfg.controls.postpone2Minutes) min",
                            value: $cfg.controls.postpone2Minutes, in: 1...240)
                        .fixedSize()
                    Text("minutes")
                }
            }
            .disabled(!cfg.controls.showPostpone2)

            Toggle("Show button to skip break", isOn: $cfg.controls.showSkip)

            SectionDivider()

            MoreOptionsToggle(isExpanded: showMoreOptions)

            if showMoreOptions.wrappedValue {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mindfulness:")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 6)

                    Toggle(isOn: Binding(
                        get: { cfg.controls.disableButtonsSeconds > 0 },
                        set: { cfg.controls.disableButtonsSeconds = $0 ? 15 : 0 })) {
                        HStack(spacing: 6) {
                            Text("Disable the buttons for")
                            Stepper("\(cfg.controls.disableButtonsSeconds) sec",
                                    value: $cfg.controls.disableButtonsSeconds, in: 0...300, step: 5)
                                .fixedSize()
                                .disabled(cfg.controls.disableButtonsSeconds == 0)
                            Text("seconds")
                        }
                    }

                    Toggle("Show number of times postponed/skipped/done today",
                           isOn: $cfg.controls.showTodayCounts)

                    Toggle("Show button to end break early",
                           isOn: $cfg.controls.showEndEarly)

                    Text("Control limits:")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.top, 6)

                    Toggle(isOn: Binding(
                        get: { cfg.controls.maxPostponesPerDay > 0 },
                        set: { cfg.controls.maxPostponesPerDay = $0 ? 10 : 0 })) {
                        HStack(spacing: 6) {
                            Text("Postpone no more than")
                            Stepper("\(cfg.controls.maxPostponesPerDay)×",
                                    value: $cfg.controls.maxPostponesPerDay, in: 0...100)
                                .fixedSize()
                                .disabled(cfg.controls.maxPostponesPerDay == 0)
                            Text("times per Day")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { cfg.controls.maxSkipsPerDay > 0 },
                        set: { cfg.controls.maxSkipsPerDay = $0 ? 10 : 0 })) {
                        HStack(spacing: 6) {
                            Text("Limit skip no more than")
                            Stepper("\(cfg.controls.maxSkipsPerDay)×",
                                    value: $cfg.controls.maxSkipsPerDay, in: 0...100)
                                .fixedSize()
                                .disabled(cfg.controls.maxSkipsPerDay == 0)
                            Text("times per Day")
                        }
                    }
                }
                .padding(.leading, 14)
            }
        }
    }
}

/// The whole pill — chevron + label — is one tappable button (the system
/// DisclosureGroup only toggles from its tiny triangle).
struct MoreOptionsToggle: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                Text(isExpanded ? "Hide More Options" : "Show More Options")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date picker with seconds

/// A native NSDatePicker showing AND editing seconds (SwiftUI's DatePicker
/// can't display them). Matches the original app's Next due control.
struct SecondsDatePicker: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.datePickerMode = .single
        picker.timeZone = .current
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.dateValue = date
        picker.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.dateValue != date {
            picker.dateValue = date
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SecondsDatePicker
        init(_ parent: SecondsDatePicker) { self.parent = parent }

        @objc func changed(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}

// MARK: - Amount + unit composite field (like the original's "10 minutes ▲▼")

/// One bordered field: an editable number with a preset dropdown (NSComboBox),
/// a unit dropdown with smart singular/plural, and up/down arrows.
struct AmountUnitField: View {
    @Binding var amount: Int
    @Binding var unit: DurationUnit
    let presets: [Int]
    var range: ClosedRange<Int> = 0...120

    var body: some View {
        HStack(spacing: 0) {
            NumberComboBox(number: $amount, presets: presets, range: range)
                .frame(width: 58)

            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 1, height: 16)

            Menu {
                ForEach(DurationUnit.allCases) { u in
                    Button(unitLabel(u)) { unit = u }
                }
            } label: {
                Text(unitLabel(unit))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 84)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 1, height: 16)

            // compact up/down arrows, fully inside the field bounds
            VStack(spacing: 0) {
                Button {
                    amount = min(range.upperBound, amount + 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    amount = max(range.lowerBound, amount - 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 20, height: 20)
        }
        .frame(height: 22)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.primary.opacity(0.25)))
    }

    /// "1 minute", "10 minutes" — singular when the amount is exactly 1.
    private func unitLabel(_ u: DurationUnit) -> String {
        amount == 1 ? String(u.rawValue.dropLast()) : u.rawValue
    }
}

/// Editable number box with a preset dropdown, like the original.
struct NumberComboBox: NSViewRepresentable {
    @Binding var number: Int
    let presets: [Int]
    var range: ClosedRange<Int>

    func makeNSView(context: Context) -> NSComboBox {
        let cb = NSComboBox()
        cb.isBordered = false
        cb.backgroundColor = .clear
        cb.hasVerticalScroller = false
        cb.focusRingType = .none
        cb.completes = false
        cb.usesDataSource = false
        cb.addItems(withObjectValues: presets.map(String.init))
        cb.numberOfVisibleItems = max(presets.count, 10)   // full list, no scrolling
        cb.stringValue = String(number)
        cb.delegate = context.coordinator
        cb.target = context.coordinator
        cb.action = #selector(Coordinator.comboAction(_:))
        return cb
    }

    func updateNSView(_ cb: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if Int(cb.stringValue) != number {
            cb.stringValue = String(number)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: NumberComboBox

        init(_ parent: NumberComboBox) { self.parent = parent }

        @objc func comboAction(_ sender: NSComboBox) { commit(sender.stringValue) }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let cb = notification.object as? NSComboBox else { return }
            // stringValue may still hold the OLD text when this fires —
            // read the picked item from the list index instead
            let idx = cb.indexOfSelectedItem
            if idx >= 0, let value = cb.itemObjectValue(at: idx) as? String {
                commit(value)
            } else {
                commit(cb.stringValue)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let cb = notification.object as? NSComboBox else { return }
            commit(cb.stringValue)
        }

        private func commit(_ raw: String) {
            let parsed = Int(raw.trimmingCharacters(in: .whitespaces)) ?? parent.number
            let clamped = min(parent.range.upperBound, max(parent.range.lowerBound, parsed))
            parent.number = clamped
        }
    }
}

/// Compact weekday toggles (S M T W T F S) for the availability days mask.
struct WeekdayChips: View {
    @Binding var mask: Int

    private static let labels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { bit in
                let on = mask & (1 << bit) != 0
                Button {
                    mask ^= (1 << bit)
                } label: {
                    Text(Self.labels[bit])
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(on ? Color.forestGreen : Color.primary.opacity(0.08)))
                        .foregroundStyle(on ? .white : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Actions tab

struct ActionsTab: View {
    @Binding var cfg: BreakConfig

    private var sounds: [String] { SoundPlayer.systemSoundNames }

    var body: some View {
        TabForm {
            SettingsRow("When the break starts:") {
                Picker("", selection: $cfg.actions.startSound) {
                    Text("None").tag("")
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
            }

            SettingsRow("When the break ends:") {
                Picker("", selection: $cfg.actions.endSound) {
                    Text("None").tag("")
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
            }

            SettingsRow("Volume:") {
                HStack {
                    Slider(value: $cfg.actions.volume, in: 0...1)
                        .frame(width: 160)
                    Text("\(Int(cfg.actions.volume * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            SectionDivider()

            HStack {
                Button("Test Sound") {
                    let name = cfg.actions.startSound.isEmpty
                        ? cfg.actions.endSound : cfg.actions.startSound
                    SoundPlayer.play(name, volume: cfg.actions.volume)
                }
                Spacer()
            }
            Text("Sounds come from the built-in macOS system sound library.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            SectionDivider()

            Text("Run AppleScript at break start:")
                .font(.system(size: 13, weight: .semibold))
            TextEditor(text: $cfg.actions.startAppleScript)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 380, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15)))
                .padding(.leading, 14)

            Text("Run AppleScript at break end:")
                .font(.system(size: 13, weight: .semibold))
            TextEditor(text: $cfg.actions.endAppleScript)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 380, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15)))
                .padding(.leading, 14)

            Text("Example: tell application \"Music\" to pause — runs any AppleScript when the break starts or ends, like the original's Break Actions.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420, alignment: .leading)
        }
    }
}

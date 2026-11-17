import Foundation

// MARK: - Kinds

enum BreakKind: String, Codable, CaseIterable, Identifiable {
    case normal
    case micro
    case custom

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .normal: return "figure.stand"
        case .micro: return "figure.arms.open"
        case .custom: return "circle"
        }
    }
}

// MARK: - Schedule

/// How often a break occurs — the modes of the original's "Every" dropdown:
/// manually, once at the due date, at a regular interval, or at random intervals.
enum ScheduleMode: Codable, Equatable {
    case everyMinutes(Int)
    case timesPerHour(Int)   // kept for backward compatibility of saved configs
    case manual
    case once
    case random(Int)         // maximum interval in minutes

    var interval: TimeInterval {
        switch self {
        case .everyMinutes(let m): return Double(max(1, m)) * 60
        case .timesPerHour(let n): return 3600.0 / Double(max(1, n))
        case .manual: return .infinity
        case .once: return .infinity
        case .random(let m): return Double(max(1, m)) * 60
        }
    }

    /// The actual interval to use when scheduling the next occurrence
    /// (random draws a fresh value each time).
    var nextInterval: TimeInterval {
        if case .random(let m) = self {
            let maxSec = Double(max(1, m)) * 60
            return Double.random(in: min(60, maxSec)...maxSec)
        }
        return interval
    }

    var isManual: Bool { self == .manual }

    var label: String {
        switch self {
        case .everyMinutes(let m): return "Every \(m) min"
        case .timesPerHour(let n): return "\(n)× per hour"
        case .manual: return "Manual only"
        case .once: return "Once"
        case .random(let m): return "Randomly (up to \(m) min)"
        }
    }
}

/// Where the next interval counts from ("From:" on the Schedule tab).
enum ScheduleAnchor: String, Codable, CaseIterable, Identifiable {
    case lastDue
    case endOfBreak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastDue: return "Last Due"
        case .endOfBreak: return "End of Break"
        }
    }
}

/// Availability of a break ("Available:" on the Schedule tab):
/// every day around the clock, all day on chosen weekdays, or a time window
/// on chosen weekdays ("Between 9:00 and 17:00").
enum AvailabilityMode: String, Codable, CaseIterable, Identifiable {
    case everyDay
    case allDay
    case between

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDay: return "Every Day"
        case .allDay: return "All Day"
        case .between: return "Between"
        }
    }
}

struct Availability: Codable, Equatable {
    var mode: AvailabilityMode = .everyDay
    /// Allowed weekdays as a bitmask, bit 0 = Sunday … bit 6 = Saturday.
    var daysMask: Int = 0b1111111
    /// Window start/end as seconds since midnight (used for .between).
    var fromSec: Int = 9 * 3600
    var toSec: Int = 17 * 3600

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(AvailabilityMode.self, forKey: .mode) ?? .everyDay
        daysMask = try c.decodeIfPresent(Int.self, forKey: .daysMask) ?? 0b1111111
        fromSec = try c.decodeIfPresent(Int.self, forKey: .fromSec) ?? 9 * 3600
        toSec = try c.decodeIfPresent(Int.self, forKey: .toSec) ?? 17 * 3600
    }

    var isOvernight: Bool { toSec <= fromSec }

    func isDayAllowed(_ date: Date) -> Bool {
        let bit = Calendar.current.component(.weekday, from: date) - 1
        return daysMask & (1 << bit) != 0
    }

    private func secondsOfDay(_ date: Date) -> Int {
        Int(date.timeIntervalSince(Calendar.current.startOfDay(for: date)))
    }

    func inTimeWindow(_ date: Date) -> Bool {
        let tod = secondsOfDay(date)
        return isOvernight ? (tod >= fromSec || tod < toSec) : (tod >= fromSec && tod < toSec)
    }

    func isAvailable(_ date: Date) -> Bool {
        switch mode {
        case .everyDay: return true
        case .allDay: return isDayAllowed(date)
        case .between: return isDayAllowed(date) && inTimeWindow(date)
        }
    }

    /// The start of the next available moment at or after `date`
    /// (rolls forward over disallowed days and outside-window times).
    func rollIntoWindow(_ date: Date) -> Date {
        guard mode != .everyDay else { return date }
        let cal = Calendar.current
        var candidate = date
        for _ in 0..<9 {
            if isAvailable(candidate) { return candidate }
            let dayStart = cal.startOfDay(for: candidate)
            if mode == .between, isDayAllowed(candidate) {
                let windowStart = dayStart.addingTimeInterval(Double(fromSec))
                if windowStart > candidate {
                    // window still ahead today (covers the overnight gap too)
                    candidate = windowStart
                    continue
                }
            }
            // move to the next allowed day, at the window start if needed
            var nextDay = dayStart
            repeat {
                nextDay = cal.date(byAdding: .day, value: 1, to: nextDay)!
            } while !isDayAllowed(nextDay) && nextDay < date.addingTimeInterval(8 * 86400)
            candidate = mode == .between
                ? nextDay.addingTimeInterval(Double(fromSec))
                : nextDay.addingTimeInterval(date.timeIntervalSince(dayStart))
        }
        return date
    }
}

/// What to do when the user has been idle (no input) — the natural break modes.
/// Raw values are historical (kept so older configs decode unchanged).
enum IdleMode: String, Codable, CaseIterable, Identifiable {
    case ignore
    case countAsBreak
    case pauseTimers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ignore: return "Continue Countdown"
        case .pauseTimers: return "Pause Countdown"
        case .countAsBreak: return "Count Backwards"
        }
    }

    /// The order shown in the picker: Continue, Pause, Count Backwards.
    static var displayOrder: [IdleMode] { [.ignore, .pauseTimers, .countAsBreak] }
}

// MARK: - Controls (break overlay behavior)

struct BreakControls: Codable, Equatable {
    var fadeInSeconds: Double = 1.0
    var fadeOutSeconds: Double = 1.0

    var showPostpone1: Bool = true
    var postpone1Minutes: Int = 5
    var showPostpone2: Bool = true
    var postpone2Minutes: Int = 10
    var showSkip: Bool = true

    /// Mindfulness: overlay buttons stay disabled for N seconds after the break starts (0 = off).
    var disableButtonsSeconds: Int = 0
    /// Show how many times this break was postponed/skipped/done today.
    var showTodayCounts: Bool = false
    /// Show a button to end the break early (in the overlay).
    var showEndEarly: Bool = false

    /// Control limits per day (0 = no limit).
    var maxPostponesPerDay: Int = 0
    var maxSkipsPerDay: Int = 0

    var postponeOptions: [Int] {
        var options: [Int] = []
        if showPostpone1 { options.append(postpone1Minutes) }
        if showPostpone2 { options.append(postpone2Minutes) }
        return options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fadeInSeconds = try c.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 1.0
        fadeOutSeconds = try c.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 1.0
        showPostpone1 = try c.decodeIfPresent(Bool.self, forKey: .showPostpone1) ?? true
        postpone1Minutes = try c.decodeIfPresent(Int.self, forKey: .postpone1Minutes) ?? 5
        showPostpone2 = try c.decodeIfPresent(Bool.self, forKey: .showPostpone2) ?? true
        postpone2Minutes = try c.decodeIfPresent(Int.self, forKey: .postpone2Minutes) ?? 10
        showSkip = try c.decodeIfPresent(Bool.self, forKey: .showSkip) ?? true
        disableButtonsSeconds = try c.decodeIfPresent(Int.self, forKey: .disableButtonsSeconds) ?? 0
        showTodayCounts = try c.decodeIfPresent(Bool.self, forKey: .showTodayCounts) ?? false
        showEndEarly = try c.decodeIfPresent(Bool.self, forKey: .showEndEarly) ?? false
        maxPostponesPerDay = try c.decodeIfPresent(Int.self, forKey: .maxPostponesPerDay) ?? 0
        maxSkipsPerDay = try c.decodeIfPresent(Int.self, forKey: .maxSkipsPerDay) ?? 0
    }

    init(fadeInSeconds: Double = 1.0, fadeOutSeconds: Double = 1.0,
         showPostpone1: Bool = true, postpone1Minutes: Int = 5,
         showPostpone2: Bool = true, postpone2Minutes: Int = 10,
         showSkip: Bool = true) {
        self.fadeInSeconds = fadeInSeconds
        self.fadeOutSeconds = fadeOutSeconds
        self.showPostpone1 = showPostpone1
        self.postpone1Minutes = postpone1Minutes
        self.showPostpone2 = showPostpone2
        self.postpone2Minutes = postpone2Minutes
        self.showSkip = showSkip
    }
}

// MARK: - Appearance

struct BreakAppearance: Codable, Equatable {
    /// Background color of the break overlay, as a hex string ("#RRGGBB").
    var backgroundHex: String = "#1C1C1E"
    /// Overlay opacity (0.2 – 1.0).
    var opacity: Double = 0.85
    /// Countdown style in the overlay.
    var countdownStyle: CountdownStyle = .ring
    /// Show the overlay on every connected screen.
    var showOnAllScreens: Bool = true
    /// How the Get Ready warning is presented.
    var readyStyle: ReadyStyle = .banner

    enum CountdownStyle: String, Codable, CaseIterable, Identifiable {
        case ring
        case bar
        case digits

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ring: return "Circle countdown"
            case .bar: return "Bar countdown"
            case .digits: return "Numbers only"
            }
        }
    }

    /// Banner: a small floating countdown window — the screen stays usable
    /// (stop music, close windows). Fullscreen: the classic dimmed overlay.
    enum ReadyStyle: String, Codable, CaseIterable, Identifiable {
        case banner
        case fullscreen

        var id: String { rawValue }

        var label: String {
            switch self {
            case .banner: return "Banner (non-blocking)"
            case .fullscreen: return "Fullscreen"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex) ?? "#1C1C1E"
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.85
        countdownStyle = try c.decodeIfPresent(CountdownStyle.self, forKey: .countdownStyle) ?? .ring
        showOnAllScreens = try c.decodeIfPresent(Bool.self, forKey: .showOnAllScreens) ?? true
        readyStyle = try c.decodeIfPresent(ReadyStyle.self, forKey: .readyStyle) ?? .banner
    }

    init(backgroundHex: String = "#1C1C1E", opacity: Double = 0.85,
         countdownStyle: CountdownStyle = .ring, showOnAllScreens: Bool = true,
         readyStyle: ReadyStyle = .banner) {
        self.backgroundHex = backgroundHex
        self.opacity = opacity
        self.countdownStyle = countdownStyle
        self.showOnAllScreens = showOnAllScreens
        self.readyStyle = readyStyle
    }
}

// MARK: - Actions

struct BreakActions: Codable, Equatable {
    init() {}

    /// Name of a system sound to play when the break starts (empty = none).
    var startSound: String = ""
    /// Name of a system sound to play when the break ends (empty = none).
    var endSound: String = ""
    /// Playback volume (0 – 1).
    var volume: Double = 0.7
    /// AppleScript source run when the break starts (empty = none).
    var startAppleScript: String = ""
    /// AppleScript source run when the break ends (empty = none).
    var endAppleScript: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startSound = try c.decodeIfPresent(String.self, forKey: .startSound) ?? ""
        endSound = try c.decodeIfPresent(String.self, forKey: .endSound) ?? ""
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.7
        startAppleScript = try c.decodeIfPresent(String.self, forKey: .startAppleScript) ?? ""
        endAppleScript = try c.decodeIfPresent(String.self, forKey: .endAppleScript) ?? ""
    }
}

// MARK: - Break config

struct BreakConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: BreakKind
    var enabled: Bool = true

    // Identity (Name tab)
    /// Accent color for this break (sidebar pie chart, etc.), as a hex string.
    var labelHex: String = "#2E6B4F"
    /// Show a mini pie chart of postponed/skipped/done today instead of the status dot.
    var showPieChart: Bool = false
    /// Free-form notes about this break.
    var comments: String = ""

    // Schedule
    var scheduleMode: ScheduleMode = .everyMinutes(60)
    /// Where the next interval counts from.
    var anchor: ScheduleAnchor = .lastDue
    /// When the break may be due (optional so older saved configs decode).
    var availability: Availability?
    /// The effective availability (default when unset).
    var avail: Availability {
        get { availability ?? Availability() }
        set { availability = newValue }
    }
    /// Break duration in seconds.
    var durationSec: Int = 600
    /// "Get Ready" countdown before the break locks in, in seconds (0 = off).
    var readySeconds: Int = 10

    // Priority interactions
    /// Skip this break when a higher-priority break is due within N minutes (0 = off).
    var skipIfHigherPriorityDueWithinMin: Int = 0
    /// Reset this break's timer when a break with a higher priority finishes.
    var resetAfterHigherPriorityFinish: Bool = false
    /// Reset this break's countdown after a natural break longer than N seconds (0 = off).
    var resetAfterNaturalLongerThanSec: Int = 0

    // Idle behavior (threshold is global; see AppSettings.naturalBreakThresholdSec)
    var idleMode: IdleMode = .countAsBreak

    var appearance: BreakAppearance = BreakAppearance()
    var controls: BreakControls = BreakControls()
    var actions: BreakActions = BreakActions()

    var duration: TimeInterval { Double(max(5, durationSec)) }

    /// Tolerant decoding: any field added in a later version falls back to
    /// its default instead of wiping the whole config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Break"
        kind = try c.decodeIfPresent(BreakKind.self, forKey: .kind) ?? .custom
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        labelHex = try c.decodeIfPresent(String.self, forKey: .labelHex) ?? "#2E6B4F"
        showPieChart = try c.decodeIfPresent(Bool.self, forKey: .showPieChart) ?? false
        comments = try c.decodeIfPresent(String.self, forKey: .comments) ?? ""
        scheduleMode = try c.decodeIfPresent(ScheduleMode.self, forKey: .scheduleMode) ?? .everyMinutes(60)
        anchor = try c.decodeIfPresent(ScheduleAnchor.self, forKey: .anchor) ?? .lastDue
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec) ?? 600
        readySeconds = try c.decodeIfPresent(Int.self, forKey: .readySeconds) ?? 10
        skipIfHigherPriorityDueWithinMin = try c.decodeIfPresent(Int.self, forKey: .skipIfHigherPriorityDueWithinMin) ?? 0
        resetAfterHigherPriorityFinish = try c.decodeIfPresent(Bool.self, forKey: .resetAfterHigherPriorityFinish) ?? false
        resetAfterNaturalLongerThanSec = try c.decodeIfPresent(Int.self, forKey: .resetAfterNaturalLongerThanSec) ?? 0
        idleMode = try c.decodeIfPresent(IdleMode.self, forKey: .idleMode) ?? .countAsBreak
        appearance = try c.decodeIfPresent(BreakAppearance.self, forKey: .appearance) ?? BreakAppearance()
        controls = try c.decodeIfPresent(BreakControls.self, forKey: .controls) ?? BreakControls()
        actions = try c.decodeIfPresent(BreakActions.self, forKey: .actions) ?? BreakActions()
    }

    init(id: UUID, name: String, kind: BreakKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    static func normal() -> BreakConfig {
        var b = BreakConfig(id: UUID(), name: "Normal", kind: .normal)
        b.scheduleMode = .everyMinutes(60)
        b.durationSec = 600
        b.readySeconds = 10
        b.idleMode = .countAsBreak
        b.appearance = BreakAppearance(backgroundHex: "#1C1C1E", opacity: 0.85,
                                       countdownStyle: .ring, showOnAllScreens: true)
        b.controls = BreakControls(fadeInSeconds: 1.0, fadeOutSeconds: 1.0,
                                   showPostpone1: true, postpone1Minutes: 5,
                                   showPostpone2: true, postpone2Minutes: 10,
                                   showSkip: true)
        return b
    }

    static func micro() -> BreakConfig {
        var b = BreakConfig(id: UUID(), name: "Micro", kind: .micro)
        b.scheduleMode = .everyMinutes(5)
        b.durationSec = 15
        b.readySeconds = 0
        b.idleMode = .countAsBreak
        b.appearance = BreakAppearance(backgroundHex: "#1C1C1E", opacity: 0.7,
                                       countdownStyle: .ring, showOnAllScreens: true)
        b.controls = BreakControls(fadeInSeconds: 0.5, fadeOutSeconds: 0.5,
                                   showPostpone1: true, postpone1Minutes: 5,
                                   showPostpone2: false, postpone2Minutes: 10,
                                   showSkip: true)
        return b
    }
}

// MARK: - Rules

enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case pause
    case skip

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pause: return "Pause breaks"
        case .skip: return "Automatically skip"
        }
    }
}

struct Rule: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var appBundleID: String
    var appName: String
    var action: RuleAction = .skip
    var enabled: Bool = true
    /// Shell detector: when non-empty, the rule is active while this script
    /// exits with status 0 (evaluated with a short timeout, cached).
    var script: String = ""

    var isScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(appBundleID: String, appName: String, action: RuleAction = .skip,
         enabled: Bool = true, script: String = "") {
        self.appBundleID = appBundleID
        self.appName = appName
        self.action = action
        self.enabled = enabled
        self.script = script
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID) ?? ""
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? appBundleID
        action = try c.decodeIfPresent(RuleAction.self, forKey: .action) ?? .skip
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
    }
}

// MARK: - Keyboard shortcuts

/// A recorded global shortcut (Carbon key code + modifier mask).
struct ShortcutSpec: Codable, Equatable {
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0

    var isSet: Bool { keyCode != 0 }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case startNormal
    case startNext
    case postponeNext1
    case postponeNext2
    case skipNext
    case pauseAll
    case resumeAll
    case resetAll
    case stopSound

    var id: String { rawValue }

    var label: String {
        switch self {
        case .startNormal: return "Start Normal Break:"
        case .startNext: return "Start Next Break:"
        case .postponeNext1: return "Postpone Next Break (1):"
        case .postponeNext2: return "Postpone Next Break (2):"
        case .skipNext: return "Skip Next / Current Break:"
        case .pauseAll: return "Pause All Indefinitely:"
        case .resumeAll: return "Resume All Breaks:"
        case .resetAll: return "Reset All Breaks:"
        case .stopSound: return "Stop Sound:"
        }
    }
}

// MARK: - Global settings

enum MenuBarLabelMode: String, Codable, CaseIterable, Identifiable {
    case onlyIcon
    case lastDoneBrief
    case lastDoneFull
    case doneTime
    case lastDuration
    case countdownBrief
    case countdownFull
    case dueTime
    case finishTime
    case nextDuration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onlyIcon: return "Only Icon"
        case .lastDoneBrief: return "Brief Time Since Last Break"
        case .lastDoneFull: return "Full Time Since Last Break"
        case .doneTime: return "Done Time of Last Break"
        case .lastDuration: return "Duration of Last Break"
        case .countdownBrief: return "Brief Countdown to Next Break"
        case .countdownFull: return "Full Countdown to Next Break"
        case .dueTime: return "Due Time of Next Break"
        case .finishTime: return "Finish Time of Next Break"
        case .nextDuration: return "Duration of Next Break"
        }
    }
}

enum NaturalBreakMethod: String, Codable, CaseIterable, Identifiable {
    case none
    case eventSource
    case eventMonitor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .eventSource: return "Event Source"
        case .eventMonitor: return "Event Monitor"
        }
    }
}

struct AppSettings: Codable, Equatable {
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        labelMode = try c.decodeIfPresent(MenuBarLabelMode.self, forKey: .labelMode) ?? .countdownBrief
        statusBarIcon = try c.decodeIfPresent(String.self, forKey: .statusBarIcon) ?? "timer"
        onlyLongBreaksInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .onlyLongBreaksInMenuBar) ?? false
        relativeTimesInSidebar = try c.decodeIfPresent(Bool.self, forKey: .relativeTimesInSidebar) ?? true
        naturalBreakMethod = try c.decodeIfPresent(NaturalBreakMethod.self, forKey: .naturalBreakMethod) ?? .eventSource
        naturalBreakThresholdSec = try c.decodeIfPresent(Int.self, forKey: .naturalBreakThresholdSec) ?? 60
        hiddenItems = try c.decodeIfPresent([String].self, forKey: .hiddenItems) ?? []
        moreOptionsExpanded = try c.decodeIfPresent(Bool.self, forKey: .moreOptionsExpanded) ?? false
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        breakPauses = try c.decodeIfPresent([String: Date].self, forKey: .breakPauses) ?? [:]
        shortcuts = try c.decodeIfPresent([String: ShortcutSpec].self, forKey: .shortcuts) ?? [:]
    }
    /// Global pause end date; `nil` when running, `.distantFuture` for "indefinitely".
    var pausedUntil: Date?
    var launchAtLogin: Bool = false
    var showDockIcon: Bool = false

    // Menu bar status
    var labelMode: MenuBarLabelMode = .countdownBrief
    /// SF Symbol name shown in the menu bar ("none" = no icon).
    var statusBarIcon: String = "timer"
    var onlyLongBreaksInMenuBar: Bool = false

    /// Per-break pause end dates, keyed by UUID string (the Options ▸ Pause Break menu).
    var breakPauses: [String: Date] = [:]

    // Sidebar
    var relativeTimesInSidebar: Bool = true

    // Natural breaks
    var naturalBreakMethod: NaturalBreakMethod = .eventSource
    var naturalBreakThresholdSec: Int = 60

    /// Sidebar/menu items to hide, by key: "pause", "makeDue", "reset", "disable", "delete", "quit".
    var hiddenItems: [String] = []
    func isHidden(_ key: String) -> Bool { hiddenItems.contains(key) }

    /// Shared "More Options" disclosure state — one toggle for all breaks,
    /// persisted across relaunches.
    var moreOptionsExpanded: Bool = false

    var rules: [Rule] = []
    var shortcuts: [String: ShortcutSpec] = [:]

    var isPausedNow: Bool {
        guard let until = pausedUntil else { return false }
        return until > Date()
    }
}

// MARK: - Daily counters

struct DayCounters: Codable, Equatable {
    var day: Date = .distantPast
    var postponed: Int = 0
    var skipped: Int = 0
    var done: Int = 0
}

// MARK: - Persisted root

struct PersistedConfig: Codable {
    var breaks: [BreakConfig] = [BreakConfig.normal(), BreakConfig.micro()]
    var settings: AppSettings = AppSettings()
    var hasLaunchedBefore: Bool = false
    /// Per-break daily counters, keyed by UUID string (JSON-safe).
    var counters: [String: DayCounters] = [:]
    /// Persisted due dates, so the schedule continues across relaunches.
    var scheduleState: [String: Date] = [:]

    /// Tolerant decoding: keys added in later versions default gracefully,
    /// so an older config file never resets the user's setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        breaks = try c.decodeIfPresent([BreakConfig].self, forKey: .breaks)
            ?? [BreakConfig.normal(), BreakConfig.micro()]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        hasLaunchedBefore = try c.decodeIfPresent(Bool.self, forKey: .hasLaunchedBefore) ?? false
        counters = try c.decodeIfPresent([String: DayCounters].self, forKey: .counters) ?? [:]
        scheduleState = try c.decodeIfPresent([String: Date].self, forKey: .scheduleState) ?? [:]
    }

    init(breaks: [BreakConfig] = [BreakConfig.normal(), BreakConfig.micro()],
         settings: AppSettings = AppSettings(),
         hasLaunchedBefore: Bool = false,
         counters: [String: DayCounters] = [:],
         scheduleState: [String: Date] = [:]) {
        self.breaks = breaks
        self.settings = settings
        self.hasLaunchedBefore = hasLaunchedBefore
        self.counters = counters
        self.scheduleState = scheduleState
    }
}

import Foundation
import Combine

/// App-wide state, persisted as JSON in Application Support.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var breaks: [BreakConfig] {
        didSet { persist() }
    }
    @Published var settings: AppSettings {
        didSet { persist() }
    }
    @Published var hasLaunchedBefore: Bool {
        didSet { persist() }
    }
    /// Per-break counters for today (postponed/skipped/done), used for limits and the overlay.
    @Published private(set) var counters: [UUID: DayCounters] {
        didSet { persist() }
    }
    /// Persisted due dates (break UUID string → nextStart), so the schedule
    /// continues across relaunches instead of restarting.
    @Published private(set) var scheduleState: [String: Date] {
        didSet { persist() }
    }

    let supportURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportURL = base.appendingPathComponent("BreakTime", isDirectory: true)

        var loaded: PersistedConfig?
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("config.json")) {
            loaded = try? JSONDecoder().decode(PersistedConfig.self, from: data)
        }
        let config = loaded ?? PersistedConfig()
        breaks = config.breaks
        settings = config.settings
        hasLaunchedBefore = config.hasLaunchedBefore
        counters = Dictionary(uniqueKeysWithValues:
            config.counters.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            })
        scheduleState = config.scheduleState

        if !fm.fileExists(atPath: supportURL.path) {
            try? fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        }
    }

    private func persist() {
        let stringCounters = Dictionary(uniqueKeysWithValues:
            counters.map { ($0.key.uuidString, $0.value) })
        let config = PersistedConfig(breaks: breaks, settings: settings,
                                      hasLaunchedBefore: hasLaunchedBefore,
                                      counters: stringCounters,
                                      scheduleState: scheduleState)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: supportURL.appendingPathComponent("config.json"), options: .atomic)
    }

    func resetToDefaults() {
        breaks = [BreakConfig.normal(), BreakConfig.micro()]
        settings = AppSettings()
        counters = [:]
        scheduleState = [:]
    }

    /// Replaces the persisted due dates (called by the scheduler).
    func saveScheduleState(_ state: [String: Date]) {
        scheduleState = state
    }

    func breakByID(_ id: UUID) -> BreakConfig? {
        breaks.first { $0.id == id }
    }

    // MARK: Daily counters

    func counters(for id: UUID) -> DayCounters {
        var c = counters[id] ?? DayCounters()
        if !Calendar.current.isDateInToday(c.day) {
            c = DayCounters(day: Date())
        }
        return c
    }

    func bumpCounter(_ id: UUID, _ key: WritableKeyPath<DayCounters, Int>) {
        var c = counters(for: id)
        c.day = Date()
        c[keyPath: key] += 1
        counters[id] = c
    }

    /// Whether a limit per day has been reached (limit 0 = no limit).
    func limitReached(_ id: UUID, limit: Int, key: WritableKeyPath<DayCounters, Int>) -> Bool {
        guard limit > 0 else { return false }
        return counters(for: id)[keyPath: key] >= limit
    }
}

import Foundation

// MARK: - Events

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case started
    case finished
    case autoFinished
    case skipped
    case autoSkipped
    case postponed
    case preview
    case naturalReset

    var id: String { rawValue }

    var label: String {
        switch self {
        case .started: return "Started"
        case .finished: return "Finished"
        case .autoFinished: return "Finished (idle)"
        case .skipped: return "Skipped"
        case .autoSkipped: return "Skipped (rule)"
        case .postponed: return "Postponed"
        case .preview: return "Preview"
        case .naturalReset: return "Reset (natural break)"
        }
    }
}

struct ActivityEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var kind: ActivityKind
    var breakID: UUID
    var breakName: String
    var breakKindRaw: String
    /// Effective duration in seconds, for finished breaks.
    var durationSec: Int = 0
    /// For postponed events: how many minutes it was postponed by.
    var postponeMinutes: Int = 0

    var breakKind: BreakKind { BreakKind(rawValue: breakKindRaw) ?? .custom }
}

// MARK: - Day statistics

struct DayStat: Identifiable, Equatable {
    var date: Date  // start of day
    var id: Date { date }

    var total: Int { normalCount + microCount }
    var minutes: Double { (normalMinutes + microMinutes) }

    var normalCount: Int = 0
    var microCount: Int = 0
    var normalMinutes: Double = 0
    var microMinutes: Double = 0
}

// MARK: - Log

/// Fully local activity journal: JSON lines in Application Support.
final class ActivityLog: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []

    /// Cached last completion per break — sidebar rows ask for this every
    /// second, and scanning the whole journal each time showed up in profiles.
    private var lastCompletionCache: [UUID: ActivityEvent] = [:]

    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("activity.jsonl")
        load()
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var loaded: [ActivityEvent] = []
        for line in text.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let event = try? JSONDecoder().decode(ActivityEvent.self, from: data) {
                loaded.append(event)
            }
        }
        events = loaded.sorted { $0.date < $1.date }
        rebuildCompletionCache()
    }

    private func rebuildCompletionCache() {
        lastCompletionCache.removeAll()
        for e in events where e.kind == .finished || e.kind == .autoFinished {
            lastCompletionCache[e.breakID] = e
        }
    }

    private func appendToDisk(_ event: ActivityEvent) {
        guard let enc = try? JSONEncoder().encode(event),
              let line = String(data: enc, encoding: .utf8) else { return }
        let data = (line + "\n").data(using: .utf8)!
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }
        let handle = FileHandle(forWritingAtPath: fileURL.path)
        defer { try? handle?.close() }
        try? handle?.seekToEnd()
        try? handle?.write(contentsOf: data)
    }

    func record(_ kind: ActivityKind, break cfg: BreakConfig,
                durationSec: Int = 0, postponeMinutes: Int = 0) {
        let event = ActivityEvent(date: Date(), kind: kind, breakID: cfg.id,
                                  breakName: cfg.name, breakKindRaw: cfg.kind.rawValue,
                                  durationSec: durationSec, postponeMinutes: postponeMinutes)
        events.append(event)
        if kind == .finished || kind == .autoFinished {
            lastCompletionCache[cfg.id] = event
        }
        appendToDisk(event)
    }

    func clear() {
        events = []
        lastCompletionCache.removeAll()
        try? Data().write(to: fileURL)
    }

    // MARK: Completion history (sidebar status lines)

    /// The kind of the most recent completion (finished / autoFinished), if any.
    func lastCompletion(forBreakID id: UUID) -> ActivityKind? {
        lastCompletionCache[id]?.kind
    }

    /// The most recent completion event (finished / autoFinished), if any.
    func lastCompletionEvent(forBreakID id: UUID) -> ActivityEvent? {
        lastCompletionCache[id]
    }

    func hasEverCompleted(forBreakID id: UUID) -> Bool {
        lastCompletionCache[id] != nil
    }

    // MARK: Aggregation (for Statistics tab)

    /// Finished breaks count toward statistics; previews are excluded.
    private var statEvents: [ActivityEvent] {
        events.filter { $0.kind == .finished || $0.kind == .autoFinished }
    }

    func dayStats(days: Int, endingAt ref: Date = Date()) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: ref)
        var byDay: [Date: DayStat] = [:]
        for offset in (0..<days).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            byDay[day] = DayStat(date: day)
        }
        for e in statEvents {
            let day = cal.startOfDay(for: e.date)
            guard var stat = byDay[day] else { continue }
            switch e.breakKind {
            case .normal, .custom:
                stat.normalCount += 1
                stat.normalMinutes += Double(e.durationSec) / 60
            case .micro:
                stat.microCount += 1
                stat.microMinutes += Double(e.durationSec) / 60
            }
            byDay[day] = stat
        }
        return (0..<days).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).flatMap { byDay[$0] }
        }
    }

    var totalFinished: Int { statEvents.count }

    var totalMinutes: Double {
        Double(statEvents.reduce(0) { $0 + $1.durationSec }) / 60
    }

    func todayStats(ref: Date = Date()) -> (count: Int, minutes: Double) {
        let todayStart = Calendar.current.startOfDay(for: ref)
        let today = statEvents.filter { $0.date >= todayStart }
        let minutes = Double(today.reduce(0) { $0 + $1.durationSec }) / 60
        return (today.count, minutes)
    }

    /// Consecutive days (ending today or yesterday) with at least one finished break.
    func streak(ref: Date = Date()) -> Int {
        let cal = Calendar.current
        let statDays = Set(statEvents.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: ref)
        if !statDays.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
                  statDays.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while statDays.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}
